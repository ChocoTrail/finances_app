source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))
source(file.path("R", "database_queries.R"))

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
    "Database equivalence requires all three account exports. Missing: ",
    paste(missing_account_files, collapse = ", ")
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
  transactions = pipeline_transactions,
  monthly_allocations = get_monthly_allocations(),
  opening_balance = 0
)

database_path <- file.path("data", "local", "finances.duckdb")

if (!file.exists(database_path)) {
  stop(
    "The local database does not exist. Run ",
    "scripts/04_initialize_database.R first."
  )
}

connection <- connect_finance_database(database_path, read_only = TRUE)
on.exit(disconnect_finance_database(connection), add = TRUE)

equivalence_results <- compare_pipeline_to_database(
  connection = connection,
  pipeline_transactions = pipeline_transactions,
  pipeline_rollover_ledger = pipeline_rollover_ledger,
  pipeline_merchant_rules = get_merchant_category_rules()
)

print(equivalence_results)
message("The local database reproduces every protected pipeline result.")
