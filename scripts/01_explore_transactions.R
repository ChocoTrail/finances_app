# Explore the raw account exports -----------------------------------------

raw_data_directory <- file.path("data", "raw")

csv_files <- list.files(
  path = raw_data_directory,
  pattern = "\\.[Cc][Ss][Vv]$",
  full.names = TRUE
)

tibble::tibble(
  account_file = basename(csv_files),
  file_path = csv_files
)

# Validate the file schemas ----------------------------------------------

expected_columns <- c(
  "DATE",
  "DESCRIPTION",
  "AMOUNT",
  "CHECK #",
  "STATUS"
)

schema_check <- csv_files |>
  purrr::map(
    function(file_path) {
      actual_columns <- readr::read_csv(
        file = file_path,
        n_max = 0,
        show_col_types = FALSE
      ) |>
        names()

      tibble::tibble(
        account_file = basename(file_path),
        schema_matches = identical(actual_columns, expected_columns),
        columns_found = paste(actual_columns, collapse = ", ")
      )
    }
  ) |>
  purrr::list_rbind()

print(schema_check)

# Read the raw transactions ----------------------------------------------

account_names <- c(
  "Checking.csv" = "checking",
  "CreditCardKendra.csv" = "credit_card_kendra",
  "CreditCardJacob.csv" = "credit_card_jacob"
)

transactions_raw <- csv_files |>
  purrr::map(
    function(file_path) {
      account_file <- basename(file_path)

      readr::read_csv(
        file = file_path,
        col_types = readr::cols(.default = readr::col_character())
      ) |>
        dplyr::mutate(
          account = unname(account_names[account_file]),
          source_file = account_file,
          .before = 1
        )
    }
  ) |>
  purrr::list_rbind()

status_summary <- transactions_raw |>
  dplyr::count(account, STATUS, name = "transaction_count") |>
  dplyr::arrange(account, STATUS)

print(status_summary)

# Standardize and type the transaction fields ----------------------------

transactions_typed <- transactions_raw |>
  dplyr::filter(STATUS == "Posted") |>
  dplyr::transmute(
    account,
    source_file,
    date = readr::parse_date(DATE, format = "%m/%d/%Y"),
    description = stringr::str_squish(DESCRIPTION),
    amount = readr::parse_double(AMOUNT),
    check_number = dplyr::na_if(
      stringr::str_squish(`CHECK #`),
      ""
    )
  )

typing_check <- transactions_typed |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    missing_dates = sum(is.na(date)),
    missing_descriptions = sum(is.na(description) | description == ""),
    missing_amounts = sum(is.na(amount)),
    populated_check_numbers = sum(!is.na(check_number))
  )

print(typing_check)

# Summarize account coverage and cash flow -------------------------------

account_summary <- transactions_typed |>
  dplyr::group_by(account) |>
  dplyr::summarize(
    first_date = min(date),
    last_date = max(date),
    negative_transaction_count = sum(amount < 0),
    positive_transaction_count = sum(amount > 0),
    total_outflow = sum(-amount[amount < 0]),
    total_inflow = sum(amount[amount > 0]),
    .groups = "drop"
  )

print(account_summary)

# Review positive transactions ------------------------------------------

positive_transaction_review <- transactions_typed |>
  dplyr::filter(amount > 0) |>
  dplyr::arrange(account, date) |>
  dplyr::select(
    account,
    date,
    description
  )

print(positive_transaction_review, n = Inf)

# Review checking-account outflows --------------------------------------

checking_outflow_review <- transactions_typed |>
  dplyr::filter(
    account == "checking",
    amount < 0
  ) |>
  dplyr::arrange(amount, date) |>
  dplyr::select(
    date,
    description,
    amount,
    check_number
  )

print(checking_outflow_review, n = Inf)

# Classify transaction types --------------------------------------------

transactions_classified <- transactions_typed |>
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
        description == "ONLINE PAYMENT THANK YOU" ~ "transfer_or_card_payment",
      stringr::str_starts(account, "credit_card_") &
        amount > 0 ~ "refund",
      account == "checking" &
        amount > 0 &
        stringr::str_starts(description, "ZELLE FROM BRENT HALES") ~
        "category_offset",
      account == "checking" &
        amount > 0 &
        stringr::str_detect(description, "EXPENSE REPORT") ~ "reimbursement",
      account == "checking" & amount > 0 ~ "excluded_inflow",
      account == "checking" &
        amount < 0 &
        stringr::str_starts(description, "ZELLE TO MILLER JONATHAN") ~
        "pass_through",
      account == "checking" &
        amount < 0 &
        stringr::str_starts(description, "UTAH801/297-7703 TAX PAYMNT") ~
        "excluded_outflow",
      amount < 0 ~ "expense",
      TRUE ~ "needs_review"
    )
  )

