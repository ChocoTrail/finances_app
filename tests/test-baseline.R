source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))

expect_equal <- function(actual, expected, label, tolerance = 1e-8) {
  comparison <- all.equal(
    actual,
    expected,
    tolerance = tolerance,
    check.attributes = FALSE
  )

  if (!isTRUE(comparison)) {
    stop(
      label,
      "\n",
      paste(comparison, collapse = "\n"),
      call. = FALSE
    )
  }
}

expect_error <- function(code, pattern, label) {
  error_message <- tryCatch(
    {
      force(code)
      NA_character_
    },
    error = function(error) conditionMessage(error)
  )

  if (is.na(error_message) || !grepl(pattern, error_message, fixed = TRUE)) {
    stop(label, call. = FALSE)
  }
}

run_test <- function(name, code) {
  force(code)
  message("PASS: ", name)
}

run_test("monthly allocations retain the agreed baseline", {
  allocations <- get_monthly_allocations()

  expect_equal(nrow(allocations), 5L, "Expected five fixed categories.")
  expect_equal(
    sum(allocations$monthly_allocation),
    6300,
    "Expected the initial monthly allocation to total $6,300."
  )
})

run_test("account exports require the exact source schema and keep posted rows", {
  export_file <- tempfile(fileext = ".csv")
  on.exit(unlink(export_file), add = TRUE)

  readr::write_csv(
    tibble::tibble(
      DATE = c("04/01/2026", "04/02/2026"),
      DESCRIPTION = c(" POSTED MERCHANT ", "PENDING MERCHANT"),
      AMOUNT = c("-10.25", "-99.00"),
      `CHECK #` = c("", ""),
      STATUS = c("Posted", "Pending")
    ),
    export_file
  )

  imported <- suppressMessages(
    read_account_export(export_file, "checking")
  )

  expect_equal(nrow(imported), 1L, "Expected only posted rows to remain.")
  expect_equal(
    imported$description,
    "POSTED MERCHANT",
    "Expected descriptions to be standardized."
  )

  invalid_file <- tempfile(fileext = ".csv")
  on.exit(unlink(invalid_file), add = TRUE)
  readr::write_csv(
    tibble::tibble(
      DATE = "04/01/2026",
      DESCRIPTION = "MERCHANT",
      AMOUNT = "-10.25",
      STATUS = "Posted"
    ),
    invalid_file
  )

  expect_error(
    suppressMessages(read_account_export(invalid_file, "checking")),
    "Unexpected columns",
    "Expected an invalid export schema to fail."
  )
})

run_test("identical transactions receive durable duplicate sequences", {
  transactions <- tibble::tibble(
    account = c("checking", "checking"),
    source_file = c("checking.csv", "checking.csv"),
    source_row_number = c(2L, 5L),
    date = as.Date(c("2026-04-01", "2026-04-01")),
    description = c("SAME MERCHANT", "SAME MERCHANT"),
    amount = c(-12.34, -12.34),
    check_number = c(NA_character_, NA_character_)
  )

  identified <- add_transaction_identity(transactions)

  expect_equal(
    identified$duplicate_sequence,
    c(1L, 2L),
    "Expected duplicate sequence to follow source row order."
  )
})

run_test("saved transaction decisions override reusable merchant defaults", {
  transaction <- tibble::tibble(
    account = "credit_card_jacob",
    source_file = "card.csv",
    source_row_number = 1L,
    date = as.Date("2026-04-01"),
    description = "TARGET STORE",
    amount = -25,
    check_number = NA_character_,
    duplicate_sequence = 1L
  ) |>
    classify_transaction_types() |>
    apply_category_rules(get_merchant_category_rules())

  override <- transaction |>
    dplyr::transmute(
      account,
      date,
      description,
      amount,
      check_number,
      duplicate_sequence,
      is_reimbursable = FALSE,
      budget_category_override = "Food & living expenses",
      override_note = "Synthetic test"
    )

  overridden <- apply_transaction_overrides(transaction, override)

  expect_equal(
    overridden$budget_category,
    "Food & living expenses",
    "Expected the saved category decision to win."
  )
  expect_equal(
    overridden$category_source,
    "transaction_override",
    "Expected the assignment source to record the override."
  )
})

