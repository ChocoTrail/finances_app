project_root <- normalizePath(file.path("..", ".."), mustWork = TRUE)

source(file.path(project_root, "R", "transaction_pipeline.R"))
source(file.path(project_root, "R", "budget_config.R"))
source(file.path(project_root, "R", "database.R"))
source(file.path(project_root, "R", "database_queries.R"))
source(file.path(project_root, "R", "import_service.R"))
source(file.path(project_root, "R", "prototype_contracts.R"))
source(file.path(project_root, "R", "overview_service.R"))
source(file.path(project_root, "R", "app_server.R"))

empty_prototype_seed <- function() {
  tibble::tibble(
    account = character(),
    source_file = character(),
    source_row_number = integer(),
    date = as.Date(character()),
    description = character(),
    amount = double(),
    check_number = character(),
    duplicate_sequence = integer(),
    transaction_type = character(),
    budget_category = character(),
    category_source = character(),
    category_rule = character(),
    is_reimbursable = logical(),
    override_note = character(),
    budget_amount = double()
  )
}

prototype_connection_factory <- function() {
  connection <- connect_finance_database(":memory:")
  apply_database_migrations(
    connection,
    file.path(project_root, "migrations")
  )
  seed_initial_database(connection, empty_prototype_seed())
  connection
}

overview_seed <- function() {
  tibble::tibble(
    account = c(
      "checking",
      "credit_card_jacob",
      "credit_card_kendra"
    ),
    source_file = c(
      "Checking.csv",
      "CreditCardJacob.csv",
      "CreditCardKendra.csv"
    ),
    source_row_number = rep(1L, 3),
    date = as.Date(c("2026-04-05", "2026-04-10", "2026-05-03")),
    description = c("HOUSING PAYMENT", "TARGET STORE", "TARGET RETURN"),
    amount = c(-1000, -25, 10),
    check_number = rep(NA_character_, 3),
    duplicate_sequence = rep(1L, 3),
    transaction_type = c("expense", "expense", "refund"),
    budget_category = c(
      "Housing & related expenses",
      "Personal & discretionary",
      "Personal & discretionary"
    ),
    category_source = rep("merchant_rule", 3),
    category_rule = c("housing", "variable_retailers", "variable_retailers"),
    is_reimbursable = rep(FALSE, 3),
    override_note = rep(NA_character_, 3),
    budget_amount = c(1000, 25, -10)
  )
}

overview_connection_factory <- function() {
  connection <- connect_finance_database(":memory:")
  apply_database_migrations(
    connection,
    file.path(project_root, "migrations")
  )
  seed_initial_database(
    connection,
    overview_seed(),
    initialized_at = as.POSIXct("2026-05-06 12:00:00", tz = "UTC")
  )
  connection
}

write_prototype_export <- function(rows) {
  file_path <- tempfile(fileext = ".csv")
  readr::write_csv(rows, file_path, na = "")
  file_path
}
