create_finance_app_server <- function(
  connection_factory = function() connect_app_finance_database()
) {
  force(connection_factory)

  function(input, output, session) {
    connection <- connection_factory()
    data_revision <- shiny::reactiveVal(0L)
    transaction_save_result <- shiny::reactiveVal(list(status = "idle"))
    configuration_save_result <- shiny::reactiveVal(list(status = "idle"))
    session$onSessionEnded(function() {
      disconnect_finance_database(connection)
    })

    output$upload_widget <- shiny::renderUI({
      shiny::fileInput(
        inputId = "account_file",
        label = "Account export",
        multiple = FALSE,
        accept = c(".csv", "text/csv"),
        buttonLabel = "Choose CSV",
        placeholder = "No file selected"
      )
    })
    shiny::outputOptions(
      output,
      "upload_widget",
      suspendWhenHidden = FALSE
    )

    output$prototype_echo <- shinyreact::reactive_output({
      message <- input$prototype_message

      if (is.null(message)) {
        return(NULL)
      }

      format_prototype_echo(message)
    })

    output$overview_screen <- shinyreact::reactive_output({
      data_revision()
      build_overview_screen_contract(
        connection = connection,
        selected_month = input$overview_month,
        selected_category = input$overview_category
      )
    })

    output$transaction_screen <- shinyreact::reactive_output({
      data_revision()
      build_transaction_screen_contract(
        connection = connection,
        filters = input$transaction_filters
      )
    })

    output$transaction_save_result <- shinyreact::reactive_output({
      transaction_save_result()
    })

    output$configuration_screen <- shinyreact::reactive_output({
      data_revision()
      build_configuration_screen_contract(connection)
    })

    output$configuration_save_result <- shinyreact::reactive_output({
      configuration_save_result()
    })

    shiny::observeEvent(
      input$transaction_save_request,
      {
        request <- input$transaction_save_request
        request_id <- if (
          is.list(request) && "request_id" %in% names(request)
        ) {
          as.character(request$request_id)
        } else {
          NULL
        }

        result <- tryCatch(
          {
            saved <- save_transaction_decision(connection, request)

            if (saved$status == "saved") {
              data_revision(data_revision() + 1L)
            }

            saved
          },
          error = function(error) {
            list(
              status = "error",
              request_id = request_id,
              message = conditionMessage(error)
            )
          }
        )

        transaction_save_result(result)
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$configuration_save_request,
      {
        request <- input$configuration_save_request
        request_id <- if (is.list(request) && "request_id" %in% names(request)) {
          as.character(request$request_id)
        } else {
          NULL
        }

        result <- tryCatch(
          {
            saved <- save_configuration_change(connection, request)
            if (saved$status == "saved") data_revision(data_revision() + 1L)
            saved
          },
          error = function(error) {
            list(status = "error", request_id = request_id, message = conditionMessage(error))
          }
        )
        configuration_save_result(result)
      },
      ignoreInit = TRUE
    )

    output$import_preview <- shinyreact::reactive_output({
      upload <- input$account_file
      account <- input$account_slot

      if (is.null(upload) || is.null(account)) {
        return(empty_import_preview_contract())
      }

      tryCatch(
        {
          preview <- preview_transaction_import(
            connection = connection,
            file_path = upload$datapath[[1]],
            account = account,
            source_filename = upload$name[[1]]
          )
          format_import_preview_contract(preview)
        },
        error = function(error) {
          format_import_preview_error(conditionMessage(error))
        }
      )
    })
  }
}
