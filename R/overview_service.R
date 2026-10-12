overview_accounts <- function() {
  tibble::tribble(
    ~account, ~label,
    "checking", "Checking",
    "credit_card_jacob", "Jacob's credit card",
    "credit_card_kendra", "Kendra's credit card"
  )
}

read_account_freshness <- function(connection) {
  latest_imports <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "account,",
      "max(coverage_end) AS data_through,",
      "max(imported_at) AS last_imported_at",
      "FROM imports",
      "WHERE outcome = 'successful'",
      "GROUP BY account"
    )
  )

  overview_accounts() |>
    dplyr::left_join(latest_imports, by = "account") |>
    dplyr::mutate(
      data_through = as.Date(data_through),
      last_imported_at = as.POSIXct(last_imported_at, tz = "UTC")
    )
}

normalize_overview_month <- function(selected_month = NULL, today = Sys.Date()) {
  current_month <- lubridate::floor_date(as.Date(today), unit = "month")

  if (is.null(selected_month) || !nzchar(selected_month)) {
    return(current_month)
  }

  selected_month <- as.character(selected_month)

  if (!grepl("^[0-9]{4}-[0-9]{2}-01$", selected_month)) {
    stop("Overview month must use YYYY-MM-01 format.", call. = FALSE)
  }

  parsed_month <- suppressWarnings(as.Date(selected_month))

  if (is.na(parsed_month)) {
    stop("Overview month is not a valid calendar month.", call. = FALSE)
  }

  parsed_month
}

format_optional_date <- function(value) {
  if (length(value) == 0 || is.na(value)) NULL else as.character(as.Date(value))
}

format_account_freshness_contract <- function(freshness) {
  purrr::pmap(
    freshness,
    function(account, label, data_through, last_imported_at) {
      list(
        account = account,
        label = label,
        data_through = format_optional_date(data_through),
        last_updated = format_optional_date(last_imported_at)
      )
    }
  )
}

month_elapsed_fraction <- function(selected_month, today = Sys.Date()) {
  selected_month <- lubridate::floor_date(as.Date(selected_month), "month")
  today <- as.Date(today)
  current_month <- lubridate::floor_date(today, "month")

  if (selected_month < current_month) {
    return(1)
  }

  min(1, lubridate::day(today) / lubridate::days_in_month(today))
}

classify_budget_pace <- function(
  net_spending,
  monthly_allocation,
  selected_month,
  today = Sys.Date()
) {
  if (monthly_allocation <= 0) {
    return(if (net_spending > 0) "danger" else "success")
  }

  spending_fraction <- max(net_spending, 0) / monthly_allocation

  if (spending_fraction > 1) {
    "danger"
  } else if (
    spending_fraction <= month_elapsed_fraction(selected_month, today)
  ) {
    "success"
  } else {
    "warning"
  }
}

format_category_card_contracts <- function(
  category_rows,
  selected_month,
  today = Sys.Date()
) {
  purrr::pmap(
    category_rows,
    function(
      category_code,
      budget_category,
      sort_order,
      monthly_allocation,
      net_spending,
      opening_balance,
      cumulative_rollover_balance
    ) {
      list(
        category_code = category_code,
        name = budget_category,
        monthly_allocation = monthly_allocation,
        net_spending = net_spending,
        opening_rollover = opening_balance,
        available_balance = cumulative_rollover_balance,
        pace_state = classify_budget_pace(
          net_spending,
          monthly_allocation,
          selected_month,
          today
        ),
        balance_state = if (
          cumulative_rollover_balance < 0
        ) "deficit" else "available"
      )
    }
  )
}

format_monthly_budget_totals <- function(
  category_rows,
  selected_month,
  today = Sys.Date()
) {
  total_monthly_budget <- sum(category_rows$monthly_allocation)
  net_spending <- sum(category_rows$net_spending)
  rollover_total <- sum(category_rows$opening_balance)

  list(
    total_monthly_budget = total_monthly_budget,
    net_spending = net_spending,
    rollover_total = rollover_total,
    pace_state = classify_budget_pace(
      net_spending,
      total_monthly_budget,
      selected_month,
      today
    )
  )
}

format_transaction_contracts <- function(transactions) {
  account_labels <- stats::setNames(
    overview_accounts()$label,
    overview_accounts()$account
  )

  purrr::pmap(
    transactions,
    function(
      transaction_id,
      account,
      date,
      description,
      amount,
      transaction_type,
      budget_category,
      budget_amount
    ) {
      list(
        transaction_id = transaction_id,
        account = account,
        account_label = unname(account_labels[[account]]),
        date = as.character(date),
        description = description,
        amount = amount,
        budget_treatment = transaction_type,
        category = budget_category,
        budget_effect = budget_amount
      )
    }
  )
}

