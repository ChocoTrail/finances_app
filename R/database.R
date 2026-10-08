finance_category_codes <- c(
  "housing",
  "transportation",
  "food_living",
  "personal_discretionary",
  "rainy_day"
)

finance_category_names <- c(
  "Housing & related expenses",
  "Transportation",
  "Food & living expenses",
  "Personal & discretionary",
  "Rainy day & irregular expenses"
)

get_category_seed <- function() {
  tibble::tibble(
    category_code = finance_category_codes,
    display_name = finance_category_names,
    sort_order = seq_along(finance_category_codes),
    is_active = TRUE
  )
}

category_name_to_code <- function(category_name) {
  category_codes <- stats::setNames(
    finance_category_codes,
    finance_category_names
  )
  unname(category_codes[category_name])
}

connect_finance_database <- function(
  database_path = file.path("data", "local", "finances.duckdb"),
  read_only = FALSE
) {
  if (!identical(database_path, ":memory:") && !read_only) {
    dir.create(dirname(database_path), recursive = TRUE, showWarnings = FALSE)
  }

  DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = database_path,
    read_only = read_only
  )
}

connect_local_finance_database <- function(
  config = finances_app_config,
  read_only = FALSE
) {
  validate_finances_app_config(config)
  connect_finance_database(
    config$local_database_path,
    read_only = read_only
  )
}

connect_motherduck_finance_database <- function(
  config = finances_app_config
) {
  validate_finances_app_config(config)
  token <- motherduck_token()
  prior_extension_token <- Sys.getenv(
    "motherduck_token",
    unset = NA_character_
  )

  on.exit({
    if (is.na(prior_extension_token)) {
      Sys.unsetenv("motherduck_token")
    } else {
      do.call(
        Sys.setenv,
        setNames(list(prior_extension_token), "motherduck_token")
      )
    }
  }, add = TRUE)

  do.call(Sys.setenv, setNames(list(token), "motherduck_token"))
  connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")

  tryCatch(
    {
      DBI::dbExecute(connection, "INSTALL motherduck")
      DBI::dbExecute(connection, "LOAD motherduck")

      database_identifier <- DBI::dbQuoteIdentifier(
        connection,
        config$motherduck_database
      )
      attach_statement <- sprintf(
        "ATTACH 'md:%s' AS %s",
        config$motherduck_database,
        database_identifier
      )

      DBI::dbExecute(connection, attach_statement)
      DBI::dbExecute(connection, paste("USE", database_identifier))
      connection
    },
    error = function(error) {
      disconnect_finance_database(connection)
      stop(
        "Could not connect to MotherDuck: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
}

connect_app_finance_database <- function(
  config = finances_app_config,
  target = finance_database_target(config),
  read_only = FALSE
) {
  target <- validate_finance_database_target(target, config)

  connection <- switch(
    target,
    local = connect_local_finance_database(config, read_only),
    motherduck = connect_motherduck_finance_database(config)
  )

  if (target == "motherduck") {
    tryCatch(
      select_finance_schema(connection, config),
      error = function(error) {
        disconnect_finance_database(connection)
        stop(conditionMessage(error), call. = FALSE)
      }
    )
  }

  connection
}

disconnect_finance_database <- function(connection) {
  if (!is.null(connection) && DBI::dbIsValid(connection)) {
    DBI::dbDisconnect(connection, shutdown = TRUE)
  }

  invisible(NULL)
}

finance_schema_exists <- function(
  connection,
  config = finances_app_config
) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT count(*) AS schema_count",
      "FROM information_schema.schemata",
      "WHERE catalog_name = ? AND schema_name = ?"
    ),
    params = list(config$motherduck_database, config$database_schema)
  )$schema_count[[1]] > 0
}

create_and_select_finance_schema <- function(
  connection,
  config = finances_app_config
) {
  validate_finances_app_config(config)
  schema_identifier <- DBI::dbQuoteIdentifier(
    connection,
    config$database_schema
  )

  DBI::dbExecute(
    connection,
    paste("CREATE SCHEMA IF NOT EXISTS", schema_identifier)
  )
  DBI::dbExecute(
    connection,
    paste("SET schema =", DBI::dbQuoteString(connection, config$database_schema))
  )

  invisible(connection)
}

