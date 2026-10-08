source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))
source(file.path("R", "database.R"))
source(file.path("R", "database_queries.R"))
source(file.path("R", "import_service.R"))

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
    stop(
      label,
      if (!is.na(error_message)) paste0("\nActual error: ", error_message),
      call. = FALSE
    )
  }
}

run_test <- function(name, code) {
  force(code)
  message("PASS: ", name)
}

empty_seed_transactions <- function() {
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

with_import_database <- function(code) {
  connection <- connect_finance_database(":memory:")
  on.exit(disconnect_finance_database(connection), add = TRUE)
  apply_database_migrations(connection)
  seed_initial_database(connection, empty_seed_transactions())
  evaluation_environment <- list2env(
    list(connection = connection),
    parent = parent.frame()
  )
  eval(substitute(code), envir = evaluation_environment)
}

write_test_export <- function(rows) {
  file_path <- tempfile(fileext = ".csv")
  readr::write_csv(rows, file_path, na = "")
  file_path
}

test_export <- function(
  dates,
  descriptions,
  amounts,
  statuses = rep("Posted", length(dates)),
  check_numbers = rep(NA_character_, length(dates))
) {
  tibble::tibble(
    DATE = dates,
    DESCRIPTION = descriptions,
    AMOUNT = amounts,
    `CHECK #` = check_numbers,
    STATUS = statuses
  )
}

table_count <- function(connection, table_name) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT count(*) AS row_count FROM",
      DBI::dbQuoteIdentifier(connection, table_name)
    )
  )$row_count[[1]]
}

run_test("preview filters posted rows and never mutates the database", {
  with_import_database({
    file_path <- write_test_export(test_export(
      dates = c("10/01/2026", "10/02/2026", "10/03/2026"),
      descriptions = c("TARGET STORE", "NEW LOCAL SHOP", "PENDING SHOP"),
      amounts = c("-25.00", "-12.00", "-40.00"),
      statuses = c("Posted", "Posted", "Pending")
    ))
    on.exit(unlink(file_path), add = TRUE)

    preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    )

    expect_equal(preview$source_row_count, 3L, "Expected all source rows.")
    expect_equal(preview$posted_row_count, 2L, "Expected posted-only import rows.")
    expect_equal(preview$new_transaction_count, 2L, "Expected two new identities.")
    expect_equal(preview$known_transaction_count, 0L, "Expected no known identities.")
    expect_equal(preview$coverage_start, as.Date("2026-10-01"), "Wrong coverage start.")
    expect_equal(preview$coverage_end, as.Date("2026-10-02"), "Wrong coverage end.")
    expect_equal(preview$can_confirm, TRUE, "Expected a confirmable preview.")
    confirmation <- import_confirmation_details(preview)
    expect_equal(
      confirmation$source_filename,
      basename(file_path),
      "Confirmation should retain the source filename."
    )
    expect_equal(
      grepl("complete calendar-day", confirmation$complete_day_notice),
      TRUE,
      "Confirmation must warn that partial-day exports are unsupported."
    )
    expect_equal(
      preview$transactions$review_state,
      c("confirmed", "pending"),
      "Expected a merchant match and an uncertain fallback."
    )
    expect_equal(
      table_count(connection, "transactions"),
      0,
      "Preview must not write transactions."
    )
    expect_equal(
      table_count(connection, "imports"),
      0,
      "Preview must not write import metadata."
    )
  })
})

run_test("one malformed row blocks the complete file", {
  with_import_database({
    file_path <- write_test_export(test_export(
      dates = c("10/01/2026", "not-a-date"),
      descriptions = c("TARGET STORE", "PENDING SHOP"),
      amounts = c("-25.00", "not-an-amount"),
      statuses = c("Posted", "Pending")
    ))
    on.exit(unlink(file_path), add = TRUE)

    preview <- suppressWarnings(preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    ))

    expect_equal(preview$can_confirm, FALSE, "Malformed rows must block confirmation.")
    expect_equal(
      sort(preview$problems$code),
      c("invalid_amount", "invalid_date"),
      "Expected every malformed field to be reported."
    )
    expect_error(
      confirm_transaction_import(
        connection,
        preview,
        "credit_card_jacob",
        basename(file_path)
      ),
      "blocking errors",
      "A malformed preview must not be confirmable."
    )
    expect_equal(table_count(connection, "imports"), 0, "Blocked files must not write.")
  })
})

