transaction_filter_defaults <- function(today = Sys.Date()) {
  start_date <- lubridate::floor_date(as.Date(today), unit = "month")
  end_date <- seq.Date(start_date, by = "month", length.out = 2)[[2]] - 1

  list(
    start_date = as.character(start_date),
    end_date = as.character(end_date),
    search = "",
    account = "all",
    category = "all",
    merchant = "all",
    treatment = "all",
    review_state = "all"
  )
}

transaction_filter_value <- function(filters, name, default) {
  if (name %in% names(filters)) filters[[name]] else default
}

normalize_optional_filter_date <- function(value, label) {
  if (is.null(value) || identical(value, "")) {
    return(NULL)
  }

  value <- as.character(value)

  if (length(value) != 1 || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)) {
    stop(label, " must use YYYY-MM-DD format.", call. = FALSE)
  }

  parsed <- suppressWarnings(as.Date(value))

  if (is.na(parsed)) {
    stop(label, " is not a valid calendar date.", call. = FALSE)
  }

  parsed
}

normalize_transaction_filters <- function(
  filters = NULL,
  today = Sys.Date()
) {
  defaults <- transaction_filter_defaults(today)
  filters <- if (is.null(filters)) list() else filters
  start_date <- normalize_optional_filter_date(
    transaction_filter_value(filters, "start_date", defaults$start_date),
    "Transaction start date"
  )
  end_date <- normalize_optional_filter_date(
    transaction_filter_value(filters, "end_date", defaults$end_date),
    "Transaction end date"
  )

  if (!is.null(start_date) && !is.null(end_date) && end_date < start_date) {
    stop("Transaction end date cannot precede its start date.", call. = FALSE)
  }

  search <- trimws(as.character(
    transaction_filter_value(filters, "search", defaults$search)
  ))

  if (length(search) != 1 || is.na(search) || nchar(search) > 200) {
    stop("Transaction search must contain at most 200 characters.", call. = FALSE)
  }

  normalize_choice <- function(name) {
    value <- as.character(transaction_filter_value(filters, name, defaults[[name]]))

    if (length(value) != 1 || is.na(value) || !nzchar(value)) {
      stop("Transaction filter is invalid: ", name, call. = FALSE)
    }

    value
  }

  list(
    start_date = start_date,
    end_date = end_date,
    search = search,
    account = normalize_choice("account"),
    category = normalize_choice("category"),
    merchant = normalize_choice("merchant"),
    treatment = normalize_choice("treatment"),
    review_state = normalize_choice("review_state")
  )
}

validate_transaction_filter_choices <- function(filters, categories, merchants) {
  allowed_accounts <- c("all", overview_accounts()$account)
  allowed_categories <- c("all", categories$category_code)
  allowed_merchants <- c("all", merchants$rule_name)
  allowed_treatments <- c(
    "all",
    "expense",
    "refund",
    "category_offset",
    "reimbursement",
    "transfer_or_card_payment",
    "excluded_inflow",
    "excluded_outflow",
    "pass_through",
    "needs_review",
    "reimbursable",
    "excluded"
  )
  allowed_review_states <- c("all", "pending", "confirmed")

  allowed <- list(
    account = allowed_accounts,
    category = allowed_categories,
    merchant = allowed_merchants,
    treatment = allowed_treatments,
    review_state = allowed_review_states
  )

  for (name in names(allowed)) {
    if (!filters[[name]] %in% allowed[[name]]) {
      stop("Unsupported transaction filter: ", name, call. = FALSE)
    }
  }

  invisible(filters)
}

transaction_filter_options <- function(connection) {
  categories <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT category_code, display_name AS label",
      "FROM categories",
      "WHERE is_active",
      "ORDER BY sort_order"
    )
  )
  merchants <- read_database_merchant_rules(connection) |>
    dplyr::transmute(rule_name, label = display_name)
  treatments <- tibble::tribble(
    ~value, ~label,
    "expense", "Spending",
    "refund", "Refund",
    "category_offset", "Category offset",
    "reimbursement", "Reimbursement",
    "transfer_or_card_payment", "Transfer or card payment",
    "excluded_inflow", "Excluded inflow",
    "excluded_outflow", "Excluded outflow",
    "pass_through", "Pass-through",
    "needs_review", "Needs review",
    "reimbursable", "Marked reimbursable",
    "excluded", "Marked excluded"
  )

  list(
    accounts = overview_accounts(),
    categories = categories,
    merchants = merchants,
    treatments = treatments
  )
}

prepare_transaction_screen_rows <- function(connection) {
  merchant_names <- read_database_merchant_rules(connection) |>
    dplyr::select(rule_name, merchant_label = display_name)

  read_database_transactions(connection) |>
    dplyr::mutate(
      merchant_rule = dplyr::if_else(
        category_source == "merchant_rule",
        category_rule,
        NA_character_
      ),
      display_treatment = dplyr::case_when(
        is_reimbursable ~ "reimbursable",
        is_excluded ~ "excluded",
        TRUE ~ transaction_type
      )
    ) |>
    dplyr::left_join(
      merchant_names,
      by = c("merchant_rule" = "rule_name")
    )
}

