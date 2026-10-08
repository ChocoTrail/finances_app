supported_finance_accounts <- c(
  "checking",
  "credit_card_jacob",
  "credit_card_kendra"
)

new_import_problem <- function(
  code,
  severity,
  message,
  source_row_number = NA_integer_
) {
  tibble::tibble(
    code = code,
    severity = severity,
    source_row_number = as.integer(source_row_number),
    message = message
  )
}

empty_import_problems <- function() {
  tibble::tibble(
    code = character(),
    severity = character(),
    source_row_number = integer(),
    message = character()
  )
}

validate_import_account <- function(account) {
  if (
    length(account) != 1L ||
      is.na(account) ||
      !account %in% supported_finance_accounts
  ) {
    stop(
      "The import account must be checking, credit_card_jacob, or ",
      "credit_card_kendra.",
      call. = FALSE
    )
  }

  account
}

read_import_file <- function(file_path) {
  if (!file.exists(file_path)) {
    stop("The account export does not exist: ", file_path, call. = FALSE)
  }

  suppressMessages(readr::read_csv(
    file = file_path,
    col_types = readr::cols(.default = readr::col_character()),
    name_repair = "minimal",
    trim_ws = FALSE,
    progress = FALSE
  ))
}

parse_import_rows <- function(raw_rows, account, source_filename) {
  rows <- raw_rows |>
    dplyr::mutate(
      source_row_number = dplyr::row_number(),
      original_date = DATE,
      original_description = DESCRIPTION,
      original_amount = AMOUNT,
      original_check_number = `CHECK #`,
      original_status = STATUS,
      date = readr::parse_date(trimws(DATE), format = "%m/%d/%Y"),
      description = stringr::str_squish(DESCRIPTION),
      amount = readr::parse_double(trimws(AMOUNT)),
      check_number = dplyr::na_if(stringr::str_squish(`CHECK #`), ""),
      status = trimws(STATUS),
      account = .env$account,
      source_file = .env$source_filename
    )

  problems <- empty_import_problems()

  append_row_problems <- function(condition, code, message) {
    problem_rows <- rows$source_row_number[condition]

    if (length(problem_rows) > 0) {
      problems <<- dplyr::bind_rows(
        problems,
        purrr::map_dfr(
          problem_rows,
          ~ new_import_problem(code, "error", message, .x)
        )
      )
    }
  }

  append_row_problems(
    is.na(rows$date),
    "invalid_date",
    "DATE must use MM/DD/YYYY and contain a real calendar date."
  )
  append_row_problems(
    is.na(rows$amount),
    "invalid_amount",
    "AMOUNT must contain a parseable number."
  )
  append_row_problems(
    is.na(rows$description) | !nzchar(rows$description),
    "missing_description",
    "DESCRIPTION cannot be blank."
  )
  append_row_problems(
    is.na(rows$status) | !rows$status %in% c("Posted", "Pending"),
    "invalid_status",
    "STATUS must be Posted or Pending."
  )

  list(rows = rows, problems = problems)
}

add_import_duplicate_sequence <- function(transactions) {
  transactions |>
    dplyr::group_by(
      account,
      date,
      description,
      amount,
      check_number
    ) |>
    dplyr::arrange(source_row_number, .by_group = TRUE) |>
    dplyr::mutate(duplicate_sequence = dplyr::row_number()) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      composite_identity = make_transaction_identity(
        account,
        date,
        description,
        amount,
        check_number,
        duplicate_sequence
      ),
      transaction_id = make_stable_id("txn", composite_identity)
    )
}

read_import_merchant_rules <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "m.rule_id,",
      "m.description_pattern,",
      "m.default_category_code AS category_code,",
      "m.effective_date,",
      "m.priority",
      "FROM merchant_rules m",
      "WHERE m.is_active",
      "ORDER BY m.priority"
    )
  ) |>
    dplyr::mutate(effective_date = as.Date(effective_date))
}

