configuration_categories <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT category_code, display_name, sort_order",
      "FROM categories WHERE is_active ORDER BY sort_order"
    )
  )
}

configuration_month <- function(value, label) {
  value <- as.character(value)
  if (length(value) != 1 || is.na(value) ||
      !grepl("^[0-9]{4}-[0-9]{2}-01$", value)) {
    stop(label, " must be the first day of a month.", call. = FALSE)
  }
  parsed <- suppressWarnings(as.Date(value))
  if (is.na(parsed)) stop(label, " is invalid.", call. = FALSE)
  parsed
}

configuration_date <- function(value, label) {
  value <- as.character(value)
  if (length(value) != 1 || is.na(value) ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)) {
    stop(label, " must use YYYY-MM-DD format.", call. = FALSE)
  }
  parsed <- suppressWarnings(as.Date(value))
  if (is.na(parsed)) stop(label, " is invalid.", call. = FALSE)
  parsed
}

configuration_request_id <- function(request) {
  if (is.null(request) || !"request_id" %in% names(request)) {
    stop("Configuration request is missing: request_id", call. = FALSE)
  }
  value <- as.character(request$request_id)
  if (length(value) != 1 || is.na(value) ||
      !grepl("^[A-Za-z0-9._:-]{8,128}$", value)) {
    stop("Configuration request ID is invalid.", call. = FALSE)
  }
  value
}

configuration_field <- function(request, name) {
  if (is.null(request) || !name %in% names(request)) {
    stop("Configuration request is missing: ", name, call. = FALSE)
  }
  request[[name]]
}

configuration_number <- function(value, label, allow_negative = FALSE) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1 || is.na(value) || !is.finite(value) ||
      (!allow_negative && value < 0)) {
    stop(label, " must be a valid number", if (!allow_negative) " at least zero" else "", ".", call. = FALSE)
  }
  round(value, 2)
}

configuration_json <- function(value) {
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, na = "null"))
}

configuration_audit_exists <- function(connection, action, request_id) {
  audit_id <- make_stable_id("audit", paste(action, request_id, sep = "|"))
  DBI::dbGetQuery(
    connection,
    "SELECT entity_id FROM decision_audit_log WHERE audit_id = ?",
    params = list(audit_id)
  )
}

format_configuration_categories <- function(categories) {
  purrr::pmap(categories, function(category_code, display_name, sort_order) {
    list(value = category_code, label = display_name, sort_order = as.integer(sort_order))
  })
}

build_configuration_screen_contract <- function(connection, today = Sys.Date()) {
  categories <- configuration_categories(connection)
  merchants <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT rule_id, display_name, description_pattern,",
      "default_category_code AS category_code, effective_date, priority, is_active",
      "FROM merchant_rules ORDER BY priority"
    )
  )
  versions <- read_database_budget_versions(connection)
  openings <- read_database_opening_balances(connection)
  current_month <- lubridate::floor_date(as.Date(today), "month")
  default_effective_month <- seq.Date(current_month, by = "month", length.out = 2)[[2]]

  version_contracts <- versions |>
    dplyr::group_split(budget_version_id) |>
    purrr::map(function(rows) {
      list(
        budget_version_id = rows$budget_version_id[[1]],
        effective_month = as.character(rows$effective_month[[1]]),
        total_monthly_budget = rows$total_monthly_budget[[1]],
        allocations = purrr::pmap(
          rows |> dplyr::select(category_code, budget_category, monthly_allocation),
          ~ list(category_code = ..1, category = ..2, amount = ..3)
        )
      )
    })

  list(
    status = "ready",
    current_month = as.character(current_month),
    default_effective_month = as.character(default_effective_month),
    categories = format_configuration_categories(categories),
    merchants = purrr::pmap(merchants, function(
      rule_id, display_name, description_pattern, category_code,
      effective_date, priority, is_active
    ) {
      list(
        rule_id = rule_id,
        display_name = display_name,
        description_pattern = description_pattern,
        category_code = category_code,
        effective_date = as.character(effective_date),
        priority = as.integer(priority),
        is_active = is_active
      )
    }),
    budget_versions = version_contracts,
    budget_setup = list(
      budget_start_month = if (nrow(openings)) as.character(openings$budget_start_month[[1]]) else NULL,
      opening_balances = purrr::pmap(
        openings |> dplyr::select(category_code, budget_category, configured_opening_balance),
        ~ list(category_code = ..1, category = ..2, amount = ..3)
      )
    )
  )
}

