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

configuration_number <- function(value, label) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1 || is.na(value) || !is.finite(value) ||
      value < 0) {
    stop(label, " must be a valid number at least zero.", call. = FALSE)
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

merchant_default_category_codes <- c(
  "food_living",
  "personal_discretionary",
  "transportation",
  "housing"
)

find_merchant_defaults <- function(connection, merchants) {
  descriptions <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT t.standardized_description AS display_name,",
      "min(t.transaction_date) AS first_seen_date",
      "FROM transactions t",
      "JOIN transaction_decisions d USING (transaction_id)",
      "WHERE d.budget_treatment IN ('expense', 'refund')",
      "GROUP BY t.standardized_description"
    )
  ) |>
    dplyr::mutate(first_seen_date = as.Date(first_seen_date))

  if (!nrow(descriptions)) {
    return(dplyr::mutate(descriptions, category_code = character()))
  }

  active_merchants <- merchants |>
    dplyr::filter(is_active) |>
    dplyr::arrange(priority)
  category_code <- purrr::map_chr(descriptions$display_name, function(description) {
    matches <- purrr::map_lgl(active_merchants$description_pattern, function(pattern) {
      stringr::str_detect(description, stringr::regex(pattern, ignore_case = TRUE))
    })
    if (any(matches)) active_merchants$category_code[[which(matches)[[1]]]] else NA_character_
  })

  descriptions |>
    dplyr::mutate(category_code = category_code) |>
    dplyr::arrange(stringr::str_to_lower(display_name))
}

find_new_merchants <- function(merchant_defaults, today) {
  current_month <- lubridate::floor_date(as.Date(today), "month")
  since_last_month <- seq.Date(current_month, by = "-1 month", length.out = 2)[[2]]

  dplyr::filter(merchant_defaults, first_seen_date >= since_last_month)
}

build_configuration_screen_contract <- function(connection, today = Sys.Date()) {
  categories <- configuration_categories(connection)
  merchants <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT rule_id, display_name, description_pattern,",
      "default_category_code AS category_code, effective_date, priority, is_active",
      "FROM merchant_rules ORDER BY lower(display_name), priority"
    )
  )
  versions <- read_database_budget_versions(connection)
  openings <- read_database_opening_balances(connection)
  merchant_defaults <- find_merchant_defaults(connection, merchants)
  new_merchants <- find_new_merchants(merchant_defaults, today)
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
    merchant_defaults = purrr::pmap(merchant_defaults, function(display_name, first_seen_date, category_code) {
      list(
        display_name = display_name,
        first_seen_date = as.character(first_seen_date),
        category_code = if (is.na(category_code)) NULL else category_code
      )
    }),
    new_merchants = purrr::pmap(new_merchants, function(display_name, first_seen_date, category_code) {
      list(
        display_name = display_name,
        first_seen_date = as.character(first_seen_date),
        category_code = if (is.na(category_code)) NULL else category_code
      )
    }),
    budget_versions = version_contracts,
    budget_setup = list(
      budget_start_month = if (nrow(openings)) {
        as.character(openings$budget_start_month[[1]])
      } else {
        NULL
      }
    )
  )
}

exact_merchant_pattern <- function(description) {
  escaped <- gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", description)
  paste0("^", escaped, "$")
}