classify_import_transactions <- function(transactions, merchant_rules) {
  categorized <- transactions |>
    classify_transaction_types() |>
    dplyr::mutate(
      category_code = dplyr::if_else(
        transaction_type == "category_offset",
        "housing",
        NA_character_
      ),
      category_source = dplyr::if_else(
        transaction_type == "category_offset",
        "transaction_type_rule",
        NA_character_
      ),
      category_rule = dplyr::if_else(
        transaction_type == "category_offset",
        "rental_income_offset",
        NA_character_
      )
    )

  for (rule_index in seq_len(nrow(merchant_rules))) {
    rule_matches <-
      is.na(categorized$category_code) &
      categorized$transaction_type %in% c("expense", "refund") &
      categorized$date >= merchant_rules$effective_date[[rule_index]] &
      stringr::str_detect(
        categorized$description,
        stringr::regex(
          merchant_rules$description_pattern[[rule_index]],
          ignore_case = TRUE
        )
      )

    categorized <- categorized |>
      dplyr::mutate(
        category_code = dplyr::if_else(
          .env$rule_matches,
          merchant_rules$category_code[[rule_index]],
          category_code
        ),
        category_source = dplyr::if_else(
          .env$rule_matches,
          "merchant_rule",
          category_source
        ),
        category_rule = dplyr::if_else(
          .env$rule_matches,
          merchant_rules$rule_id[[rule_index]],
          category_rule
        )
      )
  }

  categorized |>
    dplyr::mutate(
      is_uncertain =
        transaction_type == "needs_review" |
        (transaction_type %in% c("expense", "refund") & is.na(category_code)),
      category_code = dplyr::if_else(
        transaction_type %in% c("expense", "refund") & is.na(category_code),
        "personal_discretionary",
        category_code
      ),
      category_source = dplyr::if_else(
        transaction_type %in% c("expense", "refund") & is.na(category_source),
        "default",
        category_source
      ),
      category_rule = dplyr::if_else(
        transaction_type %in% c("expense", "refund") & is.na(category_rule),
        "personal_discretionary_fallback",
        category_rule
      ),
      review_state = dplyr::if_else(
        is_uncertain,
        "pending",
        "confirmed"
      ),
      is_reimbursable = FALSE,
      is_excluded = transaction_type %in% c(
        "reimbursement",
        "transfer_or_card_payment",
        "excluded_inflow",
        "excluded_outflow",
        "pass_through"
      )
    )
}