normalize_merchant_request <- function(request) {
  display_name <- trimws(as.character(configuration_field(request, "display_name")))
  pattern <- trimws(as.character(configuration_field(request, "description_pattern")))
  category_code <- as.character(configuration_field(request, "category_code"))
  is_active <- configuration_field(request, "is_active")
  apply_existing <- configuration_field(request, "apply_existing")
  rule_id <- if ("rule_id" %in% names(request) && !is.null(request$rule_id)) as.character(request$rule_id) else NULL

  if (length(display_name) != 1 || is.na(display_name) || !nzchar(display_name) || nchar(display_name) > 100) {
    stop("Merchant display name must contain 1 to 100 characters.", call. = FALSE)
  }
  if (length(pattern) != 1 || is.na(pattern) || !nzchar(pattern) || nchar(pattern) > 500) {
    stop("Merchant regular expression must contain 1 to 500 characters.", call. = FALSE)
  }
  tryCatch(stringr::str_detect("", stringr::regex(pattern, ignore_case = TRUE)), error = function(error) {
    stop("Merchant regular expression is invalid: ", conditionMessage(error), call. = FALSE)
  })
  if (length(category_code) != 1 || is.na(category_code) || !nzchar(category_code)) {
    stop("Merchant category is invalid.", call. = FALSE)
  }
  if (!is.logical(is_active) || length(is_active) != 1 || is.na(is_active) ||
      !is.logical(apply_existing) || length(apply_existing) != 1 || is.na(apply_existing)) {
    stop("Merchant flags must be true or false.", call. = FALSE)
  }
  if (apply_existing && !is_active) {
    stop("An inactive merchant rule cannot be applied to existing transactions.", call. = FALSE)
  }
  list(
    request_id = configuration_request_id(request),
    rule_id = rule_id,
    display_name = display_name,
    description_pattern = pattern,
    category_code = category_code,
    effective_date = configuration_date(configuration_field(request, "effective_date"), "Merchant effective date"),
    is_active = is_active,
    apply_existing = apply_existing
  )
}

