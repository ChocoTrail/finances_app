create_finance_app_server <- function(
  connection_factory = function() connect_app_finance_database()
) {
  force(connection_factory)

  function(input, output, session) {
    connection <- connection_factory()
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
      build_overview_screen_contract(
        connection = connection,
        selected_month = input$overview_month,
        selected_category = input$overview_category
      )
    })

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