transaction_type_summary <- transactions_classified |>
  dplyr::count(
    account,
    transaction_type,
    name = "transaction_count"
  ) |>
  dplyr::arrange(account, transaction_type)

print(transaction_type_summary)

# Review the largest expense descriptions -------------------------------

largest_expense_descriptions <- transactions_classified |>
  dplyr::filter(transaction_type == "expense") |>
  dplyr::group_by(description) |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    total_spent = sum(-amount),
    average_monthly_spend = total_spent / 6,
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(total_spent)) |>
  dplyr::slice_head(n = 40)

print(largest_expense_descriptions, n = Inf)

# Apply the first confirmed category rules -------------------------------

transactions_categorized <- transactions_classified |>
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
      stringr::str_detect(
        description,
        stringr::regex(
          paste(
            "^UNITEDWHOLESALE LOAN PAYMT",
            "^UWM ACH",
            "^BILT FOR UWM",
            "^ZELLE TO BARNEY REGISTER",
            "^QUESTARGAS",
            "^ENBRIDGE GAS",
            "^PROVO CITY UTILITIES",
            "^GFIBER",
            "^GOOGLE FIBER",
            "^ACCLAIMED HOME WARRANTY",
            sep = "|"
          ),
          ignore_case = TRUE
        )
      ) ~ "Housing & related expenses",
      stringr::str_starts(description, "GEORGE'S FRIENDLY AUTO") ~
        "Rainy day & irregular expenses",
      stringr::str_detect(
        description,
        stringr::regex(
          paste(
            "SAMSCLUB.*GAS",
            "^PILOT",
            "^ARCO",
            "^CHEVRON",
            "^LES SCHWAB",
            "^AUTOZONE",
            "^INSPECTION STATION",
            "^STINKER",
            "^GOODYEAR",
            "^MAVERIK",
            "^SHELL",
            "^SMITHS-FUEL",
            "^FRED M FUEL",
            "^PHILLIPS 66",
            "^FASTRAK",
            sep = "|"
          ),
          ignore_case = TRUE
        )
      ) ~ "Transportation",
      stringr::str_detect(
        description,
        stringr::regex(
          paste(
            "^SAMSCLUB",
            "^SAMS CLUB",
            "^TRADER JOE",
            "^WAL-MART",
            "^WM SUPERCENTER",
            "^FRED MEYER",
            "^SAFEWAY",
            "WINCO FOODS",
            "^SUPERVALU",
            "^WALGREENS",
            "^ZARA USA",
            "^USPS",
            "^SMITHS FOOD",
            "^HOLIDAY MARKET",
            "^WHOLEFDS",
            "^ALBERTSONS",
            "^KP NCAL",
            sep = "|"
          ),
          ignore_case = TRUE
        )
      ) ~ "Food & living expenses",
      stringr::str_detect(
        description,
        stringr::regex(
          paste(
            "^VENMO PAYMENT",
            "^VENMO PURCHASE",
            "^APPLE",
            "^TARGET",
            "^THE HOME DEPOT",
            "^BRITISH AWYS",
            "^SOUTHWES",
            "^DELTA",
            "^UNITED [0-9]",
            "^FRONTIER AI",
            "^ALASKA AIR",
            "^AMERICAN AIR",
            "^EDREAMS",
            "^WESTIN",
            "^FAIRFIELD INN",
            "AIRPORT PARKNG",
            "^FREENOW",
            "^HOUSE KITCHEN AND BAR",
            "^PANDA EXPRESS",
            "^CAFE RIO",
            "^SP BE ULTIMATE",
            "^USA ULTIMATE",
            "^ULTIWORLD",
            "^AUDLTV",
            "^VIVID SEATS",
            "^BARNES & NOBLE",
            "^DICKS SPORTING GOODS",
            "^PAYPAL \\*ATOLEA",
            "^CLEANINGTHEGLASS",
            "^UTAH FIRST CREDIT UNIO",
            "^STAPLES",
            "^THE RITZ-CARLTON",
            "^RED'S PIZZERIA",
            "^DD \\*DOORDASH",
            "^SACRAMENTO ZOO",
            "^TSA PRECHECK",
            "^TAKE CARE BARBERSHOP",
            "^SOAR & STEEL",
            "^TANGLE NEWS",
            "^VAULT SALON",
            "^CHEESECAKE",
            "^SLIM CHICKENS",
            "^LOS BETOS",
            "^SHERWIN-WILLIAMS",
            "^AMAZON",
            "^SAMMIES RESTAURANT",
            "^CULVERS",
            "^CHIPOTLE",
            "^PETSMART",
            "^TAVERN AT EAGLE ISLAND",
            "^TST\\* WEST COAST SOURDOUGH",
            "^RAILROAD FISH & CHIPS",
            "^H&M",
            "^UNIQLO",
            "^FOREIGN CURRENCY CONVERSION FEE",
            sep = "|"
          ),
          ignore_case = TRUE
        )
      ) ~ "Personal & discretionary",
      TRUE ~ NA_character_
    ),
    category_source = dplyr::case_when(
      account == "checking" &
        check_number %in% c("4", "5") ~ "transaction_override",
      account == "checking" &
        date == as.Date("2026-07-21") &
        stringr::str_starts(description, "ZELLE TO BARNEY REGISTER") ~
        "transaction_override",
      !is.na(budget_category) ~ "merchant_rule",
      transaction_type %in% c("expense", "refund") ~ "default",
      TRUE ~ NA_character_
    ),
    budget_category = dplyr::coalesce(
      budget_category,
      dplyr::if_else(
        transaction_type %in% c("expense", "refund"),
        "Personal & discretionary",
        NA_character_
      )
    )
  )

