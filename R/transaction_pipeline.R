# Reusable transaction import functions ---------------------------------

expected_transaction_columns <- c(
  "DATE",
  "DESCRIPTION",
  "AMOUNT",
  "CHECK #",
  "STATUS"
)

read_account_export <- function(file_path, account) {
  if (!file.exists(file_path)) {
    stop("The account export does not exist: ", file_path)
  }

  transactions_raw <- readr::read_csv(
    file = file_path,
    col_types = readr::cols(.default = readr::col_character())
  )

  actual_columns <- names(transactions_raw)

  if (!identical(actual_columns, expected_transaction_columns)) {
    stop(
      "Unexpected columns in ",
      basename(file_path),
      ". Expected: ",
      paste(expected_transaction_columns, collapse = ", "),
      ". Found: ",
      paste(actual_columns, collapse = ", ")
    )
  }

  transactions_raw |>
    dplyr::mutate(
      source_row_number = dplyr::row_number(),
      .before = 1
    ) |>
    dplyr::filter(STATUS == "Posted") |>
    dplyr::transmute(
      account = .env$account,
      source_file = basename(.env$file_path),
      source_row_number,
      date = readr::parse_date(DATE, format = "%m/%d/%Y"),
      description = stringr::str_squish(DESCRIPTION),
      amount = readr::parse_double(AMOUNT),
      check_number = dplyr::na_if(
        stringr::str_squish(`CHECK #`),
        ""
      )
    )
}

add_transaction_identity <- function(transactions) {
  transactions |>
    dplyr::group_by(
      account,
      date,
      description,
      amount,
      check_number
    ) |>
    dplyr::arrange(source_row_number, .by_group = TRUE) |>
    dplyr::mutate(
      duplicate_sequence = dplyr::row_number()
    ) |>
    dplyr::ungroup()
}

classify_transaction_types <- function(transactions) {
  transactions |>
    dplyr::mutate(
      transaction_type = dplyr::case_when(
        account == "checking" &
          amount < 0 &
          stringr::str_detect(
            description,
            "^ONLINE TRANSFER .* TO WELLS FARGO (ACTIVE CA|AUTOGRAPH)"
          ) ~ "transfer_or_card_payment",
        stringr::str_starts(account, "credit_card_") &
          amount > 0 &
          description == "ONLINE PAYMENT THANK YOU" ~
          "transfer_or_card_payment",
        stringr::str_starts(account, "credit_card_") &
          amount > 0 ~ "refund",
        account == "checking" &
          amount > 0 &
          stringr::str_starts(description, "ZELLE FROM BRENT HALES") ~
          "category_offset",
        account == "checking" &
          amount > 0 &
          stringr::str_detect(description, "EXPENSE REPORT") ~
          "reimbursement",
        account == "checking" & amount > 0 ~ "excluded_inflow",
        account == "checking" &
          amount < 0 &
          stringr::str_starts(description, "ZELLE TO MILLER JONATHAN") ~
          "pass_through",
        account == "checking" &
          amount < 0 &
          stringr::str_starts(
            description,
            "UTAH801/297-7703 TAX PAYMNT"
          ) ~ "excluded_outflow",
        amount < 0 ~ "expense",
        TRUE ~ "needs_review"
      )
    )
}