preview_transaction_import <- function(
  connection,
  file_path,
  account,
  source_filename = basename(file_path)
) {
  account <- validate_import_account(account)
  raw_rows <- read_import_file(file_path)
  problems <- empty_import_problems()

  if (!identical(names(raw_rows), expected_transaction_columns)) {
    problems <- new_import_problem(
      "invalid_schema",
      "error",
      paste0(
        "Expected columns: ",
        paste(expected_transaction_columns, collapse = ", "),
        ". Found: ",
        paste(names(raw_rows), collapse = ", "),
        "."
      )
    )

    return(structure(
      list(
        account = account,
        source_filename = source_filename,
        source_row_count = nrow(raw_rows),
        posted_row_count = 0L,
        coverage_start = as.Date(NA),
        coverage_end = as.Date(NA),
        new_transaction_count = 0L,
        known_transaction_count = 0L,
        duplicate_group_count = 0L,
        problems = problems,
        can_confirm = FALSE,
        transactions = tibble::tibble()
      ),
      class = c("finance_import_preview", "list")
    ))
  }

  parsed <- parse_import_rows(raw_rows, account, source_filename)
  problems <- parsed$problems
  posted_transactions <- parsed$rows |>
    dplyr::filter(status == "Posted")

  if (nrow(posted_transactions) == 0) {
    problems <- dplyr::bind_rows(
      problems,
      new_import_problem(
        "no_posted_transactions",
        "error",
        "The file contains no posted transactions."
      )
    )
  }

  valid_posted_transactions <- posted_transactions |>
    dplyr::filter(
      !is.na(date),
      !is.na(amount),
      !is.na(description),
      nzchar(description)
    ) |>
    add_import_duplicate_sequence()

  duplicate_groups <- valid_posted_transactions |>
    dplyr::count(
      account,
      date,
      description,
      amount,
      check_number,
      name = "duplicate_count"
    ) |>
    dplyr::filter(duplicate_count > 1)

  if (nrow(duplicate_groups) > 0) {
    problems <- dplyr::bind_rows(
      problems,
      new_import_problem(
        "identical_transaction_groups",
        "warning",
        paste0(
          nrow(duplicate_groups),
          " group(s) of otherwise identical transactions were assigned ",
          "duplicate sequence numbers."
        )
      )
    )
  }

  existing_identities <- if (nrow(valid_posted_transactions) == 0) {
    character()
  } else {
    DBI::dbGetQuery(
      connection,
      "SELECT composite_identity FROM transactions"
    )$composite_identity
  }

  merchant_rules <- read_import_merchant_rules(connection)
  classified_transactions <- valid_posted_transactions |>
    classify_import_transactions(merchant_rules) |>
    dplyr::mutate(
      identity_status = dplyr::if_else(
        composite_identity %in% existing_identities,
        "known",
        "new"
      )
    )

  error_count <- sum(problems$severity == "error")
  coverage_dates <- valid_posted_transactions$date

  structure(
    list(
      account = account,
      source_filename = source_filename,
      source_row_count = nrow(raw_rows),
      posted_row_count = nrow(posted_transactions),
      coverage_start = if (length(coverage_dates) > 0) min(coverage_dates) else as.Date(NA),
      coverage_end = if (length(coverage_dates) > 0) max(coverage_dates) else as.Date(NA),
      new_transaction_count = sum(classified_transactions$identity_status == "new"),
      known_transaction_count = sum(classified_transactions$identity_status == "known"),
      duplicate_group_count = nrow(duplicate_groups),
      problems = problems,
      can_confirm = error_count == 0,
      transactions = classified_transactions
    ),
    class = c("finance_import_preview", "list")
  )
}

import_confirmation_details <- function(preview) {
  if (!inherits(preview, "finance_import_preview")) {
    stop("A valid import preview is required.", call. = FALSE)
  }

  tibble::tibble(
    account = preview$account,
    source_filename = preview$source_filename,
    coverage_start = preview$coverage_start,
    coverage_end = preview$coverage_end,
    posted_transaction_count = preview$posted_row_count,
    new_transaction_count = preview$new_transaction_count,
    known_transaction_count = preview$known_transaction_count,
    account_slot_notice = paste0(
      "Confirm that ",
      preview$source_filename,
      " belongs in the ",
      preview$account,
      " account slot."
    ),
    complete_day_notice = paste0(
      "Only complete calendar-day exports are supported. ",
      "Do not confirm a partial-day export."
    )
  )
}

prepare_confirmed_import_transactions <- function(
  transactions,
  import_id,
  imported_at
) {
  transactions |>
    dplyr::filter(identity_status == "new") |>
    dplyr::transmute(
      transaction_id,
      account,
      transaction_date = date,
      original_description,
      original_amount = readr::parse_double(trimws(original_amount)),
      original_check_number = dplyr::na_if(
        stringr::str_squish(original_check_number),
        ""
      ),
      standardized_description = description,
      standardized_amount = amount,
      standardized_check_number = check_number,
      duplicate_sequence,
      composite_identity,
      raw_transaction_json = purrr::pmap_chr(
        dplyr::pick(
          original_date,
          original_description,
          original_amount,
          original_check_number,
          original_status
        ),
        ~ jsonlite::toJSON(list(...), auto_unbox = TRUE, na = "null")
      ),
      first_seen_import_id = import_id,
      last_seen_import_id = import_id,
      created_at = imported_at,
      updated_at = imported_at
    )
}

