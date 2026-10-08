finances_app_config <- list(
  motherduck_database = "choco_trail",
  database_schema = "finances_app",
  local_database_path = file.path("data", "local", "finances.duckdb"),
  database_targets = c("local", "motherduck")
)

validate_finances_app_config <- function(config = finances_app_config) {
  identifier_pattern <- "^[A-Za-z_][A-Za-z0-9_]*$"
  identifiers <- unlist(
    config[c("motherduck_database", "database_schema")],
    use.names = TRUE
  )
  invalid_identifiers <- !grepl(identifier_pattern, identifiers)

  if (any(invalid_identifiers)) {
    stop(
      "Database and schema names must be safe SQL identifiers: ",
      paste(names(identifiers)[invalid_identifiers], collapse = ", "),
      call. = FALSE
    )
  }

  if (!identical(config$database_targets, c("local", "motherduck"))) {
    stop("Database targets must be local and motherduck.", call. = FALSE)
  }

  if (
    length(config$local_database_path) != 1L ||
      is.na(config$local_database_path) ||
      !nzchar(trimws(config$local_database_path))
  ) {
    stop("The local database path must be one non-empty value.", call. = FALSE)
  }

  invisible(config)
}

validate_finance_database_target <- function(
  target,
  config = finances_app_config
) {
  validate_finances_app_config(config)

  if (
    length(target) != 1L ||
      is.na(target) ||
      !target %in% config$database_targets
  ) {
    stop(
      "FINANCES_APP_DATABASE_TARGET must be local or motherduck.",
      call. = FALSE
    )
  }

  target
}

finance_database_target <- function(config = finances_app_config) {
  target <- Sys.getenv(
    "FINANCES_APP_DATABASE_TARGET",
    unset = "local"
  )

  validate_finance_database_target(target, config)
}

motherduck_token <- function() {
  token <- Sys.getenv("MOTHERDUCK_TOKEN", unset = "")

  if (!nzchar(token)) {
    stop(
      "MOTHERDUCK_TOKEN is required for a MotherDuck connection. ",
      "Set it in the local environment or deployment secrets.",
      call. = FALSE
    )
  }

  token
}
