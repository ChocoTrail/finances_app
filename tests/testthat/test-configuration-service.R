configuration_test_allocations <- function(amounts = c(2820, 500, 1230, 1100, 650)) {
  purrr::map2(finance_category_codes, amounts, ~ list(category_code = .x, amount = .y))
}

test_that("configuration contract exposes merchants and versioned budget setup", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  contract <- build_configuration_screen_contract(connection, as.Date("2026-05-15"))

  expect_equal(contract$status, "ready")
  expect_equal(contract$current_month, "2026-05-01")
  expect_equal(contract$default_effective_month, "2026-06-01")
  expect_length(contract$categories, 5)
  expect_length(contract$merchants, 21)
  expect_length(contract$budget_versions, 1)
  expect_length(contract$budget_setup$opening_balances, 5)
})

test_that("merchant saves are prospective by default and idempotent", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  request <- list(
    kind = "merchant",
    request_id = "merchant-create-001",
    rule_id = NULL,
    display_name = "New merchant",
    description_pattern = "^NEW MERCHANT$",
    category_code = "food_living",
    effective_date = "2026-05-01",
    is_active = TRUE,
    apply_existing = FALSE
  )

  first <- save_configuration_change(connection, request)
  second <- save_configuration_change(connection, request)
  existing <- DBI::dbGetQuery(connection, paste(
    "SELECT category_code, assignment_source FROM transaction_decisions d",
    "JOIN transactions t USING (transaction_id)",
    "WHERE t.standardized_description = 'NEW MERCHANT'"
  ))
  audit_count <- DBI::dbGetQuery(connection, paste(
    "SELECT count(*) AS n FROM decision_audit_log",
    "WHERE action = 'merchant_rule_create'"
  ))$n[[1]]

  expect_equal(first$status, "saved")
  expect_equal(first$matched_transaction_count, 0)
  expect_equal(second$status, "already_saved")
  expect_equal(existing$assignment_source[[1]], "default")
  expect_equal(audit_count, 1)
})

test_that("merchant rules can deliberately update existing matches atomically", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  request <- list(
    kind = "merchant",
    request_id = "merchant-apply-001",
    rule_id = NULL,
    display_name = "New merchant",
    description_pattern = "^NEW MERCHANT$",
    category_code = "food_living",
    effective_date = "2026-05-01",
    is_active = TRUE,
    apply_existing = TRUE
  )

  result <- save_configuration_change(connection, request)
  saved <- DBI::dbGetQuery(connection, paste(
    "SELECT category_code, assignment_source, assignment_rule, review_state",
    "FROM transaction_decisions d JOIN transactions t USING (transaction_id)",
    "WHERE t.standardized_description = 'NEW MERCHANT'"
  ))
  applied_audits <- DBI::dbGetQuery(connection, paste(
    "SELECT count(*) AS n FROM decision_audit_log",
    "WHERE action = 'merchant_rule_apply_existing'"
  ))$n[[1]]

  expect_equal(result$matched_transaction_count, 1)
  expect_equal(saved$category_code[[1]], "food_living")
  expect_equal(saved$assignment_source[[1]], "merchant_rule")
  expect_equal(saved$assignment_rule[[1]], result$rule_id)
  expect_equal(saved$review_state[[1]], "confirmed")
  expect_equal(applied_audits, 1)
})

test_that("invalid merchant save leaves rules and audits unchanged", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  counts_before <- DBI::dbGetQuery(connection, paste(
    "SELECT (SELECT count(*) FROM merchant_rules) AS merchants,",
    "(SELECT count(*) FROM decision_audit_log) AS audits"
  ))

  expect_error(save_configuration_change(connection, list(
    kind = "merchant", request_id = "merchant-invalid-001", rule_id = NULL,
    display_name = "Broken", description_pattern = "[", category_code = "food_living",
    effective_date = "2026-05-01", is_active = TRUE, apply_existing = FALSE
  )), "regular expression")

  counts_after <- DBI::dbGetQuery(connection, paste(
    "SELECT (SELECT count(*) FROM merchant_rules) AS merchants,",
    "(SELECT count(*) FROM decision_audit_log) AS audits"
  ))
  expect_equal(counts_after, counts_before)
})

test_that("budget changes create a new effective version without rewriting history", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  request <- list(
    kind = "budget_version",
    request_id = "budget-version-001",
    effective_month = "2026-06-01",
    total_monthly_budget = 6300,
    allocations = configuration_test_allocations(c(2800, 500, 1300, 1100, 600))
  )

  first <- save_configuration_change(connection, request, today = as.Date("2026-05-15"))
  second <- save_configuration_change(connection, request, today = as.Date("2026-05-15"))
  versions <- read_database_budget_versions(connection)

  expect_equal(first$status, "saved")
  expect_equal(second$status, "already_saved")
  expect_equal(sort(unique(as.character(versions$effective_month))), c("2026-04-01", "2026-06-01"))
  expect_equal(sum(versions$monthly_allocation[versions$effective_month == as.Date("2026-06-01")]), 6300)
  expect_equal(sum(versions$monthly_allocation[versions$effective_month == as.Date("2026-04-01")]), 6300)
})

test_that("budget allocation mismatch rolls back completely", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  before <- DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM budget_versions")$n[[1]]

  expect_error(save_configuration_change(connection, list(
    kind = "budget_version", request_id = "budget-invalid-001",
    effective_month = "2026-06-01", total_monthly_budget = 6200,
    allocations = configuration_test_allocations()
  ), today = as.Date("2026-05-15")), "sum exactly")

  after <- DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM budget_versions")$n[[1]]
  expect_equal(after, before)
})

test_that("budget start and opening balances save together and affect rollover", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  request <- list(
    kind = "opening_balances",
    request_id = "opening-save-001",
    budget_start_month = "2026-04-01",
    opening_balances = configuration_test_allocations(c(100, 20, 30, -10, 50))
  )

  first <- save_configuration_change(connection, request, today = as.Date("2026-05-15"))
  second <- save_configuration_change(connection, request, today = as.Date("2026-05-15"))
  openings <- read_database_opening_balances(connection)
  ledger <- build_database_rollover_ledger(connection, through_month = as.Date("2026-04-01"))

  expect_equal(first$status, "saved")
  expect_equal(second$status, "already_saved")
  expect_equal(openings$configured_opening_balance, c(100, 20, 30, -10, 50))
  housing <- dplyr::filter(ledger, budget_category == "Housing & related expenses")
  expect_equal(housing$opening_balance[[1]], 100)
})