format_transaction_screen_rows <- function(rows) {
  account_labels <- stats::setNames(
    overview_accounts()$label,
    overview_accounts()$account
  )

  purrr::pmap(
    rows,
    function(
      transaction_id,
      account,
      date,
      description,
      amount,
      category_code,
      budget_category,
      transaction_type,
      display_treatment,
      review_state,
      is_reimbursable,
      is_excluded,
      override_note,
      budget_amount,
      merchant_rule,
      merchant_label
    ) {
      list(
        transaction_id = transaction_id,
        account = account,
        account_label = unname(account_labels[[account]]),
        date = as.character(date),
        description = description,
        amount = amount,
        category_code = category_code,
        category = budget_category,
        budget_treatment = transaction_type,
        display_treatment = display_treatment,
        review_state = review_state,
        is_reimbursable = is_reimbursable,
        is_excluded = is_excluded,
        note = if (is.na(override_note)) NULL else override_note,
        budget_effect = budget_amount,
        merchant_rule = if (is.na(merchant_rule)) NULL else merchant_rule,
        merchant = if (is.na(merchant_label)) NULL else merchant_label
      )
    }
  )
}

format_filter_options <- function(options) {
  list(
    accounts = purrr::pmap(
      options$accounts,
      ~ list(value = ..1, label = ..2)
    ),
    categories = purrr::pmap(
      options$categories,
      ~ list(value = ..1, label = ..2)
    ),
    merchants = purrr::pmap(
      options$merchants,
      ~ list(value = ..1, label = ..2)
    ),
    treatments = purrr::pmap(
      options$treatments,
      ~ list(value = ..1, label = ..2)
    )
  )
}

build_transaction_screen_contract <- function(
  connection,
  filters = NULL,
  today = Sys.Date(),
  result_limit = 200L
) {
  filters <- normalize_transaction_filters(filters, today)
  options <- transaction_filter_options(connection)
  validate_transaction_filter_choices(
    filters,
    options$categories,
    options$merchants
  )
  all_rows <- prepare_transaction_screen_rows(connection)
  pending_review_count <- sum(all_rows$review_state == "pending")
  rows <- all_rows

  if (!is.null(filters$start_date)) {
    rows <- dplyr::filter(rows, date >= filters$start_date)
  }

  if (!is.null(filters$end_date)) {
    rows <- dplyr::filter(rows, date <= filters$end_date)
  }

  if (nzchar(filters$search)) {
    rows <- dplyr::filter(
      rows,
      stringr::str_detect(
        description,
        stringr::fixed(filters$search, ignore_case = TRUE)
      )
    )
  }

  if (filters$account != "all") {
    rows <- dplyr::filter(rows, account == filters$account)
  }

  if (filters$category != "all") {
    rows <- dplyr::filter(rows, category_code == filters$category)
  }

  if (filters$merchant != "all") {
    rows <- dplyr::filter(rows, merchant_rule == filters$merchant)
  }

  if (filters$treatment != "all") {
    rows <- dplyr::filter(rows, display_treatment == filters$treatment)
  }

  if (filters$review_state != "all") {
    rows <- dplyr::filter(rows, review_state == filters$review_state)
  }

  rows <- rows |>
    dplyr::arrange(dplyr::desc(date), dplyr::desc(transaction_id))
  total_count <- nrow(rows)
  visible_rows <- rows |>
    dplyr::slice_head(n = result_limit) |>
    dplyr::select(
      transaction_id,
      account,
      date,
      description,
      amount,
      category_code,
      budget_category,
      transaction_type,
      display_treatment,
      review_state,
      is_reimbursable,
      is_excluded,
      override_note,
      budget_amount,
      merchant_rule,
      merchant_label
    )

  list(
    status = "ready",
    filters = list(
      start_date = format_optional_date(filters$start_date),
      end_date = format_optional_date(filters$end_date),
      search = filters$search,
      account = filters$account,
      category = filters$category,
      merchant = filters$merchant,
      treatment = filters$treatment,
      review_state = filters$review_state
    ),
    options = format_filter_options(options),
    pending_review_count = as.integer(pending_review_count),
    total_count = as.integer(total_count),
    displayed_count = as.integer(nrow(visible_rows)),
    is_truncated = total_count > result_limit,
    transactions = format_transaction_screen_rows(visible_rows)
  )
}

decision_request_field <- function(request, name) {
  if (is.null(request) || !name %in% names(request)) {
    stop("Transaction decision request is missing: ", name, call. = FALSE)
  }

  request[[name]]
}

