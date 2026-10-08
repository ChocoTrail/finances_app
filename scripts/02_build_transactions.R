# Build the standardized transaction table ------------------------------

source(file.path("R", "transaction_pipeline.R"))
source(file.path("R", "budget_config.R"))

monthly_allocations <- get_monthly_allocations()

allocation_summary <- monthly_allocations |>
  dplyr::summarize(
    category_count = dplyr::n(),
    total_monthly_allocation = sum(monthly_allocation)
  )

print(allocation_summary)

account_files <- tibble::tribble(
  ~account, ~file_path,
  "checking", file.path("data", "raw", "Checking.csv"),
  "credit_card_kendra", file.path("data", "raw", "CreditCardKendra.csv"),
  "credit_card_jacob", file.path("data", "raw", "CreditCardJacob.csv")
)

transactions <- purrr::map2(
  account_files$file_path,
  account_files$account,
  read_account_export
) |>
  purrr::list_rbind()

transaction_count_by_account <- transactions |>
  dplyr::count(account, name = "transaction_count") |>
  dplyr::arrange(account)

print(transaction_count_by_account)

transactions_identified <- transactions |>
  add_transaction_identity()

transaction_identity_summary <- transactions_identified |>
  dplyr::count(
    duplicate_sequence,
    name = "transaction_count"
  ) |>
  dplyr::arrange(duplicate_sequence)

print(transaction_identity_summary)

transactions_classified <- transactions_identified |>
  classify_transaction_types()

transaction_type_summary <- transactions_classified |>
  dplyr::count(
    account,
    transaction_type,
    name = "transaction_count"
  ) |>
  dplyr::arrange(account, transaction_type)

print(transaction_type_summary)

merchant_category_rules <- get_merchant_category_rules()

transactions_categorized <- transactions_classified |>
  apply_category_rules(merchant_category_rules)

initial_category_summary <- transactions_categorized |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::count(
    budget_category,
    category_source,
    transaction_type,
    name = "transaction_count"
  ) |>
  dplyr::arrange(
    budget_category,
    category_source,
    transaction_type
  )

print(initial_category_summary)

unclassified_budget_activity <- transactions_categorized |>
  dplyr::filter(
    transaction_type %in% c("expense", "refund"),
    is.na(budget_category)
  ) |>
  dplyr::group_by(transaction_type) |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    absolute_amount = sum(abs(amount)),
    .groups = "drop"
  )

print(unclassified_budget_activity)

override_file <- file.path(
  "data",
  "private",
  "transaction_overrides.csv"
)

transaction_overrides <- read_transaction_overrides(override_file)

transactions_overridden <- transactions_categorized |>
  apply_transaction_overrides(transaction_overrides)

override_application_summary <- transactions_overridden |>
  dplyr::summarize(
    override_count = sum(override_applied),
    reimbursable_count = sum(is_reimbursable),
    category_override_count = sum(!is.na(budget_category_override))
  )

print(override_application_summary)

transactions_budgeted <- transactions_overridden |>
  calculate_budget_amounts()

analysis_month_count <- transactions_budgeted |>
  dplyr::summarize(
    month_count = dplyr::n_distinct(
      lubridate::floor_date(date, unit = "month")
    )
  ) |>
  dplyr::pull(month_count)

category_spending_summary <- transactions_budgeted |>
  dplyr::filter(!is.na(budget_category)) |>
  dplyr::group_by(budget_category) |>
  dplyr::summarize(
    net_spending = sum(budget_amount),
    average_monthly_spending = net_spending / analysis_month_count,
    .groups = "drop"
  ) |>
  dplyr::left_join(monthly_allocations, by = "budget_category") |>
  dplyr::mutate(
    average_monthly_balance_change =
      monthly_allocation - average_monthly_spending
  ) |>
  dplyr::arrange(dplyr::desc(average_monthly_spending))

print(category_spending_summary)

monthly_rollover_ledger <- build_monthly_rollover_ledger(
  transactions = transactions_budgeted,
  monthly_allocations = monthly_allocations,
  opening_balance = 0
) |>
  add_weighted_average_spending(
    decay_factor = 0.75,
    lookback_months = 6
)

print(monthly_rollover_ledger, n = Inf)

monthly_rollover_totals <- summarize_monthly_rollover_ledger(
  monthly_rollover_ledger
)

print(monthly_rollover_totals, n = Inf)

duplicate_transaction_groups <- transactions_classified |>
  find_duplicate_transaction_groups()

print(duplicate_transaction_groups, n = Inf)
