source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))
source(file.path("R", "database_queries.R"))

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

run_test <- function(name, code) {
  force(code)
  message("PASS: ", name)
}

with_test_database <- function(code) {
  connection <- connect_finance_database(":memory:")
  on.exit(disconnect_finance_database(connection), add = TRUE)
  evaluation_environment <- list2env(
    list(connection = connection),
    parent = parent.frame()
  )
  eval(substitute(code), envir = evaluation_environment)
}

build_synthetic_transactions <- function() {
  tibble::tibble(
    account = c("credit_card_jacob", "credit_card_jacob"),
    source_file = c("CreditCardJacob.csv", "CreditCardJacob.csv"),
    source_row_number = c(1L, 2L),
    date = as.Date(c("2026-04-05", "2026-06-05")),
    description = c("TARGET STORE", "TARGET STORE"),
    amount = c(-25, -25),
    check_number = c(NA_character_, NA_character_)
  ) |>
    add_transaction_identity() |>
    classify_transaction_types() |>
    apply_category_rules(get_merchant_category_rules()) |>
    apply_transaction_overrides(
      read_transaction_overrides(tempfile(fileext = ".csv"))
    ) |>
    calculate_budget_amounts()
}

run_test("effective-month versions preserve earlier allocations", {
  with_test_database({
    apply_database_migrations(connection)
    seed_initial_database(connection, build_synthetic_transactions())

    second_version <- tibble::tibble(
      budget_version_id = "budget_2026_05",
      effective_month = as.Date("2026-05-01"),
      total_monthly_budget = 6300,
      created_at = as.POSIXct("2026-05-01 00:00:00", tz = "UTC")
    )
    second_allocations <- tibble::tibble(
      budget_version_id = "budget_2026_05",
      category_code = finance_category_codes,
      monthly_allocation = c(2800, 500, 1230, 1120, 650)
    )

    DBI::dbWithTransaction(connection, {
      DBI::dbAppendTable(connection, "budget_versions", second_version)
      DBI::dbAppendTable(connection, "budget_allocations", second_allocations)
    })

    ledger <- build_database_rollover_ledger(
      connection,
      through_month = as.Date("2026-06-01")
    )
    personal_ledger <- ledger |>
      dplyr::filter(budget_category == "Personal & discretionary")

    expect_equal(
      personal_ledger$monthly_allocation,
      c(1100, 1120, 1120),
      "A later budget version must not rewrite April."
    )
    expect_equal(
      personal_ledger$net_spending,
      c(25, 0, 25),
      "A zero-transaction month must remain in the ledger."
    )
    expect_equal(
      personal_ledger$cumulative_rollover_balance,
      c(1075, 2195, 3290),
      "The versioned personal allocation did not roll forward correctly."
    )
  })
})

run_test("category-specific opening balances feed independent rollovers", {
  with_test_database({
    apply_database_migrations(connection)
    seed_initial_database(connection, build_synthetic_transactions())
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE budget_opening_balances",
        "SET opening_balance = 50",
        "WHERE category_code = 'housing'"
      )
    )

    april_ledger <- build_database_rollover_ledger(
      connection,
      through_month = as.Date("2026-04-01")
    )
    housing_april <- april_ledger |>
      dplyr::filter(budget_category == "Housing & related expenses")
    transportation_april <- april_ledger |>
      dplyr::filter(budget_category == "Transportation")

    expect_equal(
      housing_april$opening_balance,
      50,
      "Housing should use its configured opening balance."
    )
    expect_equal(
      housing_april$cumulative_rollover_balance,
      2870,
      "Housing should add its April allocation to its opening balance."
    )
    expect_equal(
      transportation_april$opening_balance,
      0,
      "One category's opening balance must not affect another category."
    )
  })
})

baseline_files <- c(
  file.path("data", "raw", "Checking.csv"),
  file.path("data", "raw", "CreditCardKendra.csv"),
  file.path("data", "raw", "CreditCardJacob.csv"),
  file.path("data", "private", "transaction_overrides.csv"),
  file.path("data", "local", "finances.duckdb")
)

if (all(file.exists(baseline_files))) {
  run_test("the local database is fully equivalent to the protected pipeline", {
    account_files <- tibble::tribble(
      ~account, ~file_path,
      "checking", baseline_files[[1]],
      "credit_card_kendra", baseline_files[[2]],
      "credit_card_jacob", baseline_files[[3]]
    )

    pipeline_transactions <- purrr::map2(
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

    pipeline_rollover_ledger <- build_monthly_rollover_ledger(
      pipeline_transactions,
      get_monthly_allocations(),
      opening_balance = 0
    )

    connection <- connect_finance_database(baseline_files[[5]], read_only = TRUE)
    on.exit(disconnect_finance_database(connection), add = TRUE)

    comparison <- compare_pipeline_to_database(
      connection,
      pipeline_transactions,
      pipeline_rollover_ledger,
      get_merchant_category_rules()
    )

    expect_equal(
      comparison$comparison,
      c(
        "transactions",
        "category_spending",
        "rollover_ledger",
        "merchant_rules"
      ),
      "The database equivalence checks changed."
    )
    expect_equal(
      comparison$passed,
      rep(TRUE, 4),
      "Every database equivalence check must pass."
    )
  })
} else {
  message("SKIP: private baseline files or the local database are unavailable")
}

message("All database equivalence tests passed.")