save_merchant_configuration <- function(connection, request, changed_at = Sys.time()) {
  request <- normalize_merchant_request(request)
  prior_audit <- configuration_audit_exists(connection, "merchant_rule_save", request$request_id)
  if (nrow(prior_audit)) {
    return(list(status = "already_saved", request_id = request$request_id, rule_id = prior_audit$entity_id[[1]]))
  }
  category_exists <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM categories WHERE category_code = ? AND is_active",
    params = list(request$category_code)
  )$n[[1]] == 1
  if (!category_exists) stop("Merchant category is not supported.", call. = FALSE)

  creating <- is.null(request$rule_id) || !nzchar(request$rule_id)
  if (creating) {
    rule_id <- make_stable_id("merchant", paste(request$request_id, request$display_name, sep = "|"))
    before <- NULL
    priority <- DBI::dbGetQuery(connection, "SELECT coalesce(max(priority), 0) + 10 AS priority FROM merchant_rules")$priority[[1]]
  } else {
    rule_id <- request$rule_id
    before <- DBI::dbGetQuery(connection, "SELECT * FROM merchant_rules WHERE rule_id = ?", params = list(rule_id))
    if (nrow(before) != 1) stop("Merchant rule was not found.", call. = FALSE)
    priority <- before$priority[[1]]
  }
  merchant_after <- list(
    display_name = request$display_name,
    description_pattern = request$description_pattern,
    category_code = request$category_code,
    effective_date = as.character(request$effective_date),
    priority = as.integer(priority),
    is_active = request$is_active
  )
  candidates <- read_database_transactions(connection) |>
    dplyr::filter(
      date >= request$effective_date,
      transaction_type %in% c("expense", "refund"),
      stringr::str_detect(description, stringr::regex(request$description_pattern, ignore_case = TRUE))
    )
  if (!request$apply_existing) candidates <- dplyr::slice_head(candidates, n = 0)

  merchant_audit <- tibble::tibble(
    audit_id = make_stable_id("audit", paste("merchant_rule_save", request$request_id, sep = "|")),
    entity_type = "merchant_rule",
    entity_id = rule_id,
    action = if (creating) "merchant_rule_create" else "merchant_rule_update",
    changed_at = as.POSIXct(changed_at, tz = "UTC"),
    before_json = if (creating) NA_character_ else configuration_json(as.list(before[1, , drop = FALSE])),
    after_json = configuration_json(merchant_after),
    change_note = if (request$apply_existing) "Merchant rule saved and applied to existing matches" else "Merchant rule saved for future imports"
  )

  DBI::dbWithTransaction(connection, {
    if (creating) {
      DBI::dbExecute(connection, paste(
        "INSERT INTO merchant_rules",
        "(rule_id, display_name, description_pattern, match_type, default_category_code, effective_date, priority, is_active, created_at, updated_at)",
        "VALUES (?, ?, ?, 'regular_expression', ?, ?, ?, ?, ?, ?)"
      ), params = list(rule_id, request$display_name, request$description_pattern, request$category_code,
        request$effective_date, priority, request$is_active, as.POSIXct(changed_at, tz = "UTC"), as.POSIXct(changed_at, tz = "UTC")))
    } else {
      DBI::dbExecute(connection, paste(
        "UPDATE merchant_rules SET display_name = ?, description_pattern = ?,",
        "default_category_code = ?, effective_date = ?, is_active = ?, updated_at = ? WHERE rule_id = ?"
      ), params = list(request$display_name, request$description_pattern, request$category_code,
        request$effective_date, request$is_active, as.POSIXct(changed_at, tz = "UTC"), rule_id))
    }
    DBI::dbAppendTable(connection, "decision_audit_log", merchant_audit)

    if (nrow(candidates)) {
      purrr::pwalk(candidates, function(transaction_id, account, date, description, amount,
                                        check_number, duplicate_sequence, composite_identity,
                                        transaction_type, category_code, budget_category,
                                        category_source, category_rule, review_state,
                                        is_reimbursable, is_excluded, override_note,
                                        first_seen_import_id, last_seen_import_id,
                                        first_seen_at, last_seen_at, is_budget_relevant,
                                        budget_amount) {
        after <- list(category_code = request$category_code, assignment_source = "merchant_rule",
          assignment_rule = rule_id, review_state = "confirmed", budget_treatment = transaction_type,
          is_reimbursable = is_reimbursable, is_excluded = is_excluded,
          note = if (is.na(override_note)) NA_character_ else override_note)
        DBI::dbExecute(connection, paste(
          "UPDATE transaction_decisions SET category_code = ?, assignment_source = 'merchant_rule',",
          "assignment_rule = ?, review_state = 'confirmed', updated_at = ? WHERE transaction_id = ?"
        ), params = list(request$category_code, rule_id, as.POSIXct(changed_at, tz = "UTC"), transaction_id))
        DBI::dbAppendTable(connection, "decision_audit_log", tibble::tibble(
          audit_id = make_stable_id("audit", paste("merchant_rule_apply", request$request_id, transaction_id, sep = "|")),
          entity_type = "transaction_decision", entity_id = transaction_id,
          action = "merchant_rule_apply_existing", changed_at = as.POSIXct(changed_at, tz = "UTC"),
          before_json = configuration_json(list(category_code = category_code, assignment_source = category_source,
            assignment_rule = category_rule, review_state = review_state)),
          after_json = configuration_json(after), change_note = paste("Applied merchant rule", request$display_name)
        ))
      })
    }
  })
  list(status = "saved", request_id = request$request_id, rule_id = rule_id, matched_transaction_count = nrow(candidates))
}

normalize_allocation_request <- function(connection, request, value_name) {
  allocations <- configuration_field(request, value_name)
  if (!is.list(allocations)) stop("Budget allocations are invalid.", call. = FALSE)
  rows <- purrr::map_dfr(allocations, function(item) {
    tibble::tibble(category_code = as.character(configuration_field(item, "category_code")),
      amount = configuration_number(configuration_field(item, "amount"), "Budget allocation"))
  })
  categories <- configuration_categories(connection)
  if (nrow(rows) != nrow(categories) || anyDuplicated(rows$category_code) ||
      !setequal(rows$category_code, categories$category_code)) {
    stop("Budget allocations must contain each fixed category exactly once.", call. = FALSE)
  }
  rows |> dplyr::left_join(categories, by = "category_code") |> dplyr::arrange(sort_order)
}

