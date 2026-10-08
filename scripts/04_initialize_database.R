source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))

database_path <- file.path("data", "local", "finances.duckdb")

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
    "The initial database requires all three account exports. Missing: ",
    paste(missing_account_files, collapse = ", ")
  )
}

transactions <- purrr::map2(
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

connection <- connect_finance_database(database_path)
on.exit(disconnect_finance_database(connection), add = TRUE)

applied_migrations <- apply_database_migrations(connection)
seed_summary <- seed_initial_database(connection, transactions)

message(
  "Initialized ",
  database_path,
  " with ",
  seed_summary$transaction_count,
  " transactions across ",
  seed_summary$import_count,
  " account imports."
)

print(applied_migrations)
print(as.data.frame(seed_summary))
