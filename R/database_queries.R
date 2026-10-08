read_database_transactions <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "WITH sighting_bounds AS (",
      "SELECT",
      "transaction_id,",
      "arg_min(import_id, seen_at) AS first_seen_import_id,",
      "arg_max(import_id, seen_at) AS last_seen_import_id,",
      "min(seen_at) AS first_seen_at,",
      "max(seen_at) AS last_seen_at",
      "FROM transaction_sightings",
      "GROUP BY transaction_id",
      ")",
      "SELECT",
      "t.transaction_id,",
      "t.account,",
      "t.transaction_date AS date,",
      "t.standardized_description AS description,",
      "CAST(t.standardized_amount AS DOUBLE) AS amount,",
      "t.standardized_check_number AS check_number,",
      "t.duplicate_sequence,",
      "t.composite_identity,",
      "d.budget_treatment AS transaction_type,",
      "d.category_code,",
      "c.display_name AS budget_category,",
      "d.assignment_source AS category_source,",
      "d.assignment_rule AS category_rule,",
      "d.review_state,",
      "d.is_reimbursable,",
      "d.is_excluded,",
      "d.note AS override_note,",
      "s.first_seen_import_id,",
      "s.last_seen_import_id,",
      "s.first_seen_at,",
      "s.last_seen_at",
      "FROM transactions t",
      "JOIN transaction_decisions d USING (transaction_id)",
      "JOIN sighting_bounds s USING (transaction_id)",
      "LEFT JOIN categories c USING (category_code)",
      "ORDER BY t.account, t.transaction_date, t.transaction_id"
    )
  ) |>
    dplyr::mutate(
      date = as.Date(date),
      is_budget_relevant =
        transaction_type %in% c("expense", "refund", "category_offset") &
        !is_reimbursable &
        !is_excluded &
        !is.na(budget_category),
      budget_amount = dplyr::if_else(
        is_budget_relevant,
        -amount,
        0
      )
    )
}

read_database_merchant_rules <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "m.priority AS rule_priority,",
      "m.rule_id AS rule_name,",
      "m.display_name,",
      "m.description_pattern,",
      "c.display_name AS budget_category,",
      "m.effective_date,",
      "m.is_active",
      "FROM merchant_rules m",
      "JOIN categories c",
      "ON m.default_category_code = c.category_code",
      "ORDER BY m.priority"
    )
  ) |>
    dplyr::mutate(effective_date = as.Date(effective_date))
}

read_database_budget_versions <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "v.budget_version_id,",
      "v.effective_month,",
      "CAST(v.total_monthly_budget AS DOUBLE) AS total_monthly_budget,",
      "a.category_code,",
      "c.display_name AS budget_category,",
      "c.sort_order,",
      "CAST(a.monthly_allocation AS DOUBLE) AS monthly_allocation",
      "FROM budget_versions v",
      "JOIN budget_allocations a USING (budget_version_id)",
      "JOIN categories c USING (category_code)",
      "ORDER BY v.effective_month, c.sort_order"
    )
  ) |>
    dplyr::mutate(effective_month = as.Date(effective_month))
}

read_database_opening_balances <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT",
      "b.category_code,",
      "c.display_name AS budget_category,",
      "c.sort_order,",
      "b.budget_start_month,",
      "CAST(b.opening_balance AS DOUBLE) AS configured_opening_balance",
      "FROM budget_opening_balances b",
      "JOIN categories c USING (category_code)",
      "ORDER BY c.sort_order"
    )
  ) |>
    dplyr::mutate(budget_start_month = as.Date(budget_start_month))
}

summarize_database_category_spending <- function(connection) {
  read_database_transactions(connection) |>
    dplyr::filter(!is.na(budget_category)) |>
    dplyr::group_by(budget_category) |>
    dplyr::summarize(
      net_spending = sum(budget_amount),
      .groups = "drop"
    ) |>
    dplyr::arrange(budget_category)
}