run_test("schema and status validation are strict", {
  with_import_database({
    wrong_schema_file <- tempfile(fileext = ".csv")
    readr::write_csv(
      tibble::tibble(
        DATE = "10/01/2026",
        DESCRIPTION = "TARGET STORE",
        AMOUNT = "-25.00",
        STATUS = "Posted"
      ),
      wrong_schema_file
    )
    on.exit(unlink(wrong_schema_file), add = TRUE)

    schema_preview <- preview_transaction_import(
      connection,
      wrong_schema_file,
      "credit_card_jacob"
    )

    expect_equal(schema_preview$can_confirm, FALSE, "Wrong columns must block.")
    expect_equal(schema_preview$problems$code, "invalid_schema", "Wrong schema problem.")

    bad_status_file <- write_test_export(test_export(
      dates = "10/01/2026",
      descriptions = "TARGET STORE",
      amounts = "-25.00",
      statuses = "Complete"
    ))
    on.exit(unlink(bad_status_file), add = TRUE)
    status_preview <- preview_transaction_import(
      connection,
      bad_status_file,
      "credit_card_jacob"
    )

    expect_equal(status_preview$can_confirm, FALSE, "Unknown status must block.")
    expect_equal(
      "invalid_status" %in% status_preview$problems$code,
      TRUE,
      "Wrong status problem."
    )
  })
})

run_test("genuine identical transactions receive stable duplicate identities", {
  with_import_database({
    file_path <- write_test_export(test_export(
      dates = c("10/01/2026", "10/01/2026"),
      descriptions = c("SAME MERCHANT", "SAME MERCHANT"),
      amounts = c("-12.34", "-12.34")
    ))
    on.exit(unlink(file_path), add = TRUE)

    preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_kendra"
    )

    expect_equal(preview$can_confirm, TRUE, "Duplicate groups should be reviewable.")
    expect_equal(preview$duplicate_group_count, 1L, "Expected one duplicate group.")
    expect_equal(
      preview$problems$severity,
      "warning",
      "Genuine duplicate groups should warn without blocking."
    )
    expect_equal(
      preview$transactions$duplicate_sequence,
      c(1L, 2L),
      "Expected duplicate sequence one and two."
    )
    expect_equal(
      length(unique(preview$transactions$transaction_id)),
      2L,
      "Duplicate sequences must produce distinct durable IDs."
    )
  })
})

run_test("confirmation is idempotent and preserves saved decisions", {
  with_import_database({
    file_path <- write_test_export(test_export(
      dates = c("10/01/2026", "10/02/2026"),
      descriptions = c("TARGET STORE", "NEW LOCAL SHOP"),
      amounts = c("-25.00", "-12.00")
    ))
    on.exit(unlink(file_path), add = TRUE)

    first_preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    )
    first_import <- confirm_transaction_import(
      connection,
      first_preview,
      "credit_card_jacob",
      basename(file_path)
    )
    overridden_transaction_id <- first_preview$transactions$transaction_id[[2]]
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE transaction_decisions",
        "SET category_code = 'housing',",
        "assignment_source = 'transaction_override',",
        "assignment_rule = 'test_override',",
        "review_state = 'confirmed'",
        "WHERE transaction_id = ?"
      ),
      params = list(overridden_transaction_id)
    )

    second_preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    )
    second_import <- confirm_transaction_import(
      connection,
      second_preview,
      "credit_card_jacob",
      basename(file_path)
    )

    saved_decision <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT category_code, assignment_source",
        "FROM transaction_decisions WHERE transaction_id = ?"
      ),
      params = list(overridden_transaction_id)
    )
    latest_sighting_count <- DBI::dbGetQuery(
      connection,
      "SELECT count(*) AS n FROM transaction_sightings WHERE import_id = ?",
      params = list(second_import$import_id)
    )$n[[1]]

    expect_equal(first_import$new_transaction_count, 2L, "First import should insert two.")
    expect_equal(second_preview$new_transaction_count, 0L, "Retry should insert none.")
    expect_equal(second_preview$known_transaction_count, 2L, "Retry should see both.")
    expect_equal(table_count(connection, "transactions"), 2, "Retry duplicated rows.")
    expect_equal(table_count(connection, "imports"), 2, "Expected both successful sightings.")
    expect_equal(
      latest_sighting_count,
      2,
      "Known rows should record the latest sighting."
    )
    expect_equal(saved_decision$category_code, "housing", "Retry rewrote a category.")
    expect_equal(
      saved_decision$assignment_source,
      "transaction_override",
      "Retry rewrote a saved assignment source."
    )
  })
})