first_category_summary <- transactions_categorized |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::count(
    budget_category,
    transaction_type,
    name = "transaction_count"
  ) |>
  dplyr::arrange(budget_category, transaction_type)

print(first_category_summary)

category_source_summary <- transactions_categorized |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::count(
    budget_category,
    category_source,
    name = "transaction_count"
  ) |>
  dplyr::arrange(budget_category, category_source)

print(category_source_summary)

# Review transactions assigned by the fallback --------------------------

default_category_summary <- transactions_categorized |>
  dplyr::filter(category_source == "default") |>
  dplyr::group_by(transaction_type) |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    absolute_amount = sum(abs(amount)),
    .groups = "drop"
  )

largest_defaulted_descriptions <- transactions_categorized |>
  dplyr::filter(category_source == "default") |>
  dplyr::group_by(transaction_type, description) |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    absolute_amount = sum(abs(amount)),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(absolute_amount)) |>
  dplyr::slice_head(n = 40)

print(default_category_summary)
print(largest_defaulted_descriptions, n = Inf)

# Calculate net spending by category ------------------------------------

transactions_budgeted <- transactions_categorized |>
  dplyr::mutate(
    budget_amount = dplyr::case_when(
      transaction_type %in% c(
        "expense",
        "refund",
        "reimbursement",
        "category_offset"
      ) & !is.na(budget_category) ~ -amount,
      TRUE ~ 0
    )
  )

category_spending_summary <- transactions_budgeted |>
  dplyr::group_by(budget_category) |>
  dplyr::summarize(
    six_month_net_spending = sum(budget_amount),
    average_monthly_spending = six_month_net_spending / 6,
    .groups = "drop"
  ) |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::arrange(dplyr::desc(average_monthly_spending))

print(category_spending_summary)

# Compare category spending by month ------------------------------------

monthly_category_spending <- transactions_budgeted |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::mutate(month = lubridate::floor_date(date, unit = "month")) |>
  dplyr::group_by(month, budget_category) |>
  dplyr::summarize(
    net_spending = sum(budget_amount),
    .groups = "drop"
  ) |>
  tidyr::complete(
    month,
    budget_category,
    fill = list(net_spending = 0)
  ) |>
  dplyr::arrange(month, budget_category)

print(monthly_category_spending, n = Inf)

# Decompose monthly housing activity ------------------------------------

monthly_housing_components <- transactions_budgeted |>
  dplyr::filter(budget_category == "Housing & related expenses") |>
  dplyr::mutate(month = lubridate::floor_date(date, unit = "month")) |>
  dplyr::group_by(month, transaction_type) |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    budget_amount = sum(budget_amount),
    .groups = "drop"
  ) |>
  dplyr::arrange(month, transaction_type)