select_finance_schema <- function(
  connection,
  config = finances_app_config
) {
  if (!finance_schema_exists(connection, config)) {
    stop(
      "MotherDuck schema does not exist: ",
      config$motherduck_database,
      ".",
      config$database_schema,
      call. = FALSE
    )
  }

  DBI::dbExecute(
    connection,
    paste("SET schema =", DBI::dbQuoteString(connection, config$database_schema))
  )

  invisible(connection)
}

finance_database_contract <- function(
  connection,
  config = finances_app_config
) {
  objects <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT table_name, table_type",
      "FROM information_schema.tables",
      "WHERE table_catalog = ? AND table_schema = ?",
      "ORDER BY table_name"
    ),
    params = list(config$motherduck_database, config$database_schema)
  )

  expected_tables <- c(
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
  )
  present_tables <- objects$table_name
  row_counts <- stats::setNames(
    rep(NA_real_, length(expected_tables)),
    expected_tables
  )

  for (table_name in intersect(expected_tables, present_tables)) {
    quoted_table <- DBI::dbQuoteIdentifier(connection, table_name)
    row_counts[[table_name]] <- DBI::dbGetQuery(
      connection,
      paste("SELECT count(*) AS row_count FROM", quoted_table)
    )$row_count[[1]]
  }

  list(
    objects = objects,
    missing_tables = setdiff(expected_tables, present_tables),
    unexpected_tables = setdiff(present_tables, expected_tables),
    row_counts = row_counts
  )
}

get_migration_files <- function(migrations_path = "migrations") {
  migration_files <- list.files(
    migrations_path,
    pattern = "^[0-9]{3}_[a-z0-9_]+[.]sql$",
    full.names = TRUE
  )

  sort(migration_files)
}

database_migration_status <- function(
  connection,
  migrations_path = "migrations"
) {
  migration_files <- get_migration_files(migrations_path)

  if (length(migration_files) == 0) {
    stop("No database migrations were found in: ", migrations_path)
  }

  available <- tibble::tibble(
    version = as.integer(substr(basename(migration_files), 1, 3)),
    migration_name = basename(migration_files)
  )
  applied_names <- if (DBI::dbExistsTable(connection, "schema_migrations")) {
    DBI::dbGetQuery(
      connection,
      "SELECT migration_name FROM schema_migrations"
    )$migration_name
  } else {
    character()
  }

  available |>
    dplyr::mutate(
      status = dplyr::if_else(
        migration_name %in% applied_names,
        "applied",
        "pending"
      )
    ) |>
    dplyr::arrange(version)
}

apply_database_migrations <- function(
  connection,
  migrations_path = "migrations"
) {
  DBI::dbExecute(
    connection,
    paste(
      "CREATE TABLE IF NOT EXISTS schema_migrations (",
      "version INTEGER PRIMARY KEY,",
      "migration_name VARCHAR NOT NULL UNIQUE,",
      "applied_at TIMESTAMP NOT NULL",
      ")"
    )
  )

  migration_files <- get_migration_files(migrations_path)

  if (length(migration_files) == 0) {
    stop("No database migrations were found in: ", migrations_path)
  }

  migration_versions <- as.integer(substr(basename(migration_files), 1, 3))

  if (anyDuplicated(migration_versions)) {
    stop("Database migration versions must be unique.")
  }

  applied_versions <- DBI::dbGetQuery(
    connection,
    "SELECT version FROM schema_migrations ORDER BY version"
  )$version

  pending_files <- migration_files[!migration_versions %in% applied_versions]

  for (migration_file in pending_files) {
    migration_name <- basename(migration_file)
    migration_version <- as.integer(substr(migration_name, 1, 3))
    migration_sql <- paste(readLines(migration_file, warn = FALSE), collapse = "\n")

    DBI::dbWithTransaction(connection, {
      DBI::dbExecute(connection, migration_sql)
      DBI::dbExecute(
        connection,
        paste(
          "INSERT INTO schema_migrations",
          "(version, migration_name, applied_at)",
          "VALUES (?, ?, current_timestamp)"
        ),
        params = list(migration_version, migration_name)
      )
    })
  }

  invisible(DBI::dbGetQuery(
    connection,
    paste(
      "SELECT version, migration_name, applied_at",
      "FROM schema_migrations ORDER BY version"
    )
  ))
}