run_test("overlapping export ranges add only unseen identities", {
  with_import_database({
    first_file <- write_test_export(test_export(
      dates = c("10/01/2026", "10/02/2026"),
      descriptions = c("SHOP ONE", "SHOP TWO"),
      amounts = c("-10.00", "-20.00")
    ))
    second_file <- write_test_export(test_export(
      dates = c("10/02/2026", "10/03/2026"),
      descriptions = c("SHOP TWO", "SHOP THREE"),
      amounts = c("-20.00", "-30.00")
    ))
    on.exit(unlink(c(first_file, second_file)), add = TRUE)

    first_preview <- preview_transaction_import(
      connection,
      first_file,
      "credit_card_kendra"
    )
    confirm_transaction_import(
      connection,
      first_preview,
      "credit_card_kendra",
      basename(first_file)
    )
    second_preview <- preview_transaction_import(
      connection,
      second_file,
      "credit_card_kendra"
    )
    confirm_transaction_import(
      connection,
      second_preview,
      "credit_card_kendra",
      basename(second_file)
    )

    expect_equal(second_preview$known_transaction_count, 1L, "Overlap should be known.")
    expect_equal(second_preview$new_transaction_count, 1L, "New day should be inserted.")
    expect_equal(table_count(connection, "transactions"), 3, "Wrong overlap row count.")
  })
})

run_test("confirmation verifies the account slot and filename", {
  with_import_database({
    file_path <- write_test_export(test_export(
      dates = "10/01/2026",
      descriptions = "TARGET STORE",
      amounts = "-25.00"
    ))
    on.exit(unlink(file_path), add = TRUE)
    preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    )

    expect_error(
      confirm_transaction_import(
        connection,
        preview,
        "credit_card_kendra",
        basename(file_path)
      ),
      "account does not match",
      "A different account slot must be rejected."
    )
    expect_error(
      confirm_transaction_import(
        connection,
        preview,
        "credit_card_jacob",
        "another-file.csv"
      ),
      "filename does not match",
      "A different filename must be rejected."
    )
    expect_equal(table_count(connection, "imports"), 0, "Mismatch wrote metadata.")
  })
})

run_test("a database failure rolls back the complete confirmed file", {
  with_import_database({
    file_path <- write_test_export(test_export(
      dates = "10/01/2026",
      descriptions = "TARGET STORE",
      amounts = "-25.00"
    ))
    on.exit(unlink(file_path), add = TRUE)
    preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    )
    preview$transactions$account <- "unsupported_account"

    expect_error(
      confirm_transaction_import(
        connection,
        preview,
        "credit_card_jacob",
        basename(file_path)
      ),
      "Current transaction is aborted",
      "Expected the invalid transaction to fail inside the database."
    )
    expect_equal(table_count(connection, "imports"), 0, "Failed file left metadata.")
    expect_equal(table_count(connection, "transactions"), 0, "Failed file left rows.")
    expect_equal(table_count(connection, "transaction_decisions"), 0, "Failed file left decisions.")
  })
})

run_test("merchant rules apply only on or after their effective date", {
  with_import_database({
    DBI::dbExecute(
      connection,
      "UPDATE merchant_rules SET effective_date = DATE '2027-01-01' WHERE rule_id = 'variable_retailers'"
    )
    file_path <- write_test_export(test_export(
      dates = c("12/31/2026", "01/01/2027"),
      descriptions = c("TARGET STORE", "TARGET STORE"),
      amounts = c("-25.00", "-25.00")
    ))
    on.exit(unlink(file_path), add = TRUE)

    preview <- preview_transaction_import(
      connection,
      file_path,
      "credit_card_jacob"
    ) |>
      (\(value) {
        value$transactions <- value$transactions |>
          dplyr::arrange(date)
        value
      })()

    expect_equal(
      preview$transactions$category_source,
      c("default", "merchant_rule"),
      "The rule should apply prospectively from its effective date."
    )
    expect_equal(
      preview$transactions$review_state,
      c("pending", "confirmed"),
      "Only the unmatched earlier transaction should require review."
    )
  })
})

message("All import service tests passed.")