build_database_rollover_ledger <- function(
  connection,
  through_month = NULL
) {
  transactions <- read_database_transactions(connection)
  opening_balances <- read_database_opening_balances(connection)
  budget_versions <- read_database_budget_versions(connection)

  if (nrow(opening_balances) == 0) {
    stop("The database has no configured budget opening balances.")
  }

  budget_start_months <- unique(opening_balances$budget_start_month)

  if (length(budget_start_months) != 1) {
    stop("Every category must use the same configured budget start month.")
  }

  budget_start_month <- budget_start_months[[1]]

  if (is.null(through_month)) {
    through_month <- if (nrow(transactions) == 0) {
      budget_start_month
    } else {
      max(lubridate::floor_date(transactions$date, unit = "month"))
    }
  }

  through_month <- lubridate::floor_date(as.Date(through_month), unit = "month")

  if (through_month < budget_start_month) {
    stop("The rollover end month cannot precede the budget start month.")
  }

  month_after_through <- seq.Date(
    through_month,
    by = "month",
    length.out = 2
  )[[2]]

  budget_months <- tibble::tibble(
    month = seq.Date(budget_start_month, through_month, by = "month")
  )

  month_categories <- tidyr::crossing(
    budget_months,
    opening_balances |>
      dplyr::select(
        category_code,
        budget_category,
        sort_order,
        configured_opening_balance
      )
  )

  effective_allocations <- month_categories |>
    dplyr::left_join(
      budget_versions |>
        dplyr::select(
          budget_version_id,
          effective_month,
          category_code,
          monthly_allocation
        ),
      by = "category_code",
      relationship = "many-to-many"
    ) |>
    dplyr::filter(effective_month <= month) |>
    dplyr::group_by(month, category_code) |>
    dplyr::slice_max(effective_month, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()

  if (nrow(effective_allocations) != nrow(month_categories)) {
    stop("Every category and month must have an effective budget allocation.")
  }

  monthly_spending <- transactions |>
    dplyr::filter(
      !is.na(budget_category),
      date >= budget_start_month,
      date < month_after_through
    ) |>
    dplyr::mutate(month = lubridate::floor_date(date, unit = "month")) |>
    dplyr::group_by(month, budget_category) |>
    dplyr::summarize(
      net_spending = sum(budget_amount),
      .groups = "drop"
    )

  effective_allocations |>
    dplyr::left_join(
      monthly_spending,
      by = c("month", "budget_category")
    ) |>
    dplyr::mutate(
      net_spending = tidyr::replace_na(net_spending, 0),
      monthly_balance_change = monthly_allocation - net_spending
    ) |>
    dplyr::arrange(sort_order, month) |>
    dplyr::group_by(category_code) |>
    dplyr::mutate(
      cumulative_rollover_balance =
        configured_opening_balance + cumsum(monthly_balance_change),
      opening_balance =
        cumulative_rollover_balance - monthly_balance_change
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      month,
      budget_category,
      monthly_allocation,
      net_spending,
      monthly_balance_change,
      opening_balance,
      cumulative_rollover_balance
    ) |>
    dplyr::arrange(month, budget_category)
}

compare_pipeline_to_database <- function(
  connection,
  pipeline_transactions,
  pipeline_rollover_ledger,
  pipeline_merchant_rules
) {
  database_transactions <- read_database_transactions(connection)

  pipeline_transaction_comparison <- pipeline_transactions |>
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
    dplyr::select(
      composite_identity,
      account,
      date,
      description,
      amount,
      check_number,
      duplicate_sequence,
      transaction_type,
      budget_category,
      category_source,
      category_rule,
      is_reimbursable,
      budget_amount
    ) |>
    dplyr::arrange(composite_identity)

  database_transaction_comparison <- database_transactions |>
    dplyr::select(dplyr::all_of(names(pipeline_transaction_comparison))) |>
    dplyr::arrange(composite_identity)

  pipeline_category_summary <- pipeline_transactions |>
    dplyr::filter(!is.na(budget_category)) |>
    dplyr::group_by(budget_category) |>
    dplyr::summarize(net_spending = sum(budget_amount), .groups = "drop") |>
    dplyr::arrange(budget_category)

  database_category_summary <- summarize_database_category_spending(connection)

  pipeline_rollover_comparison <- pipeline_rollover_ledger |>
    dplyr::select(
      month,
      budget_category,
      monthly_allocation,
      net_spending,
      monthly_balance_change,
      opening_balance,
      cumulative_rollover_balance
    ) |>
    dplyr::arrange(month, budget_category)

  database_rollover_comparison <- build_database_rollover_ledger(
    connection,
    through_month = max(pipeline_rollover_comparison$month)
  )

  database_merchant_comparison <- read_database_merchant_rules(connection) |>
    dplyr::select(
      rule_priority,
      rule_name,
      description_pattern,
      budget_category
    )

  pipeline_merchant_comparison <- pipeline_merchant_rules |>
    dplyr::select(dplyr::all_of(names(database_merchant_comparison))) |>
    dplyr::arrange(rule_priority)

  comparisons <- list(
    transactions = all.equal(
      database_transaction_comparison,
      pipeline_transaction_comparison,
      check.attributes = FALSE
    ),
    category_spending = all.equal(
      database_category_summary,
      pipeline_category_summary,
      check.attributes = FALSE,
      tolerance = 1e-8
    ),
    rollover_ledger = all.equal(
      database_rollover_comparison,
      pipeline_rollover_comparison,
      check.attributes = FALSE,
      tolerance = 1e-8
    ),
    merchant_rules = all.equal(
      database_merchant_comparison,
      pipeline_merchant_comparison,
      check.attributes = FALSE
    )
  )

  failed_comparisons <- names(comparisons)[
    !vapply(comparisons, isTRUE, logical(1))
  ]

  if (length(failed_comparisons) > 0) {
    failure_details <- vapply(
      failed_comparisons,
      function(comparison_name) {
        paste0(
          comparison_name,
          ": ",
          paste(comparisons[[comparison_name]], collapse = "; ")
        )
      },
      character(1)
    )
    stop(
      "Database equivalence failed.\n",
      paste(failure_details, collapse = "\n"),
      call. = FALSE
    )
  }

  tibble::tibble(
    comparison = names(comparisons),
    passed = TRUE
  )
}