validate_budget_allocations <- function(monthly_allocations, monthly_total) {
  expected_categories <- sort(finance_category_names)
  actual_categories <- sort(monthly_allocations$budget_category)

  if (!identical(actual_categories, expected_categories)) {
    stop("Budget allocations must contain each fixed category exactly once.")
  }

  if (
    length(monthly_total) != 1 ||
      is.na(monthly_total) ||
      monthly_total <= 0
  ) {
    stop("The monthly budget total must be one positive number.")
  }

  if (any(is.na(monthly_allocations$monthly_allocation))) {
    stop("Budget allocations cannot be missing.")
  }

  if (any(monthly_allocations$monthly_allocation < 0)) {
    stop("Budget allocations cannot be negative.")
  }

  if (!isTRUE(all.equal(
    sum(monthly_allocations$monthly_allocation),
    monthly_total,
    tolerance = 1e-8
  ))) {
    stop("Budget allocations must sum exactly to the monthly budget total.")
  }

  invisible(TRUE)
}

make_transaction_identity <- function(
  account,
  date,
  description,
  amount,
  check_number,
  duplicate_sequence
) {
  purrr::pmap_chr(
    list(
      account,
      as.character(date),
      description,
      sprintf("%.2f", amount),
      tidyr::replace_na(check_number, ""),
      as.integer(duplicate_sequence)
    ),
    function(account, date, description, amount, check_number, duplicate_sequence) {
      jsonlite::toJSON(
        unname(list(
          account,
          date,
          description,
          amount,
          check_number,
          duplicate_sequence
        )),
        auto_unbox = TRUE
      )
    }
  )
}

