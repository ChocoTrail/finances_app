source(file.path("R", "config.R"))
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

with_environment_variable <- function(name, value, code) {
  prior_value <- Sys.getenv(name, unset = NA_character_)
  on.exit({
    if (is.na(prior_value)) {
      Sys.unsetenv(name)
    } else {
      do.call(Sys.setenv, setNames(list(prior_value), name))
    }
  }, add = TRUE)

  if (is.na(value)) {
    Sys.unsetenv(name)
  } else {
    do.call(Sys.setenv, setNames(list(value), name))
  }

  force(code)
}

run_test("database target defaults locally and validates overrides", {
  with_environment_variable("FINANCES_APP_DATABASE_TARGET", NA_character_, {
    expect_equal(
      finance_database_target(),
      "local",
      "Expected local database use by default."
    )
  })

  with_environment_variable("FINANCES_APP_DATABASE_TARGET", "motherduck", {
    expect_equal(
      finance_database_target(),
      "motherduck",
      "Expected the explicit MotherDuck target."
    )
  })

  with_environment_variable("FINANCES_APP_DATABASE_TARGET", "remote", {
    expect_error(
      finance_database_target(),
      "must be local or motherduck",
      "Expected invalid database targets to fail."
    )
  })
})

run_test("MotherDuck token validation never supplies a fallback", {
  with_environment_variable("MOTHERDUCK_TOKEN", NA_character_, {
    expect_error(
      motherduck_token(),
      "MOTHERDUCK_TOKEN is required",
      "Expected a missing MotherDuck token to fail."
    )
  })
})

run_test("application connector opens the configured local database", {
  database_path <- tempfile(fileext = ".duckdb")
  on.exit(unlink(database_path), add = TRUE)
  config <- finances_app_config
  config$local_database_path <- database_path

  connection <- connect_app_finance_database(
    config,
    target = "local"
  )
  on.exit(disconnect_finance_database(connection), add = TRUE)

  expect_equal(
    DBI::dbIsValid(connection),
    TRUE,
    "Expected a valid local application connection."
  )
  expect_equal(
    file.exists(database_path),
    TRUE,
    "Expected the configured local database file to be created."
  )
})

run_test("schema selection isolates the complete finance contract", {
  connection <- connect_finance_database(":memory:")
  on.exit(disconnect_finance_database(connection), add = TRUE)
  config <- finances_app_config
  config$motherduck_database <- DBI::dbGetQuery(
    connection,
    "SELECT current_database() AS database_name"
  )$database_name[[1]]
  config$database_schema <- "finance_contract_test"

  expect_equal(
    finance_schema_exists(connection, config),
    FALSE,
    "The test schema should not exist before creation."
  )
  create_and_select_finance_schema(connection, config)
  apply_database_migrations(connection)
  contract <- finance_database_contract(connection, config)

  expect_equal(
    finance_schema_exists(connection, config),
    TRUE,
    "The finance schema should exist after creation."
  )
  expect_equal(
    contract$missing_tables,
    character(),
    "Every designed finance table should be present."
  )
  expect_equal(
    contract$unexpected_tables,
    character(),
    "The finance schema should not contain unexpected tables."
  )
})

message("All MotherDuck configuration tests passed.")