run_test("zero-transaction months receive allocations and roll forward", {
  transactions <- tibble::tibble(
    date = as.Date(c("2026-04-10", "2026-06-10")),
    budget_category = c("Example", "Example"),
    budget_amount = c(40, 10)
  )
  allocations <- tibble::tibble(
    budget_category = "Example",
    monthly_allocation = 100
  )

  ledger <- build_monthly_rollover_ledger(
    transactions,
    allocations,
    opening_balance = 20
  )

  expect_equal(
    ledger$month,
    as.Date(c("2026-04-01", "2026-05-01", "2026-06-01")),
    "Expected every calendar month in the range."
  )
  expect_equal(
    ledger$cumulative_rollover_balance,
    c(80, 180, 270),
    "Expected allocation and rollover in the empty month."
  )
})

baseline_files <- c(
  file.path("data", "raw", "Checking.csv"),
  file.path("data", "raw", "CreditCardKendra.csv"),
  file.path("data", "raw", "CreditCardJacob.csv"),
  file.path("data", "private", "transaction_overrides.csv")
)

if (all(file.exists(baseline_files))) {
  run_test("private April through September 2026 baseline remains unchanged", {
    account_files <- tibble::tribble(
      ~account, ~file_path,
      "checking", baseline_files[[1]],
      "credit_card_kendra", baseline_files[[2]],
      "credit_card_jacob", baseline_files[[3]]
    )

    transactions <- purrr::map2(
      account_files$file_path,
      account_files$account,
      ~ suppressMessages(read_account_export(.x, .y))
    ) |>
      purrr::list_rbind() |>
      add_transaction_identity() |>
      classify_transaction_types() |>
      apply_category_rules(get_merchant_category_rules()) |>
      apply_transaction_overrides(
        suppressMessages(read_transaction_overrides(baseline_files[[4]]))
      ) |>
      calculate_budget_amounts()

    account_counts <- transactions |>
      dplyr::count(account, name = "transaction_count") |>
      dplyr::arrange(account)

    expect_equal(
      account_counts$transaction_count,
      c(101L, 261L, 301L),
      "The account-level posted transaction counts changed."
    )
    expect_equal(
      nrow(transactions),
      663L,
      "The total posted transaction count changed."
    )
    expect_equal(
      sum(transactions$duplicate_sequence == 2L),
      1L,
      "The genuine identical-transaction duplicate changed."
    )
    expect_equal(
      sum(transactions$is_reimbursable),
      21L,
      "The saved reimbursable decisions changed."
    )

    category_totals <- transactions |>
      dplyr::filter(!is.na(budget_category)) |>
      dplyr::group_by(budget_category) |>
      dplyr::summarize(net_spending = sum(budget_amount), .groups = "drop") |>
      dplyr::arrange(budget_category)

    expected_category_totals <- tibble::tribble(
      ~budget_category, ~net_spending,
      "Food & living expenses", 7262.33,
      "Housing & related expenses", 25857.88,
      "Personal & discretionary", 11859.25,
      "Rainy day & irregular expenses", 1225.36,
      "Transportation", 2129.75
    )

    expect_equal(
      category_totals,
      expected_category_totals,
      "The validated category totals changed."
    )

    rollover_totals <- build_monthly_rollover_ledger(
      transactions,
      get_monthly_allocations(),
      opening_balance = 0
    ) |>
      summarize_monthly_rollover_ledger()

    expect_equal(
      rollover_totals$month,
      as.Date(c(
        "2026-04-01", "2026-05-01", "2026-06-01",
        "2026-07-01", "2026-08-01", "2026-09-01"
      )),
      "The validated budget month range changed."
    )
    expect_equal(
      rollover_totals$net_spending,
      c(10517.74, 9143.28, 7350.22, 5177.47, 9625.50, 6520.36),
      "The validated monthly spending totals changed."
    )
    expect_equal(
      rollover_totals$cumulative_rollover_balance,
      c(-4217.74, -7061.02, -8111.24, -6988.71, -10314.21, -10534.57),
      "The validated monthly rollover balances changed."
    )
  })
} else {
  message("SKIP: private baseline files are not available")
}

message("All baseline tests passed.")