prepare_confirmed_import_decisions <- function(transactions, imported_at) {
  transactions |>
    dplyr::filter(identity_status == "new") |>
    dplyr::transmute(
      transaction_id,
      category_code,
      assignment_source = category_source,
      assignment_rule = category_rule,
      review_state,
      budget_treatment = transaction_type,
      is_reimbursable,
      is_excluded,
      note = NA_character_,
      updated_at = imported_at
    )
}

prepare_import_decision_audit <- function(decisions, imported_at) {
  decisions |>
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
      audit_id = make_stable_id(
        "audit",
        paste(transaction_id, "initial_import_decision", sep = "|")
      ),
      entity_type = "transaction_decision",
      entity_id = transaction_id,
      action = "initial_import_decision",
      changed_at = imported_at,
      before_json = NA_character_,
      after_json,
      change_note = "Decision assigned during confirmed import"
    )
}

new_database_import_id <- function(connection) {
  paste0(
    "import_",
    DBI::dbGetQuery(
      connection,
      "SELECT CAST(uuid() AS VARCHAR) AS import_uuid"
    )$import_uuid[[1]]
  )
}

confirm_transaction_import <- function(
  connection,
  preview,
  confirmed_account,
  confirmed_filename,
  imported_at = Sys.time()
) {
  if (!inherits(preview, "finance_import_preview")) {
    stop("A valid import preview is required.", call. = FALSE)
  }

  if (!isTRUE(preview$can_confirm)) {
    stop(
      "The import preview contains blocking errors and cannot be confirmed.",
      call. = FALSE
    )
  }

  if (!identical(confirmed_account, preview$account)) {
    stop(
      "The confirmed account does not match the previewed account slot.",
      call. = FALSE
    )
  }

  if (!identical(confirmed_filename, preview$source_filename)) {
    stop(
      "The confirmed filename does not match the previewed file.",
      call. = FALSE
    )
  }

  import_id <- new_database_import_id(connection)
  import_row <- tibble::tibble(
    import_id = import_id,
    account = preview$account,
    source_filename = preview$source_filename,
    imported_at = imported_at,
    coverage_start = preview$coverage_start,
    coverage_end = preview$coverage_end,
    source_row_count = preview$source_row_count,
    posted_row_count = preview$posted_row_count,
    new_transaction_count = preview$new_transaction_count,
    known_transaction_count = preview$known_transaction_count,
    outcome = "successful",
    error_message = NA_character_
  )
  transaction_rows <- prepare_confirmed_import_transactions(
    preview$transactions,
    import_id,
    imported_at
  )
  decision_rows <- prepare_confirmed_import_decisions(
    preview$transactions,
    imported_at
  )
  audit_rows <- prepare_import_decision_audit(decision_rows, imported_at)
  sighting_rows <- preview$transactions |>
    dplyr::transmute(
      transaction_id,
      import_id = import_id,
      seen_at = imported_at
    )

  DBI::dbWithTransaction(connection, {
    DBI::dbAppendTable(connection, "imports", import_row)

    if (nrow(transaction_rows) > 0) {
      DBI::dbAppendTable(connection, "transactions", transaction_rows)
      DBI::dbAppendTable(connection, "transaction_decisions", decision_rows)
      DBI::dbAppendTable(connection, "decision_audit_log", audit_rows)
    }

    if (nrow(sighting_rows) > 0) {
      DBI::dbAppendTable(
        connection,
        "transaction_sightings",
        sighting_rows
      )
    }
  })

  invisible(list(
    import_id = import_id,
    account = preview$account,
    source_filename = preview$source_filename,
    coverage_start = preview$coverage_start,
    coverage_end = preview$coverage_end,
    posted_transaction_count = preview$posted_row_count,
    new_transaction_count = preview$new_transaction_count,
    known_transaction_count = preview$known_transaction_count
  ))
}