build_overview_screen_contract <- function(
  connection,
  selected_month = NULL,
  selected_category = NULL,
  today = Sys.Date()
) {
  selected_month <- normalize_overview_month(selected_month, today)
  current_month <- lubridate::floor_date(as.Date(today), unit = "month")
  opening_balances <- read_database_opening_balances(connection)

  if (nrow(opening_balances) == 0) {
    stop("The database has no configured budget opening balances.", call. = FALSE)
  }

  budget_start_month <- unique(opening_balances$budget_start_month)

  if (length(budget_start_month) != 1) {
    stop("Every category must use the same budget start month.", call. = FALSE)
  }

  if (selected_month > current_month) {
    stop("Overview month cannot be in the future.", call. = FALSE)
  }

  budget_versions <- read_database_budget_versions(connection)
  transactions <- read_database_transactions(connection)
  earliest_budget_month <- min(budget_versions$effective_month)
  earliest_transaction_month <- if (nrow(transactions)) {
    lubridate::floor_date(min(transactions$date), "month")
  } else {
    earliest_budget_month
  }
  overview_start_month <- max(earliest_budget_month, earliest_transaction_month)

  if (selected_month < overview_start_month) {
    stop("Overview month precedes the available budget history.", call. = FALSE)
  }

  category_index <- opening_balances |>
    dplyr::select(category_code, budget_category, sort_order)
  category_codes <- category_index$category_code

  if (
    !is.null(selected_category) &&
      (!nzchar(selected_category) || !selected_category %in% category_codes)
  ) {
    stop("Overview category is not supported.", call. = FALSE)
  }

  rollover_active <- selected_month >= budget_start_month
  category_rows <- if (rollover_active) {
    build_database_rollover_ledger(
      connection,
      through_month = selected_month
    ) |>
      dplyr::filter(month == selected_month) |>
      dplyr::left_join(category_index, by = "budget_category") |>
      dplyr::arrange(sort_order) |>
      dplyr::select(
        category_code,
        budget_category,
        sort_order,
        monthly_allocation,
        net_spending,
        opening_balance,
        cumulative_rollover_balance
      )
  } else {
    month_after_selected <- seq.Date(selected_month, by = "month", length.out = 2)[[2]]
    allocations <- budget_versions |>
      dplyr::filter(effective_month <= selected_month) |>
      dplyr::group_by(category_code) |>
      dplyr::slice_max(effective_month, n = 1, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::select(category_code, monthly_allocation)
    spending <- transactions |>
      dplyr::filter(date >= selected_month, date < month_after_selected) |>
      dplyr::group_by(budget_category) |>
      dplyr::summarize(net_spending = sum(budget_amount), .groups = "drop")

    category_index |>
      dplyr::left_join(allocations, by = "category_code") |>
      dplyr::left_join(spending, by = "budget_category") |>
      dplyr::mutate(
        net_spending = dplyr::coalesce(net_spending, 0),
        opening_balance = 0,
        cumulative_rollover_balance = monthly_allocation - net_spending
      ) |>
      dplyr::arrange(sort_order)
  }

  month_after_selected <- seq.Date(
    selected_month,
    by = "month",
    length.out = 2
  )[[2]]
  selected_category_row <- if (is.null(selected_category)) {
    NULL
  } else {
    category_rows |>
      dplyr::filter(category_code == selected_category)
  }
  transaction_rows <- if (is.null(selected_category)) {
    tibble::tibble(
      transaction_id = character(),
      account = character(),
      date = as.Date(character()),
      description = character(),
      amount = double(),
      transaction_type = character(),
      budget_category = character(),
      budget_amount = double()
    )
  } else {
    selected_category_name <- selected_category_row$budget_category[[1]]

    transactions |>
      dplyr::filter(
        date >= selected_month,
        date < month_after_selected,
        budget_category == selected_category_name
      ) |>
      dplyr::arrange(dplyr::desc(date), dplyr::desc(transaction_id)) |>
      dplyr::select(
        transaction_id,
        account,
        date,
        description,
        amount,
        transaction_type,
        budget_category,
        budget_amount
      )
  }

  previous_month <- if (selected_month > overview_start_month) {
    seq.Date(selected_month, by = "-1 month", length.out = 2)[[2]]
  } else {
    NULL
  }
  next_month <- if (selected_month < current_month) {
    month_after_selected
  } else {
    NULL
  }

  list(
    status = "ready",
    selected_month = as.character(selected_month),
    month_label = format(selected_month, "%B %Y"),
    current_month = as.character(current_month),
    budget_start_month = as.character(budget_start_month),
    overview_start_month = as.character(overview_start_month),
    rollover_active = rollover_active,
    previous_month = format_optional_date(previous_month),
    next_month = format_optional_date(next_month),
    monthly_totals = format_monthly_budget_totals(
      category_rows,
      selected_month,
      today
    ),
    categories = format_category_card_contracts(
      category_rows,
      selected_month,
      today
    ),
    accounts = format_account_freshness_contract(
      read_account_freshness(connection)
    ),
    selected_category = if (is.null(selected_category_row)) {
      NULL
    } else {
      list(
        category_code = selected_category_row$category_code[[1]],
        name = selected_category_row$budget_category[[1]]
      )
    },
    transaction_count = nrow(transaction_rows),
    transactions = format_transaction_contracts(transaction_rows)
  )
}
