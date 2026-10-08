override_file <- file.path(
  "data",
  "private",
  "transaction_overrides.csv"
)

if (file.exists(override_file)) {
  stop(
    "The override file already exists and was not changed: ",
    override_file
  )
}

# Save the initial private transaction overrides -------------------------

source(file.path("scripts", "02_build_transactions.R"))

airfare_review <- transactions_categorized |>
  build_airfare_review()

reimbursable_airfare_review_ids <- c(
  1:16,
  22:26
)

reimbursable_override_candidates <- airfare_review |>
  dplyr::filter(review_id %in% reimbursable_airfare_review_ids) |>
  dplyr::mutate(is_reimbursable = TRUE)

transaction_overrides <- reimbursable_override_candidates |>
  dplyr::transmute(
    account,
    date,
    description,
    amount,
    check_number,
    duplicate_sequence,
    is_reimbursable,
    budget_category_override = NA_character_,
    override_note = "Initial reimbursable airfare review"
  )

dir.create(
  path = dirname(override_file),
  recursive = TRUE,
  showWarnings = FALSE
)

readr::write_csv(
  transaction_overrides,
  file = override_file,
  na = ""
)

saved_override_summary <- transaction_overrides |>
  dplyr::summarize(
    transaction_count = dplyr::n(),
    reimbursable_count = sum(is_reimbursable),
    category_override_count = sum(!is.na(budget_category_override))
  )

print(saved_override_summary)