find_duplicate_transaction_groups <- function(transactions) {
  transactions |>
    dplyr::group_by(
      account,
      date,
      description,
      amount,
      check_number
    ) |>
    dplyr::summarize(
      duplicate_count = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::filter(duplicate_count > 1) |>
    dplyr::arrange(
      dplyr::desc(duplicate_count),
      account,
      date
    )
}

apply_category_rules <- function(transactions, merchant_rules) {
  merchant_rules <- merchant_rules |>
    dplyr::arrange(rule_priority)

  transactions_categorized <- transactions |>
    dplyr::mutate(
      budget_category = dplyr::case_when(
        transaction_type == "category_offset" ~
          "Housing & related expenses",
        account == "checking" &
          check_number %in% c("4", "5") ~
          "Housing & related expenses",
        account == "checking" &
          date == as.Date("2026-07-21") &
          stringr::str_starts(description, "ZELLE TO BARNEY REGISTER") ~
          "Personal & discretionary",
        TRUE ~ NA_character_
      ),
      category_source = dplyr::case_when(
        transaction_type == "category_offset" ~ "transaction_type_rule",
        account == "checking" &
          check_number %in% c("4", "5") ~ "transaction_override",
        account == "checking" &
          date == as.Date("2026-07-21") &
          stringr::str_starts(description, "ZELLE TO BARNEY REGISTER") ~
          "transaction_override",
        TRUE ~ NA_character_
      ),
      category_rule = dplyr::case_when(
        transaction_type == "category_offset" ~ "rental_income_offset",
        account == "checking" &
          check_number %in% c("4", "5") ~ "known_housing_checks",
        account == "checking" &
          date == as.Date("2026-07-21") &
          stringr::str_starts(description, "ZELLE TO BARNEY REGISTER") ~
          "house_cleaning_override",
        TRUE ~ NA_character_
      )
    )

  for (rule_index in seq_len(nrow(merchant_rules))) {
    rule_matches <-
      is.na(transactions_categorized$budget_category) &
      transactions_categorized$transaction_type %in% c("expense", "refund") &
      stringr::str_detect(
        transactions_categorized$description,
        stringr::regex(
          merchant_rules$description_pattern[[rule_index]],
          ignore_case = TRUE
        )
      )

    transactions_categorized <- transactions_categorized |>
      dplyr::mutate(
        budget_category = dplyr::if_else(
          .env$rule_matches,
          merchant_rules$budget_category[[rule_index]],
          budget_category
        ),
        category_source = dplyr::if_else(
          .env$rule_matches,
          "merchant_rule",
          category_source
        ),
        category_rule = dplyr::if_else(
          .env$rule_matches,
          merchant_rules$rule_name[[rule_index]],
          category_rule
        )
      )
  }

  transactions_categorized |>
    dplyr::mutate(
      category_source = dplyr::case_when(
        !is.na(category_source) ~ category_source,
        transaction_type %in% c("expense", "refund") ~ "default",
        TRUE ~ NA_character_
      ),
      category_rule = dplyr::case_when(
        !is.na(category_rule) ~ category_rule,
        transaction_type %in% c("expense", "refund") ~
          "personal_discretionary_fallback",
        TRUE ~ NA_character_
      ),
      budget_category = dplyr::case_when(
        !is.na(budget_category) ~ budget_category,
        transaction_type %in% c("expense", "refund") ~
          "Personal & discretionary",
        TRUE ~ NA_character_
      )
    )
}

build_airfare_review <- function(transactions) {
  transactions |>
    dplyr::filter(
      transaction_type == "expense",
      stringr::str_detect(
        description,
        stringr::regex(
          paste(
            "^BRITISH AWYS",
            "^SOUTHWES",
            "^DELTA",
            "^UNITED [0-9]",
            "^FRONTIER AI",
            "^ALASKA AIR",
            "^AMERICAN AIR",
            "^EDREAMS",
            sep = "|"
          ),
          ignore_case = TRUE
        )
      )
    ) |>
    dplyr::arrange(date, account, description) |>
    dplyr::mutate(
      review_id = dplyr::row_number(),
      amount_spent = -amount
    ) |>
    dplyr::select(
      review_id,
      account,
      date,
      description,
      amount,
      amount_spent,
      check_number,
      duplicate_sequence
    )
}

read_transaction_overrides <- function(file_path) {
  if (!file.exists(file_path)) {
    return(
      tibble::tibble(
        account = character(),
        date = as.Date(character()),
        description = character(),
        amount = double(),
        check_number = character(),
        duplicate_sequence = integer(),
        is_reimbursable = logical(),
        budget_category_override = character(),
        override_note = character()
      )
    )
  }

  readr::read_csv(
    file = file_path,
    col_types = readr::cols(
      account = readr::col_character(),
      date = readr::col_date(format = "%Y-%m-%d"),
      description = readr::col_character(),
      amount = readr::col_double(),
      check_number = readr::col_character(),
      duplicate_sequence = readr::col_integer(),
      is_reimbursable = readr::col_logical(),
      budget_category_override = readr::col_character(),
      override_note = readr::col_character()
    )
  )
}

apply_transaction_overrides <- function(transactions, transaction_overrides) {
  transaction_key <- c(
    "account",
    "date",
    "description",
    "amount",
    "check_number",
    "duplicate_sequence"
  )

  duplicate_overrides <- transaction_overrides |>
    dplyr::group_by(
      dplyr::across(dplyr::all_of(transaction_key))
    ) |>
    dplyr::summarize(
      override_count = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::filter(override_count > 1)

  if (nrow(duplicate_overrides) > 0) {
    stop("Transaction overrides contain duplicate natural keys.")
  }

  transactions |>
    dplyr::left_join(
      transaction_overrides,
      by = transaction_key
    ) |>
    dplyr::mutate(
      is_reimbursable = tidyr::replace_na(is_reimbursable, FALSE),
      override_applied =
        is_reimbursable | !is.na(budget_category_override),
      budget_category = dplyr::coalesce(
        budget_category_override,
        budget_category
      ),
      category_source = dplyr::if_else(
        !is.na(budget_category_override),
        "transaction_override",
        category_source
      ),
      category_rule = dplyr::if_else(
        !is.na(budget_category_override),
        "saved_category_override",
        category_rule
      )
    )
}

calculate_budget_amounts <- function(transactions) {
  transactions |>
    dplyr::mutate(
      is_budget_relevant =
        transaction_type %in% c("expense", "refund", "category_offset") &
        !is_reimbursable &
        !is.na(budget_category),
      budget_amount = dplyr::if_else(
        is_budget_relevant,
        -amount,
        0
      )
    )
}

build_monthly_rollover_ledger <- function(
  transactions,
  monthly_allocations,
  opening_balance = 0
) {
  budget_months <- tibble::tibble(
    month = seq.Date(
      from = lubridate::floor_date(min(transactions$date), unit = "month"),
      to = lubridate::floor_date(max(transactions$date), unit = "month"),
      by = "month"
    )
  )

  monthly_spending <- transactions |>
    dplyr::filter(!is.na(budget_category)) |>
    dplyr::mutate(
      month = lubridate::floor_date(date, unit = "month")
    ) |>
    dplyr::group_by(month, budget_category) |>
    dplyr::summarize(
      net_spending = sum(budget_amount),
      .groups = "drop"
    )

  tidyr::crossing(
    budget_months,
    monthly_allocations
  ) |>
    dplyr::left_join(
      monthly_spending,
      by = c("month", "budget_category")
    ) |>
    dplyr::mutate(
      net_spending = tidyr::replace_na(net_spending, 0),
      monthly_balance_change = monthly_allocation - net_spending
    ) |>
    dplyr::arrange(budget_category, month) |>
    dplyr::group_by(budget_category) |>
    dplyr::mutate(
      cumulative_rollover_balance =
        .env$opening_balance + cumsum(monthly_balance_change),
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

add_weighted_average_spending <- function(
  monthly_rollover_ledger,
  decay_factor = 0.75,
  lookback_months = 6
) {
  if (
    length(decay_factor) != 1 ||
      is.na(decay_factor) ||
      decay_factor <= 0 ||
      decay_factor > 1
  ) {
    stop("The decay factor must be greater than 0 and no greater than 1.")
  }

  if (
    length(lookback_months) != 1 ||
      is.na(lookback_months) ||
      lookback_months < 1 ||
      lookback_months != as.integer(lookback_months)
  ) {
    stop("The lookback period must be a positive whole number of months.")
  }

  monthly_rollover_ledger |>
    dplyr::arrange(budget_category, month) |>
    dplyr::group_by(budget_category) |>
    dplyr::mutate(
      months_in_weighted_average = pmin(
        dplyr::row_number() - 1L,
        .env$lookback_months
      ),
      weighted_average_spending = purrr::map_dbl(
        dplyr::row_number(),
        function(row_index) {
          history_count <- min(
            row_index - 1L,
            lookback_months
          )

          if (history_count == 0) {
            return(NA_real_)
          }

          history_start <- row_index - history_count
          historical_spending <- net_spending[
            history_start:(row_index - 1L)
          ]
          weights <- decay_factor ^ rev(
            seq.int(0, history_count - 1L)
          )

          weighted.mean(historical_spending, weights)
        }
      ),
      weighted_average_decay = .env$decay_factor,
      has_full_weighted_average =
        months_in_weighted_average == .env$lookback_months,
      weighted_average_balance_change =
        monthly_allocation - weighted_average_spending,
      projected_next_month_rollover_balance =
        cumulative_rollover_balance + weighted_average_balance_change
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(month, budget_category)
}

summarize_monthly_rollover_ledger <- function(monthly_rollover_ledger) {
  monthly_rollover_ledger |>
    dplyr::group_by(month) |>
    dplyr::summarize(
      monthly_allocation = sum(monthly_allocation),
      net_spending = sum(net_spending),
      monthly_balance_change = sum(monthly_balance_change),
      opening_balance = sum(opening_balance),
      cumulative_rollover_balance = sum(cumulative_rollover_balance),
      .groups = "drop"
    ) |>
    dplyr::arrange(month)
}
