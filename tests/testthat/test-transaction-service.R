test_that("transaction screen combines text and structured filters", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  screen <- build_transaction_screen_contract(
    connection,
    filters = list(
      start_date = "2026-04-01",
      end_date = "2026-04-30",
      search = "target",
      account = "credit_card_jacob",
      category = "personal_discretionary"
    ),
    today = as.Date("2026-05-15")
  )

  expect_equal(screen$total_count, 1L)
  expect_equal(screen$transactions[[1]]$description, "TARGET STORE")
  expect_equal(screen$transactions[[1]]$account, "credit_card_jacob")
  expect_equal(screen$filters$category, "personal_discretionary")
})

test_that("review queue contains only pending saved decisions", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  screen <- build_transaction_screen_contract(
    connection,
    filters = list(
      start_date = NULL,
      end_date = NULL,
      review_state = "pending"
    ),
    today = as.Date("2026-05-15")
  )

  expect_equal(screen$pending_review_count, 1L)
  expect_equal(screen$total_count, 1L)
  expect_equal(screen$transactions[[1]]$description, "NEW MERCHANT")
  expect_equal(screen$transactions[[1]]$review_state, "pending")
})

test_that("merchant and budget-treatment filters use saved classifications", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  merchant_screen <- build_transaction_screen_contract(
    connection,
    filters = list(
      start_date = NULL,
      end_date = NULL,
      merchant = "variable_retailers"
    ),
    today = as.Date("2026-05-15")
  )
  refund_screen <- build_transaction_screen_contract(
    connection,
    filters = list(
      start_date = NULL,
      end_date = NULL,
      treatment = "refund"
    ),
    today = as.Date("2026-05-15")
  )

  expect_equal(merchant_screen$total_count, 2L)
  expect_equal(refund_screen$total_count, 1L)
  expect_equal(refund_screen$transactions[[1]]$description, "TARGET RETURN")
})

test_that("transaction decision save is atomic and audited", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  transaction_id <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT transaction_id FROM transactions",
      "WHERE standardized_description = 'NEW MERCHANT'"
    )
  )$transaction_id[[1]]
  audit_count_before <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM decision_audit_log"
  )$n[[1]]
  request <- list(
    request_id = "request-save-new-merchant",
    transaction_id = transaction_id,
    category_code = "food_living",
    is_reimbursable = TRUE,
    is_excluded = FALSE,
    note = "Work meal awaiting reimbursement"
  )

  result <- save_transaction_decision(
    connection,
    request,
    changed_at = as.POSIXct("2026-05-07 12:00:00", tz = "UTC")
  )
  saved <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT d.*, c.display_name AS category",
      "FROM transaction_decisions d",
      "JOIN categories c USING (category_code)",
      "WHERE transaction_id = ?"
    ),
    params = list(transaction_id)
  )
  audit_count_after <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM decision_audit_log"
  )$n[[1]]

  expect_equal(result$status, "saved")
  expect_equal(saved$category[[1]], "Food & living expenses")
  expect_equal(saved$assignment_source[[1]], "transaction_override")
  expect_equal(saved$review_state[[1]], "confirmed")
  expect_true(saved$is_reimbursable[[1]])
  expect_equal(saved$note[[1]], "Work meal awaiting reimbursement")
  expect_equal(audit_count_after, audit_count_before + 1)

  refreshed <- build_transaction_screen_contract(
    connection,
    filters = list(start_date = NULL, end_date = NULL, search = "new merchant"),
    today = as.Date("2026-05-15")
  )
  expect_equal(refreshed$transactions[[1]]$budget_effect, 0)
  expect_equal(refreshed$transactions[[1]]$display_treatment, "reimbursable")
})

test_that("repeated decision request is idempotent", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  transaction_id <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT transaction_id FROM transactions",
      "WHERE standardized_description = 'NEW MERCHANT'"
    )
  )$transaction_id[[1]]
  request <- list(
    request_id = "request-idempotent-save",
    transaction_id = transaction_id,
    category_code = "food_living",
    is_reimbursable = FALSE,
    is_excluded = FALSE,
    note = NULL
  )

  first <- save_transaction_decision(connection, request)
  second <- save_transaction_decision(connection, request)
  audit_count <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT count(*) AS n FROM decision_audit_log",
      "WHERE action = 'transaction_decision_update'"
    )
  )$n[[1]]

  expect_equal(first$status, "saved")
  expect_equal(second$status, "already_saved")
  expect_equal(audit_count, 1)
})

test_that("invalid decision save leaves decision and audit unchanged", {
  connection <- transaction_maintenance_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  transaction_id <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT transaction_id FROM transactions",
      "WHERE standardized_description = 'NEW MERCHANT'"
    )
  )$transaction_id[[1]]
  before <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM transaction_decisions WHERE transaction_id = ?",
    params = list(transaction_id)
  )
  audit_count_before <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM decision_audit_log"
  )$n[[1]]

  expect_error(
    save_transaction_decision(
      connection,
      list(
        request_id = "request-invalid-category",
        transaction_id = transaction_id,
        category_code = "not_a_category",
        is_reimbursable = FALSE,
        is_excluded = FALSE,
        note = NULL
      )
    ),
    "category"
  )

  after <- DBI::dbGetQuery(
    connection,
    "SELECT * FROM transaction_decisions WHERE transaction_id = ?",
    params = list(transaction_id)
  )
  audit_count_after <- DBI::dbGetQuery(
    connection,
    "SELECT count(*) AS n FROM decision_audit_log"
  )$n[[1]]

  expect_equal(after, before)
  expect_equal(audit_count_after, audit_count_before)
})