normalize_transaction_decision_request <- function(request) {
  request_id <- as.character(decision_request_field(request, "request_id"))
  transaction_id <- as.character(decision_request_field(request, "transaction_id"))
  category_code <- as.character(decision_request_field(request, "category_code"))
  is_reimbursable <- decision_request_field(request, "is_reimbursable")
  is_excluded <- decision_request_field(request, "is_excluded")
  note <- if ("note" %in% names(request)) request$note else NULL

  if (
    length(request_id) != 1 ||
      is.na(request_id) ||
      !grepl("^[A-Za-z0-9._:-]{8,128}$", request_id)
  ) {
    stop("Transaction decision request ID is invalid.", call. = FALSE)
  }

  for (value in list(transaction_id = transaction_id, category_code = category_code)) {
    if (length(value) != 1 || is.na(value) || !nzchar(value)) {
      stop("Transaction decision identifier is invalid.", call. = FALSE)
    }
  }

  if (
    length(is_reimbursable) != 1 ||
      !is.logical(is_reimbursable) ||
      is.na(is_reimbursable) ||
      length(is_excluded) != 1 ||
      !is.logical(is_excluded) ||
      is.na(is_excluded)
  ) {
    stop("Transaction decision flags must be true or false.", call. = FALSE)
  }

  if (is.null(note)) {
    note <- NA_character_
  } else {
    note <- as.character(note)

    if (length(note) != 1) {
      stop("Transaction decision note must be one value.", call. = FALSE)
    }

    note <- if (is.na(note) || !nzchar(trimws(note))) {
      NA_character_
    } else {
      trimws(note)
    }
  }

  if (length(note) != 1 || (!is.na(note) && nchar(note) > 500)) {
    stop("Transaction decision note must contain at most 500 characters.", call. = FALSE)
  }

  list(
    request_id = request_id,
    transaction_id = transaction_id,
    category_code = category_code,
    is_reimbursable = is_reimbursable,
    is_excluded = is_excluded,
    note = note
  )
}

save_transaction_decision <- function(
  connection,
  request,
  changed_at = Sys.time()
) {
  request <- normalize_transaction_decision_request(request)
  audit_id <- make_stable_id(
    "audit",
    paste("transaction_decision_update", request$request_id, sep = "|")
  )
  prior_audit <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT entity_id FROM decision_audit_log",
      "WHERE audit_id = ?"
    ),
    params = list(audit_id)
  )

  if (nrow(prior_audit) > 0) {
    if (!identical(prior_audit$entity_id[[1]], request$transaction_id)) {
      stop("Transaction decision request ID was already used.", call. = FALSE)
    }

    return(list(
      status = "already_saved",
      request_id = request$request_id,
      transaction_id = request$transaction_id
    ))
  }

  category_exists <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT count(*) AS n FROM categories",
      "WHERE category_code = ? AND is_active"
    ),
    params = list(request$category_code)
  )$n[[1]] == 1

  if (!category_exists) {
    stop("Transaction decision category is not supported.", call. = FALSE)
  }

  before <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "transaction_id, category_code, assignment_source, assignment_rule,",
      "review_state, budget_treatment, is_reimbursable, is_excluded, note",
      "FROM transaction_decisions",
      "WHERE transaction_id = ?"
    ),
    params = list(request$transaction_id)
  )

  if (nrow(before) != 1) {
    stop("Transaction decision was not found.", call. = FALSE)
  }

  before_json <- as.character(jsonlite::toJSON(
    as.list(before[1, -1, drop = FALSE]),
    auto_unbox = TRUE,
    na = "null"
  ))
  after <- list(
    category_code = request$category_code,
    assignment_source = "transaction_override",
    assignment_rule = "manual_transaction_edit",
    review_state = "confirmed",
    budget_treatment = before$budget_treatment[[1]],
    is_reimbursable = request$is_reimbursable,
    is_excluded = request$is_excluded,
    note = request$note
  )
  after_json <- as.character(jsonlite::toJSON(
    after,
    auto_unbox = TRUE,
    na = "null"
  ))
  audit_row <- tibble::tibble(
    audit_id = audit_id,
    entity_type = "transaction_decision",
    entity_id = request$transaction_id,
    action = "transaction_decision_update",
    changed_at = as.POSIXct(changed_at, tz = "UTC"),
    before_json = before_json,
    after_json = after_json,
    change_note = if (is.na(request$note)) {
      "Transaction decision updated in application"
    } else {
      request$note
    }
  )

  DBI::dbWithTransaction(connection, {
    updated_count <- DBI::dbExecute(
      connection,
      paste(
        "UPDATE transaction_decisions SET",
        "category_code = ?,",
        "assignment_source = 'transaction_override',",
        "assignment_rule = 'manual_transaction_edit',",
        "review_state = 'confirmed',",
        "is_reimbursable = ?,",
        "is_excluded = ?,",
        "note = ?,",
        "updated_at = ?",
        "WHERE transaction_id = ?"
      ),
      params = list(
        request$category_code,
        request$is_reimbursable,
        request$is_excluded,
        request$note,
        as.POSIXct(changed_at, tz = "UTC"),
        request$transaction_id
      )
    )

    if (updated_count != 1) {
      stop("Transaction decision update did not affect exactly one row.")
    }

    DBI::dbAppendTable(connection, "decision_audit_log", audit_row)
  })

  list(
    status = "saved",
    request_id = request$request_id,
    transaction_id = request$transaction_id
  )
}