print(monthly_housing_components, n = Inf)

# Review airfare for reimbursable expenses -------------------------------

airfare_review <- transactions_categorized |>
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
    amount_spent
  )

print(airfare_review, n = Inf)

reimbursable_airfare_review_ids <- c(
  1,
  2, 3, 4, 5, 6, 7, 8, 9,
  10, 11,
  12, 13, 14, 15, 16,
  22, 23, 24, 25, 26
)

reimbursable_airfare_overrides <- airfare_review |>
  dplyr::filter(review_id %in% reimbursable_airfare_review_ids) |>
  dplyr::transmute(
    account,
    date,
    description,
    amount = -amount_spent,
    is_reimbursable = TRUE
  )

transactions_budgeted_adjusted <- transactions_budgeted |>
  dplyr::left_join(
    reimbursable_airfare_overrides,
    by = c("account", "date", "description", "amount")
  ) |>
  dplyr::mutate(
    is_reimbursable = tidyr::replace_na(is_reimbursable, FALSE),
    budget_amount = dplyr::if_else(
      is_reimbursable,
      0,
      budget_amount
    )
  )

adjusted_category_spending_summary <- transactions_budgeted_adjusted |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::group_by(budget_category) |>
  dplyr::summarize(
    six_month_net_spending = sum(budget_amount),
    average_monthly_spending = six_month_net_spending / 6,
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(average_monthly_spending))

print(adjusted_category_spending_summary)

# Compare the last three months with the proposed budget -----------------

monthly_allocations <- tibble::tribble(
  ~budget_category, ~monthly_allocation,
  "Housing & related expenses", 2820,
  "Transportation", 500,
  "Food & living expenses", 1230,
  "Personal & discretionary", 1100,
  "Rainy day & irregular expenses", 650
)

last_three_months <- transactions_budgeted_adjusted |>
  dplyr::filter(
    date >= as.Date("2026-07-01"),
    date < as.Date("2026-10-01"),
    !is.na(budget_category)
  ) |>
  dplyr::mutate(month = lubridate::floor_date(date, unit = "month")) |>
  dplyr::group_by(month, budget_category) |>
  dplyr::summarize(
    net_spending = sum(budget_amount),
    .groups = "drop"
  ) |>
  tidyr::complete(
    month,
    budget_category = monthly_allocations$budget_category,
    fill = list(net_spending = 0)
  ) |>
  dplyr::left_join(monthly_allocations, by = "budget_category") |>
  dplyr::mutate(
    monthly_balance_change = monthly_allocation - net_spending
  ) |>
  dplyr::arrange(budget_category, month)

last_three_month_summary <- last_three_months |>
  dplyr::group_by(budget_category) |>
  dplyr::summarize(
    three_month_allocation = sum(monthly_allocation),
    three_month_net_spending = sum(net_spending),
    three_month_balance_change = sum(monthly_balance_change),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(three_month_balance_change))

print(last_three_month_summary)

# Examine recent personal and discretionary spending --------------------

personal_spending_by_month <- transactions_budgeted_adjusted |>
  dplyr::filter(
    date >= as.Date("2026-07-01"),
    date < as.Date("2026-10-01"),
    budget_category == "Personal & discretionary"
  ) |>
  dplyr::mutate(month = lubridate::floor_date(date, unit = "month")) |>
  dplyr::group_by(month, budget_category) |>
  dplyr::summarize(
    net_spending = sum(budget_amount),
    .groups = "drop"
  ) |>
  dplyr::left_join(monthly_allocations, by = "budget_category") |>
  dplyr::mutate(
    monthly_balance_change = monthly_allocation - net_spending
  ) |>
  dplyr::select(
    month,
    net_spending,
    monthly_allocation,
    monthly_balance_change
  )

largest_personal_expenses_last_three_months <-
  transactions_budgeted_adjusted |>
  dplyr::filter(
    date >= as.Date("2026-07-01"),
    date < as.Date("2026-10-01"),
    budget_category == "Personal & discretionary",
    budget_amount > 0
  ) |>
  dplyr::group_by(description) |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    total_spent = sum(budget_amount),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(total_spent)) |>
  dplyr::slice_head(n = 40)

print(personal_spending_by_month)
print(largest_personal_expenses_last_three_months, n = Inf)
