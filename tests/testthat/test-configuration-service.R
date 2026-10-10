configuration_test_allocations <- function(amounts = c(2820, 500, 1230, 1100, 650)) {
  purrr::map2(finance_category_codes, amounts, ~ list(category_code = .x, amount = .y))
}

test_that("configuration contract exposes merchants and rollover settings", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  contract <- build_configuration_screen_contract(connection, as.Date("2026-05-15"))

  expect_equal(contract$status, "ready")
  expect_equal(contract$current_month, "2026-05-01")
  expect_equal(contract$default_effective_month, "2026-06-01")
  expect_length(contract$categories, 5)
  expect_length(contract$merchants, 21)
  expect_equal(
    purrr::map_chr(contract$merchants, "display_name"),
    sort(purrr::map_chr(contract$merchants, "display_name"), method = "radix")
  )
  expect_equal(
    purrr::map_chr(contract$merchant_defaults, "display_name"),
    c("HOUSING PAYMENT", "TARGET RETURN", "TARGET STORE")
  )
  expect_true("HOUSING PAYMENT" %in% purrr::map_chr(contract$new_merchants, "display_name"))
  expect_length(contract$budget_versions, 1)
  expect_equal(contract$budget_setup$budget_start_month, "2026-04-01")
})

test_that("simple merchant defaults preserve history and allow only everyday categories", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  result <- save_configuration_change(connection, list(
    kind = "merchant_default",
    request_id = "merchant-simple-001",
    merchant_description = "TARGET STORE",
    category_code = "transportation"
  ), today = as.Date("2026-05-15"))
  existing <- DBI::dbGetQuery(connection, paste(
    "SELECT d.category_code FROM transaction_decisions d",
    "JOIN transactions t USING (transaction_id)",
    "WHERE t.standardized_description = 'TARGET STORE'"
  ))
  saved_rule <- DBI::dbGetQuery(
    connection,
    "SELECT default_category_code, priority FROM merchant_rules WHERE rule_id = ?",
    params = list(result$rule_id)
  )
  broad_rule <- DBI::dbGetQuery(
    connection,
    "SELECT default_category_code, priority FROM merchant_rules WHERE rule_id = 'variable_retailers'"
  )
  refreshed <- build_configuration_screen_contract(connection, as.Date("2026-05-15"))
  target_default <- purrr::keep(
    refreshed$merchant_defaults,
    ~ identical(.x$display_name, "TARGET STORE")
  )[[1]]

  expect_equal(result$status, "saved")
  expect_equal(saved_rule$default_category_code[[1]], "transportation")
  expect_lt(saved_rule$priority[[1]], broad_rule$priority[[1]])
  expect_equal(broad_rule$default_category_code[[1]], "personal_discretionary")
  expect_equal(target_default$category_code, "transportation")
  expect_equal(existing$category_code[[1]], "personal_discretionary")
  expect_error(save_configuration_change(connection, list(
    kind = "merchant_default",
    request_id = "merchant-simple-002",
    merchant_description = "TARGET STORE",
    category_code = "rainy_day"
  )), "Food & living, Personal, Transportation, or Housing")
})

test_that("simple merchant defaults allow housing", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  result <- save_configuration_change(connection, list(
    kind = "merchant_default",
    request_id = "merchant-simple-housing-001",
    merchant_description = "NEW MERCHANT",
    category_code = "housing"
  ), today = as.Date("2026-05-15"))
  rule <- DBI::dbGetQuery(
    connection,
    "SELECT default_category_code FROM merchant_rules WHERE rule_id = ?",
    params = list(result$rule_id)
  )

  expect_equal(rule$default_category_code[[1]], "housing")
})

test_that("new merchant defaults create an exact future-only match", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  result <- save_configuration_change(connection, list(
    kind = "merchant_default",
    request_id = "merchant-simple-new-001",
    merchant_description = "NEW MERCHANT",
    category_code = "food_living"
  ), today = as.Date("2026-05-15"))
  rule <- DBI::dbGetQuery(
    connection,
    "SELECT description_pattern, default_category_code FROM merchant_rules WHERE rule_id = ?",
    params = list(result$rule_id)
  )

  expect_true(stringr::str_detect("NEW MERCHANT", stringr::regex(rule$description_pattern[[1]], ignore_case = TRUE)))
  expect_false(stringr::str_detect("NEW MERCHANT EXTRA", stringr::regex(rule$description_pattern[[1]], ignore_case = TRUE)))
  expect_equal(rule$default_category_code[[1]], "food_living")
  expect_equal(result$matched_transaction_count, 0)
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

test_that("rollover start changes without rewriting stored opening balances", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  configured_balances <- c(100, 20, 30, -10, 50)

  purrr::walk2(
    finance_category_codes,
    configured_balances,
    function(category_code, amount) {
      DBI::dbExecute(
        connection,
        paste(
          "UPDATE budget_opening_balances SET opening_balance = ?",
          "WHERE category_code = ?"
        ),
        params = list(amount, category_code)
      )
    }
  )

  request <- list(
    kind = "rollover_start",
    request_id = "rollover-save-001",
    budget_start_month = "2026-05-01"
  )

  first <- save_configuration_change(connection, request, today = as.Date("2026-05-15"))
  second <- save_configuration_change(connection, request, today = as.Date("2026-05-15"))
  openings <- read_database_opening_balances(connection)
  ledger <- build_database_rollover_ledger(connection, through_month = as.Date("2026-05-01"))

  expect_equal(first$status, "saved")
  expect_equal(second$status, "already_saved")
  expect_equal(unique(openings$budget_start_month), as.Date("2026-05-01"))
  expect_equal(openings$configured_opening_balance, configured_balances)
  housing <- dplyr::filter(ledger, budget_category == "Housing & related expenses")
  expect_equal(housing$opening_balance[[1]], 100)
})