save_merchant_default_configuration <- function(connection, request, changed_at = Sys.time(), today = Sys.Date()) {
  request_id <- configuration_request_id(request)
  prior_audit <- configuration_audit_exists(
    connection,
    "merchant_rule_save",
    request_id
  )

  if (nrow(prior_audit)) {
    return(list(
      status = "already_saved",
      request_id = request_id,
      rule_id = prior_audit$entity_id[[1]],
      matched_transaction_count = 0L
    ))
  }

  category_code <- as.character(configuration_field(request, "category_code"))
  if (length(category_code) != 1 || is.na(category_code) ||
      !category_code %in% merchant_default_category_codes) {
    stop("Merchant defaults must use Food & living, Personal, Transportation, or Housing.", call. = FALSE)
  }

  description <- if ("merchant_description" %in% names(request) && !is.null(request$merchant_description)) {
    trimws(as.character(request$merchant_description))
  } else {
    NULL
  }
  if (is.null(description) || length(description) != 1 || is.na(description) ||
      !nzchar(description) || nchar(description) > 100) {
    stop("Merchant name must contain 1 to 100 characters.", call. = FALSE)
  }

  category_exists <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM categories WHERE category_code = ? AND is_active",
    params = list(category_code)
  )$n[[1]] == 1
  if (!category_exists) stop("Merchant category is not supported.", call. = FALSE)

  pattern <- exact_merchant_pattern(description)
  existing <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM merchant_rules WHERE description_pattern = ? ORDER BY priority LIMIT 1",
    params = list(pattern)
  )
  creating <- nrow(existing) == 0

  if (creating) {
    rule_id <- make_stable_id("merchant", paste(request_id, description, sep = "|"))
    before <- NULL
    priority <- DBI::dbGetQuery(
      connection,
      "SELECT coalesce(min(priority), 10) - 10 AS priority FROM merchant_rules"
    )$priority[[1]]
    first_seen <- DBI::dbGetQuery(
      connection,
      "SELECT min(transaction_date) AS first_seen_date FROM transactions WHERE standardized_description = ?",
      params = list(description)
    )$first_seen_date[[1]]
    effective_date <- if (is.na(first_seen)) as.Date(today) else as.Date(first_seen)
  } else {
    rule_id <- existing$rule_id[[1]]
    before <- existing
    priority <- before$priority[[1]]
    effective_date <- as.Date(before$effective_date[[1]])
  }

  merchant_after <- list(
    display_name = description,
    description_pattern = pattern,
    category_code = category_code,
    effective_date = as.character(effective_date),
    priority = as.integer(priority),
    is_active = TRUE
  )

  merchant_audit <- tibble::tibble(
    audit_id = make_stable_id("audit", paste("merchant_rule_save", request_id, sep = "|")),
    entity_type = "merchant_rule",
    entity_id = rule_id,
    action = if (creating) "merchant_rule_create" else "merchant_rule_update",
    changed_at = as.POSIXct(changed_at, tz = "UTC"),
    before_json = if (creating) NA_character_ else configuration_json(as.list(before[1, , drop = FALSE])),
    after_json = configuration_json(merchant_after),
    change_note = "Merchant default saved for future imports"
  )

  DBI::dbWithTransaction(connection, {
    if (creating) {
      DBI::dbExecute(connection, paste(
        "INSERT INTO merchant_rules",
        "(rule_id, display_name, description_pattern, match_type, default_category_code, effective_date, priority, is_active, created_at, updated_at)",
        "VALUES (?, ?, ?, 'regular_expression', ?, ?, ?, ?, ?, ?)"
      ), params = list(rule_id, description, pattern, category_code,
        effective_date, priority, TRUE, as.POSIXct(changed_at, tz = "UTC"), as.POSIXct(changed_at, tz = "UTC")))
    } else {
      DBI::dbExecute(connection, paste(
        "UPDATE merchant_rules SET display_name = ?, description_pattern = ?,",
        "default_category_code = ?, effective_date = ?, is_active = ?, updated_at = ? WHERE rule_id = ?"
      ), params = list(description, pattern, category_code,
        effective_date, TRUE, as.POSIXct(changed_at, tz = "UTC"), rule_id))
    }
    DBI::dbAppendTable(connection, "decision_audit_log", merchant_audit)
  })
  list(
    status = "saved",
    request_id = request_id,
    rule_id = rule_id,
    matched_transaction_count = 0L
  )
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

save_rollover_start_configuration <- function(
  connection,
  request,
  changed_at = Sys.time(),
  today = Sys.Date()
) {
  request_id <- configuration_request_id(request)
  prior_audit <- configuration_audit_exists(
    connection,
    "rollover_start_save",
    request_id
  )

  if (nrow(prior_audit)) {
    return(list(status = "already_saved", request_id = request_id))
  }

  start_month <- configuration_month(
    configuration_field(request, "budget_start_month"),
    "Rollover start month"
  )
  current_month <- lubridate::floor_date(as.Date(today), "month")

  if (start_month > current_month) {
    stop("Rollover start month cannot be in the future.", call. = FALSE)
  }

  effective <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT count(*) AS n FROM budget_versions",
      "WHERE effective_month <= ?"
    ),
    params = list(start_month)
  )$n[[1]] > 0

  if (!effective) {
    stop(
      "Rollover start month must have an effective budget version.",
      call. = FALSE
    )
  }

  before <- read_database_opening_balances(connection)

  if (nrow(before) == 0) {
    stop("Rollover settings have not been initialized.", call. = FALSE)
  }

  before_months <- unique(before$budget_start_month)

  if (length(before_months) != 1) {
    stop("Every category must use the same rollover start month.", call. = FALSE)
  }

  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE budget_opening_balances",
        "SET budget_start_month = ?, updated_at = ?"
      ),
      params = list(
        start_month,
        as.POSIXct(changed_at, tz = "UTC")
      )
    )
    DBI::dbAppendTable(
      connection,
      "decision_audit_log",
      tibble::tibble(
        audit_id = make_stable_id(
          "audit",
          paste("rollover_start_save", request_id, sep = "|")
        ),
        entity_type = "opening_balance",
        entity_id = "all_categories",
        action = "rollover_start_save",
        changed_at = as.POSIXct(changed_at, tz = "UTC"),
        before_json = configuration_json(list(
          budget_start_month = as.character(before_months[[1]])
        )),
        after_json = configuration_json(list(
          budget_start_month = as.character(start_month)
        )),
        change_note = "Updated rollover start month"
      )
    )
  })

  list(status = "saved", request_id = request_id)
}

save_configuration_change <- function(connection, request, changed_at = Sys.time(), today = Sys.Date()) {
  kind <- as.character(configuration_field(request, "kind"))
  if (length(kind) != 1 || is.na(kind)) stop("Configuration change kind is invalid.", call. = FALSE)
  switch(kind,
    merchant_default = save_merchant_default_configuration(connection, request, changed_at, today),
    budget_version = save_budget_version_configuration(connection, request, changed_at, today),
    rollover_start = save_rollover_start_configuration(connection, request, changed_at, today),
    stop("Unsupported configuration change kind.", call. = FALSE)
  )
}
