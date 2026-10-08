test_that("overview defaults to the current month within budget bounds", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  overview <- build_overview_screen_contract(
    connection,
    today = as.Date("2026-05-15")
  )

  expect_equal(overview$selected_month, "2026-05-01")
  expect_equal(overview$month_label, "May 2026")
  expect_equal(overview$previous_month, "2026-04-01")
  expect_null(overview$next_month)
  expect_length(overview$categories, 5)
})

test_that("overview cards preserve independent rollover calculations", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  overview <- build_overview_screen_contract(
    connection,
    selected_month = "2026-05-01",
    today = as.Date("2026-05-15")
  )
  personal <- overview$categories[[4]]

  expect_equal(personal$category_code, "personal_discretionary")
  expect_equal(personal$monthly_allocation, 1100)
  expect_equal(personal$net_spending, -10)
  expect_equal(personal$available_balance, 2185)
  expect_equal(personal$balance_state, "available")
})

test_that("negative rollover is explicitly identified as a deficit", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE budget_opening_balances",
      "SET opening_balance = -3000",
      "WHERE category_code = 'housing'"
    )
  )

  overview <- build_overview_screen_contract(
    connection,
    selected_month = "2026-04-01",
    today = as.Date("2026-05-15")
  )
  housing <- overview$categories[[1]]

  expect_equal(housing$available_balance, -1180)
  expect_equal(housing$balance_state, "deficit")
})

test_that("account freshness includes every supported account", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  overview <- build_overview_screen_contract(
    connection,
    selected_month = "2026-05-01",
    today = as.Date("2026-05-15")
  )

  expect_equal(
    vapply(overview$accounts, `[[`, character(1), "account"),
    c("checking", "credit_card_jacob", "credit_card_kendra")
  )
  expect_equal(
    vapply(overview$accounts, `[[`, character(1), "data_through"),
    c("2026-04-05", "2026-04-10", "2026-05-03")
  )
})

test_that("category selection returns only that month and category", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  overview <- build_overview_screen_contract(
    connection,
    selected_month = "2026-05-01",
    selected_category = "personal_discretionary",
    today = as.Date("2026-05-15")
  )

  expect_equal(overview$selected_category$category_code, "personal_discretionary")
  expect_length(overview$transactions, 1)
  expect_equal(overview$transactions[[1]]$description, "TARGET RETURN")
  expect_equal(overview$transactions[[1]]$budget_treatment, "refund")
  expect_equal(overview$transactions[[1]]$budget_effect, -10)
})

test_that("overview rejects months outside the supported range", {
  connection <- overview_connection_factory()
  on.exit(disconnect_finance_database(connection), add = TRUE)

  expect_error(
    build_overview_screen_contract(
      connection,
      selected_month = "2026-03-01",
      today = as.Date("2026-05-15")
    ),
    "budget start"
  )
  expect_error(
    build_overview_screen_contract(
      connection,
      selected_month = "2026-06-01",
      today = as.Date("2026-05-15")
    ),
    "future"
  )
})
