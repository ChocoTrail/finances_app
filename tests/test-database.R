source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))

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
    account = c("checking", "checking"),
    source_file = c("Checking.csv", "Checking.csv"),
    source_row_number = c(1L, 2L),
    date = as.Date(c("2026-04-05", "2026-04-05")),
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

run_test("migrations create the complete schema and are idempotent", {
  with_test_database({
    first_run <- apply_database_migrations(connection)
    second_run <- apply_database_migrations(connection)
    migration_status <- database_migration_status(connection)
    expected_tables <- sort(c(
      "budget_allocations",
      "budget_opening_balances",
      "budget_versions",
      "categories",
      "decision_audit_log",
      "imports",
      "merchant_rules",
      "schema_migrations",
      "transaction_decisions",
      "transaction_sightings",
      "transactions"
    ))

    expect_equal(nrow(first_run), 2L, "Expected two applied migrations.")
    expect_equal(second_run, first_run, "Expected migration reruns to be safe.")
    expect_equal(
      migration_status$status,
      c("applied", "applied"),
      "Expected every available migration to be applied."
    )
    expect_equal(
      sort(DBI::dbListTables(connection)),
      expected_tables,
      "The migrated table list changed."
    )
  })
})

run_test("budget allocations must match the fixed total and categories", {
  allocations <- get_monthly_allocations()

  expect_equal(
    validate_budget_allocations(allocations, 6300),
    TRUE,
    "Expected the agreed allocation to validate."
  )
  expect_error(
    validate_budget_allocations(allocations, 6200),
    "sum exactly",
    "Expected a mismatched monthly total to fail."
  )
  expect_error(
    validate_budget_allocations(allocations[-1, ], 6300),
    "each fixed category",
    "Expected a missing fixed category to fail."
  )
})

run_test("the initial seed writes durable identities and configuration", {
  with_test_database({
    apply_database_migrations(connection)
    transactions <- build_synthetic_transactions()
    seed_summary <- seed_initial_database(connection, transactions)

    expect_equal(
      unname(unlist(seed_summary[c(
        "category_count",
        "import_count",
        "transaction_count",
        "sighting_count",
        "decision_count",
        "merchant_rule_count",
        "budget_version_count",
        "allocation_count",
        "opening_balance_count",
        "audit_count"
      )])),
      c(5L, 1L, 2L, 2L, 2L, 21L, 1L, 5L, 5L, 29L),
      "The initial seed row counts changed."
    )

    stored_transactions <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT transaction_id, composite_identity, duplicate_sequence",
        "FROM transactions ORDER BY duplicate_sequence"
      )
    )

    expect_equal(
      stored_transactions$duplicate_sequence,
      c(1L, 2L),
      "Expected identical transactions to remain distinct."
    )
    expect_equal(
      length(unique(stored_transactions$transaction_id)),
      2L,
      "Expected a stable unique ID for each duplicate sequence."
    )

    expect_error(
      seed_initial_database(connection, transactions),
      "already contains seed data",
      "Expected reseeding to refuse to overwrite live configuration."
    )
    expect_equal(
      DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM transactions")$n,
      2,
      "A refused reseed must not change transaction rows."
    )
  })
})

baseline_files <- c(
  file.path("data", "raw", "Checking.csv"),
  file.path("data", "raw", "CreditCardKendra.csv"),
  file.path("data", "raw", "CreditCardJacob.csv"),
  file.path("data", "private", "transaction_overrides.csv")
)

if (all(file.exists(baseline_files))) {
  run_test("the complete private baseline seeds into local DuckDB", {
    with_test_database({
      apply_database_migrations(connection)

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

      seed_summary <- seed_initial_database(connection, transactions)

      expect_equal(
        seed_summary$transaction_count,
        663L,
        "The complete transaction seed count changed."
      )
      expect_equal(
        DBI::dbGetQuery(
          connection,
          paste(
            "SELECT count(*) AS n FROM transaction_decisions",
            "WHERE is_reimbursable"
          )
        )$n,
        21,
        "The saved reimbursable decisions changed during database seeding."
      )
      expect_equal(
        DBI::dbGetQuery(
          connection,
          "SELECT count(*) AS n FROM imports"
        )$n,
        3,
        "Expected one initial import per supported account."
      )
    })
  })
} else {
  message("SKIP: private baseline files are not available")
}

message("All database tests passed.")
