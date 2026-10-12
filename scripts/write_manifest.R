#!/usr/bin/env Rscript

runtime_files <- c(
  "app.R",
  file.path(
    "R",
    c(
      "app_server.R",
      "budget_config.R",
      "config.R",
      "configuration_service.R",
      "database.R",
      "database_queries.R",
      "import_service.R",
      "overview_service.R",
      "prototype_contracts.R",
      "transaction_pipeline.R",
      "transaction_service.R"
    )
  ),
  file.path(
    "migrations",
    c(
      "001_initial_schema.sql",
      "002_transaction_sightings.sql",
      "003_budget_effective_date.sql"
    )
  ),
  file.path("www", c("ui.css", "ui.js")),
  file.path(
    "www",
    "brand",
    c(
      "fonts/AzeretMono-Variable.ttf",
      "fonts/OFL-AzeretMono.txt",
      "fonts/OFL-Recursive.txt",
      "fonts/Recursive-Variable.ttf"
    )
  )
)

missing_files <- runtime_files[!file.exists(runtime_files)]

if (length(missing_files) > 0L) {
  stop(
    "Cannot write manifest; missing runtime files: ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

rv_status <- system2(
  "rv",
  c("export", "renv", "--output", "renv.lock")
)

if (!identical(rv_status, 0L)) {
  stop("Cannot write manifest; rv lockfile export failed.", call. = FALSE)
}

rsconnect::writeManifest(
  appDir = ".",
  appFiles = runtime_files,
  appPrimaryDoc = "app.R",
  appMode = "shiny",
  dependencyResolution = "strict"
)

lockfile <- jsonlite::read_json("renv.lock", simplifyVector = FALSE)
manifest <- jsonlite::read_json("manifest.json", simplifyVector = FALSE)
git_packages <- names(Filter(
  function(package) identical(package$Source, "GitHub"),
  lockfile$Packages
))

for (package_name in git_packages) {
  locked_package <- lockfile$Packages[[package_name]]
  manifest_package <- manifest$packages[[package_name]]

  if (is.null(manifest_package)) {
    stop(
      "Cannot write manifest; missing Git package: ",
      package_name,
      call. = FALSE
    )
  }

  remote_metadata <- list(
    RemoteType = locked_package$RemoteType,
    RemoteHost = locked_package$RemoteHost,
    RemoteRepo = locked_package$RemoteRepo,
    RemoteUsername = locked_package$RemoteUsername,
    RemotePkgRef = paste0(
      locked_package$RemoteUsername,
      "/",
      locked_package$RemoteRepo
    ),
    RemoteRef = locked_package$RemoteSha,
    RemoteSha = locked_package$RemoteSha,
    RemoteSubdir = locked_package$RemoteSubdir,
    GithubRepo = locked_package$RemoteRepo,
    GithubUsername = locked_package$RemoteUsername,
    GithubRef = locked_package$RemoteSha,
    GithubSHA1 = locked_package$RemoteSha,
    GithubSubdir = locked_package$RemoteSubdir
  )
  remote_metadata <- remote_metadata[
    !vapply(remote_metadata, is.null, logical(1))
  ]

  for (field_name in names(remote_metadata)) {
    manifest$packages[[package_name]]$description[[field_name]] <-
      remote_metadata[[field_name]]
  }
}

jsonlite::write_json(
  manifest,
  "manifest.json",
  auto_unbox = TRUE,
  null = "null",
  pretty = TRUE
)