make_stable_id <- function(prefix, value) {
  paste0(
    prefix,
    "_",
    vapply(
      value,
      digest::digest,
      character(1),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

database_has_seed_data <- function(connection) {
  seed_tables <- c(
    "categories",
    "imports",
    "transactions",
    "transaction_sightings",
    "transaction_decisions",
    "merchant_rules",
    "budget_versions",
    "budget_allocations",
    "budget_opening_balances",
    "decision_audit_log"
  )

  any(vapply(
    seed_tables,
    function(table_name) {
      DBI::dbGetQuery(
        connection,
        paste("SELECT count(*) AS row_count FROM", table_name)
      )$row_count[[1]] > 0
    },
    logical(1)
  ))
}

prepare_initial_imports <- function(transactions, initialized_at) {
  if (nrow(transactions) == 0) {
    return(tibble::tibble(
      import_id = character(),
      account = character(),
      source_filename = character(),
      imported_at = as.POSIXct(character()),
      coverage_start = as.Date(character()),
      coverage_end = as.Date(character()),
      source_row_count = integer(),
      posted_row_count = integer(),
      new_transaction_count = integer(),
      known_transaction_count = integer(),
      outcome = character(),
      error_message = character()
    ))
  }

  transactions |>
    dplyr::group_by(account, source_file) |>
    dplyr::summarize(
      imported_at = initialized_at,
      coverage_start = min(date),
      coverage_end = max(date),
      source_row_count = dplyr::n(),
      posted_row_count = dplyr::n(),
      new_transaction_count = dplyr::n(),
      known_transaction_count = 0L,
      outcome = "successful",
      error_message = NA_character_,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      import_id = paste0("initial_", account),
      .before = 1
    ) |>
    dplyr::rename(source_filename = source_file)
}

prepare_initial_transactions <- function(transactions, initialized_at) {
  transactions |>
    dplyr::mutate(
      composite_identity = make_transaction_identity(
        account,
        date,
        description,
        amount,
        check_number,
        duplicate_sequence
      ),
      transaction_id = make_stable_id("txn", composite_identity),
      raw_transaction_json = purrr::pmap_chr(
        list(account, date, description, amount, check_number),
        function(account, date, description, amount, check_number) {
          jsonlite::toJSON(
            list(
              account = account,
              date = as.character(date),
              description = description,
              amount = amount,
              check_number = check_number
            ),
            auto_unbox = TRUE,
            na = "null"
          )
        }
      )
    ) |>
    dplyr::transmute(
      transaction_id,
      account,
      transaction_date = date,
      original_description = description,
      original_amount = amount,
      original_check_number = check_number,
      standardized_description = description,
      standardized_amount = amount,
      standardized_check_number = check_number,
      duplicate_sequence,
      composite_identity,
      raw_transaction_json,
      first_seen_import_id = paste0("initial_", account),
      last_seen_import_id = paste0("initial_", account),
      created_at = initialized_at,
      updated_at = initialized_at
    )
}

prepare_initial_decisions <- function(transactions, transaction_rows, initialized_at) {
  excluded_treatments <- c(
    "reimbursement",
    "transfer_or_card_payment",
    "excluded_inflow",
    "excluded_outflow",
    "pass_through"
  )

  transactions |>
    dplyr::mutate(
      composite_identity = make_transaction_identity(
        account,
        date,
        description,
        amount,
        check_number,
        duplicate_sequence
      )
    ) |>
    dplyr::left_join(
      transaction_rows |>
        dplyr::select(transaction_id, composite_identity),
      by = "composite_identity"
    ) |>
    dplyr::transmute(
      transaction_id,
      category_code = category_name_to_code(budget_category),
      assignment_source = category_source,
      assignment_rule = category_rule,
      review_state = dplyr::if_else(
        category_source == "default" | transaction_type == "needs_review",
        "pending",
        "confirmed",
        missing = "confirmed"
      ),
      budget_treatment = transaction_type,
      is_reimbursable,
      is_excluded = transaction_type %in% excluded_treatments,
      note = override_note,
      updated_at = initialized_at
    )
}

prepare_initial_audit_log <- function(
  decision_rows,
  merchant_rows,
  budget_version_rows,
  allocation_rows,
  opening_balance_rows,
  initialized_at
) {
  decision_audit_rows <- decision_rows |>
    dplyr::mutate(
      after_json = purrr::pmap_chr(
        dplyr::pick(
          category_code,
          assignment_source,
          assignment_rule,
          review_state,
          budget_treatment,
          is_reimbursable,
          is_excluded,
          note
        ),
        ~ jsonlite::toJSON(list(...), auto_unbox = TRUE, na = "null")
      )
    ) |>
    dplyr::transmute(
      entity_type = "transaction_decision",
      entity_id = transaction_id,
      after_json
    )

  merchant_audit_rows <- merchant_rows |>
    dplyr::mutate(
      after_json = purrr::pmap_chr(
        dplyr::pick(
          display_name,
          description_pattern,
          default_category_code,
          effective_date,
          priority,
          is_active
        ),
        ~ jsonlite::toJSON(list(...), auto_unbox = TRUE, na = "null")
      )
    ) |>
    dplyr::transmute(
      entity_type = "merchant_rule",
      entity_id = rule_id,
      after_json
    )

  budget_audit_rows <- allocation_rows |>
    dplyr::group_by(budget_version_id) |>
    dplyr::summarize(
      entity_type = "budget_version",
      entity_id = dplyr::first(budget_version_id),
      after_json = as.character(jsonlite::toJSON(
        list(
          effective_month = as.character(budget_version_rows$effective_month[[1]]),
          total_monthly_budget = budget_version_rows$total_monthly_budget[[1]],
          allocations = stats::setNames(monthly_allocation, category_code)
        ),
        auto_unbox = TRUE
      )),
      .groups = "drop"
    )

  opening_balance_audit_rows <- opening_balance_rows |>
    dplyr::mutate(
      after_json = purrr::pmap_chr(
        dplyr::pick(budget_start_month, opening_balance),
        ~ jsonlite::toJSON(list(...), auto_unbox = TRUE)
      )
    ) |>
    dplyr::transmute(
      entity_type = "opening_balance",
      entity_id = category_code,
      after_json
    )

  audit_entities <- dplyr::bind_rows(
    decision_audit_rows,
    merchant_audit_rows,
    budget_audit_rows,
    opening_balance_audit_rows
  )

  audit_entities |>
    dplyr::mutate(
      audit_id = make_stable_id(
        "audit",
        paste(entity_type, entity_id, "initial_seed", sep = "|")
      ),
      action = "initial_seed",
      changed_at = initialized_at,
      before_json = NA_character_,
      change_note = "Initial local database seed"
    ) |>
    dplyr::select(
      audit_id,
      entity_type,
      entity_id,
      action,
      changed_at,
      before_json,
      after_json,
      change_note
    )
}

seed_initial_database <- function(
  connection,
  transactions,
  monthly_allocations = get_monthly_allocations(),
  merchant_rules = get_merchant_category_rules(),
  budget_start_month = as.Date("2026-04-01"),
  opening_balance = 0,
  initialized_at = Sys.time()
) {
  if (database_has_seed_data(connection)) {
    stop("The database already contains seed data and was not changed.")
  }

  monthly_total <- sum(monthly_allocations$monthly_allocation)
  validate_budget_allocations(monthly_allocations, monthly_total)

  category_rows <- get_category_seed()
  import_rows <- prepare_initial_imports(transactions, initialized_at)
  transaction_rows <- prepare_initial_transactions(transactions, initialized_at)
  sighting_rows <- transaction_rows |>
    dplyr::transmute(
      transaction_id,
      import_id = first_seen_import_id,
      seen_at = created_at
    )
  decision_rows <- prepare_initial_decisions(
    transactions,
    transaction_rows,
    initialized_at
  )
  merchant_rows <- merchant_rules |>
    dplyr::transmute(
      rule_id = rule_name,
      display_name = stringr::str_to_title(stringr::str_replace_all(rule_name, "_", " ")),
      description_pattern,
      match_type = "regular_expression",
      default_category_code = category_name_to_code(budget_category),
      effective_date = budget_start_month,
      priority = rule_priority,
      is_active = TRUE,
      created_at = initialized_at,
      updated_at = initialized_at
    )
  budget_version_rows <- tibble::tibble(
    budget_version_id = "budget_2026_04",
    effective_month = budget_start_month,
    total_monthly_budget = monthly_total,
    created_at = initialized_at
  )
  allocation_rows <- monthly_allocations |>
    dplyr::transmute(
      budget_version_id = "budget_2026_04",
      category_code = category_name_to_code(budget_category),
      monthly_allocation
    )
  opening_balance_rows <- category_rows |>
    dplyr::transmute(
      category_code,
      budget_start_month,
      opening_balance = as.numeric(.env$opening_balance),
      updated_at = initialized_at
    )
  audit_rows <- prepare_initial_audit_log(
    decision_rows,
    merchant_rows,
    budget_version_rows,
    allocation_rows,
    opening_balance_rows,
    initialized_at
  )

  DBI::dbWithTransaction(connection, {
    DBI::dbAppendTable(connection, "categories", category_rows)
    DBI::dbAppendTable(connection, "imports", import_rows)
    DBI::dbAppendTable(connection, "transactions", transaction_rows)
    DBI::dbAppendTable(connection, "transaction_sightings", sighting_rows)
    DBI::dbAppendTable(connection, "transaction_decisions", decision_rows)
    DBI::dbAppendTable(connection, "merchant_rules", merchant_rows)
    DBI::dbAppendTable(connection, "budget_versions", budget_version_rows)
    DBI::dbAppendTable(connection, "budget_allocations", allocation_rows)
    DBI::dbAppendTable(connection, "budget_opening_balances", opening_balance_rows)
    DBI::dbAppendTable(connection, "decision_audit_log", audit_rows)
  })

  invisible(list(
    category_count = nrow(category_rows),
    import_count = nrow(import_rows),
    transaction_count = nrow(transaction_rows),
    sighting_count = nrow(sighting_rows),
    decision_count = nrow(decision_rows),
    merchant_rule_count = nrow(merchant_rows),
    budget_version_count = nrow(budget_version_rows),
    allocation_count = nrow(allocation_rows),
    opening_balance_count = nrow(opening_balance_rows),
    audit_count = nrow(audit_rows)
  ))
}
