source(file.path("R", "config.R"))
source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))
source(file.path("R", "database_queries.R"))

arguments <- commandArgs(trailingOnly = TRUE)
write_to_motherduck <- identical(arguments, "--write")

if (length(arguments) > 0L && !write_to_motherduck) {
  stop(
    "Usage: Rscript scripts/06_initialize_motherduck.R [--write]",
    call. = FALSE
  )
}

account_files <- tibble::tribble(
  ~account, ~file_path,
  "checking", file.path("data", "raw", "Checking.csv"),
  "credit_card_kendra", file.path("data", "raw", "CreditCardKendra.csv"),
  "credit_card_jacob", file.path("data", "raw", "CreditCardJacob.csv")
)

missing_account_files <- account_files$file_path[
  !file.exists(account_files$file_path)
]

if (length(missing_account_files) > 0) {
  stop(
    "MotherDuck initialization requires all three account exports. Missing: ",
    paste(missing_account_files, collapse = ", "),
    call. = FALSE
  )
}

pipeline_transactions <- purrr::map2(
  account_files$file_path,
  account_files$account,
  read_account_export
) |>
  purrr::list_rbind() |>
  add_transaction_identity() |>
  classify_transaction_types() |>
  apply_category_rules(get_merchant_category_rules()) |>
  apply_transaction_overrides(
    read_transaction_overrides(
      file.path("data", "private", "transaction_overrides.csv")
    )
  ) |>
  calculate_budget_amounts()

pipeline_rollover_ledger <- build_monthly_rollover_ledger(
  pipeline_transactions,
  get_monthly_allocations(),
  opening_balance = 0
)

planned_summary <- tibble::tibble(
  database = finances_app_config$motherduck_database,
  schema = finances_app_config$database_schema,
  transaction_count = nrow(pipeline_transactions),
  reimbursable_count = sum(pipeline_transactions$is_reimbursable),
  merchant_rule_count = nrow(get_merchant_category_rules()),
  budget_version_count = 1L,
  allocation_count = nrow(get_monthly_allocations())
)

message(
  if (write_to_motherduck) {
    "MotherDuck write requested."
  } else {
    "MotherDuck preview only; no schema or data will be changed."
  }
)
print(planned_summary)

connection <- connect_motherduck_finance_database()
on.exit(disconnect_finance_database(connection), add = TRUE)

schema_exists <- finance_schema_exists(connection)
message(
  "Target schema ",
  finances_app_config$motherduck_database,
  ".",
  finances_app_config$database_schema,
  if (schema_exists) " exists." else " does not exist."
)

if (!write_to_motherduck) {
  if (schema_exists) {
    select_finance_schema(connection)
    migration_status <- database_migration_status(connection)
    contract <- finance_database_contract(connection)
    print(migration_status)
    print(contract$objects, row.names = FALSE)
    print(data.frame(
      table_name = names(contract$row_counts),
      row_count = unname(contract$row_counts)
    ), row.names = FALSE)
  }

  message(
    "Preview complete. Review the target and counts, then rerun with --write ",
    "to create or initialize the schema."
  )
} else {
  create_and_select_finance_schema(connection)
  apply_database_migrations(connection)
  print(database_migration_status(connection))

  if (database_has_seed_data(connection)) {
    message(
      "The MotherDuck schema already contains data; initialization was not ",
      "reapplied. Validating the existing contents instead."
    )
  } else {
    seed_initial_database(connection, pipeline_transactions)
    message("The initial finance history was written to MotherDuck.")
  }

  equivalence_results <- compare_pipeline_to_database(
    connection,
    pipeline_transactions,
    pipeline_rollover_ledger,
    get_merchant_category_rules()
  )
  contract <- finance_database_contract(connection)

  if (
    length(contract$missing_tables) > 0 ||
      length(contract$unexpected_tables) > 0
  ) {
    stop("The MotherDuck schema does not match the expected table contract.")
  }

  print(equivalence_results)
  print(data.frame(
    table_name = names(contract$row_counts),
    row_count = unname(contract$row_counts)
  ), row.names = FALSE)
  message("MotherDuck initialization and equivalence validation succeeded.")
}
