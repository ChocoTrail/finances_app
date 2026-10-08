project_root <- normalizePath(file.path("..", ".."), mustWork = TRUE)

source(file.path(project_root, "R", "transaction_pipeline.R"))
source(file.path(project_root, "R", "budget_config.R"))
source(file.path(project_root, "R", "database.R"))
source(file.path(project_root, "R", "database_queries.R"))
source(file.path(project_root, "R", "import_service.R"))
source(file.path(project_root, "R", "prototype_contracts.R"))
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

write_prototype_export <- function(rows) {
  file_path <- tempfile(fileext = ".csv")
  readr::write_csv(rows, file_path, na = "")
  file_path
}