save_budget_version_configuration <- function(connection, request, changed_at = Sys.time(), today = Sys.Date()) {
  request_id <- configuration_request_id(request)
  prior_audit <- configuration_audit_exists(connection, "budget_version_create", request_id)
  if (nrow(prior_audit)) return(list(status = "already_saved", request_id = request_id, budget_version_id = prior_audit$entity_id[[1]]))
  effective_month <- configuration_month(configuration_field(request, "effective_month"), "Budget effective month")
  if (effective_month < lubridate::floor_date(as.Date(today), "month")) {
    stop("Budget effective month cannot be earlier than the current month.", call. = FALSE)
  }
  allocations <- normalize_allocation_request(connection, request, "allocations")
  total <- configuration_number(configuration_field(request, "total_monthly_budget"), "Monthly budget total")
  validate_budget_allocations(allocations |> dplyr::transmute(budget_category = display_name, monthly_allocation = amount), total)
  if (DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM budget_versions WHERE effective_month = ?", params = list(effective_month))$n[[1]] > 0) {
    stop("A budget version already exists for that effective month.", call. = FALSE)
  }
  version_id <- make_stable_id("budget", paste(request_id, effective_month, sep = "|"))
  after <- list(effective_month = as.character(effective_month), total_monthly_budget = total,
    allocations = purrr::pmap(allocations |> dplyr::select(category_code, amount), ~ list(category_code = ..1, amount = ..2)))
  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(connection, "INSERT INTO budget_versions VALUES (?, ?, ?, ?)",
      params = list(version_id, effective_month, total, as.POSIXct(changed_at, tz = "UTC")))
    DBI::dbAppendTable(connection, "budget_allocations", allocations |>
      dplyr::transmute(budget_version_id = version_id, category_code, monthly_allocation = amount))
    DBI::dbAppendTable(connection, "decision_audit_log", tibble::tibble(
      audit_id = make_stable_id("audit", paste("budget_version_create", request_id, sep = "|")),
      entity_type = "budget_version", entity_id = version_id, action = "budget_version_create",
      changed_at = as.POSIXct(changed_at, tz = "UTC"), before_json = NA_character_,
      after_json = configuration_json(after), change_note = "Created monthly budget version"
    ))
  })
  list(status = "saved", request_id = request_id, budget_version_id = version_id)
}

save_opening_balance_configuration <- function(connection, request, changed_at = Sys.time(), today = Sys.Date()) {
  request_id <- configuration_request_id(request)
  prior_audit <- configuration_audit_exists(connection, "opening_balance_save", request_id)
  if (nrow(prior_audit)) return(list(status = "already_saved", request_id = request_id))
  start_month <- configuration_month(configuration_field(request, "budget_start_month"), "Budget start month")
  if (start_month > lubridate::floor_date(as.Date(today), "month")) {
    stop("Budget start month cannot be in the future.", call. = FALSE)
  }
  balances <- configuration_field(request, "opening_balances")
  if (!is.list(balances)) stop("Opening balances are invalid.", call. = FALSE)
  rows <- purrr::map_dfr(balances, function(item) tibble::tibble(
    category_code = as.character(configuration_field(item, "category_code")),
    amount = configuration_number(configuration_field(item, "amount"), "Opening balance", allow_negative = TRUE)
  ))
  categories <- configuration_categories(connection)
  if (nrow(rows) != nrow(categories) || anyDuplicated(rows$category_code) || !setequal(rows$category_code, categories$category_code)) {
    stop("Opening balances must contain each fixed category exactly once.", call. = FALSE)
  }
  effective <- DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM budget_versions WHERE effective_month <= ?", params = list(start_month))$n[[1]] > 0
  if (!effective) stop("Budget start month must have an effective budget version.", call. = FALSE)
  before <- read_database_opening_balances(connection)
  after <- list(budget_start_month = as.character(start_month), opening_balances =
    purrr::pmap(rows, ~ list(category_code = ..1, amount = ..2)))
  DBI::dbWithTransaction(connection, {
    purrr::pwalk(rows, function(category_code, amount) {
      DBI::dbExecute(connection, paste(
        "INSERT INTO budget_opening_balances VALUES (?, ?, ?, ?)",
        "ON CONFLICT (category_code) DO UPDATE SET budget_start_month = excluded.budget_start_month,",
        "opening_balance = excluded.opening_balance, updated_at = excluded.updated_at"
      ), params = list(category_code, start_month, amount, as.POSIXct(changed_at, tz = "UTC")))
    })
    DBI::dbAppendTable(connection, "decision_audit_log", tibble::tibble(
      audit_id = make_stable_id("audit", paste("opening_balance_save", request_id, sep = "|")),
      entity_type = "opening_balance", entity_id = "all_categories", action = "opening_balance_save",
      changed_at = as.POSIXct(changed_at, tz = "UTC"), before_json = configuration_json(before),
      after_json = configuration_json(after), change_note = "Updated budget start and opening balances"
    ))
  })
  list(status = "saved", request_id = request_id)
}

save_configuration_change <- function(connection, request, changed_at = Sys.time(), today = Sys.Date()) {
  kind <- as.character(configuration_field(request, "kind"))
  if (length(kind) != 1 || is.na(kind)) stop("Configuration change kind is invalid.", call. = FALSE)
  switch(kind,
    merchant = save_merchant_configuration(connection, request, changed_at),
    budget_version = save_budget_version_configuration(connection, request, changed_at, today),
    opening_balances = save_opening_balance_configuration(connection, request, changed_at, today),
    stop("Unsupported configuration change kind.", call. = FALSE)
  )
}
