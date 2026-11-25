# What the modules tell the browser when the dataset changes (T-08; audit M-6,
# M-7, M-8, M-10, L-7, L-8). Leaflet proxy calls are captured by replacing
# leaflet's internal sender, so no browser is needed.
use_app_root()

# Record every leafletProxy() call made while the calling test runs.
record_leaflet_calls <- function(env = parent.frame()) {
  rec <- new.env()
  rec$log <- list()
  testthat::local_mocked_bindings(
    invokeRemote = function(map, method, args = list()) {
      rec$log[[length(rec$log) + 1]] <- list(method = method, args = args)
      map
    },
    .package = "leaflet", .env = env
  )
  rec$methods <- function() vapply(rec$log, function(x) x$method, character(1))
  rec$reset <- function() rec$log <- list()
  rec$with <- function(method) Filter(function(x) identical(x$method, method), rec$log)
  rec
}

test_that("the data map zooms when records arrive and keeps the view on delete (M-6)", {
  calls <- record_leaflet_calls()
  d <- load_fixture_dataset("upload_sample.csv")
  analysis_data <- reactiveVal(data.frame()); selected_points <- reactiveVal(numeric(0))
  testServer(mapModuleServer, args = list(analysis_data = analysis_data, selected_points = selected_points), {
    analysis_data(d); session$flushReact()
    expect_length(calls$with("fitBounds"), 1)                  # one fit, with padding and a zoom cap
    expect_equal(calls$with("fitBounds")[[1]]$args[[5]]$maxZoom, 10)

    calls$reset()
    analysis_data(d[-1, ] |> dplyr::mutate(index = dplyr::row_number())); session$flushReact()
    expect_true("addCircleMarkers" %in% calls$methods())       # points redrawn
    expect_length(calls$with("fitBounds"), 0)                  # view untouched
  })
})

test_that("the record counter is removed when the dataset becomes empty (L-7)", {
  calls <- record_leaflet_calls()
  d <- load_fixture_dataset("Magnolia_acuminata_data_small.csv")
  analysis_data <- reactiveVal(data.frame()); selected_points <- reactiveVal(numeric(0))
  testServer(mapModuleServer, args = list(analysis_data = analysis_data, selected_points = selected_points), {
    analysis_data(d); session$flushReact()
    expect_length(calls$with("addControl"), 1)
    calls$reset()
    analysis_data(d[0, ]); session$flushReact()
    removed <- calls$with("removeControl")
    expect_true(any(vapply(removed, function(x) identical(x$args[[1]], "gbif_upload_counts"), logical(1))))
    expect_length(calls$with("addControl"), 0)
  })
})

test_that("the gap map drops its record markers when the dataset empties (M-10)", {
  calls <- record_leaflet_calls()
  d <- load_fixture_dataset("Magnolia_acuminata_data_small.csv")
  analysis_data <- reactiveVal(d)
  cleared <- function() unlist(lapply(calls$with("clearGroup"), function(x) x$args[[1]]))
  testServer(gapAnalysisServer, args = list(analysis_data = analysis_data), {
    session$setInputs(gap_map_zoom = 4, buffer_dist = "50", model_method = "buffer")
    session$flushReact()
    expect_true("addCircleMarkers" %in% calls$methods())

    calls$reset()
    analysis_data(d[0, ]); session$flushReact()
    expect_true(all(c("Reference Records", "Germplasm Records") %in% cleared()))
    expect_false("addCircleMarkers" %in% calls$methods())

    # same when rows remain but none has coordinates
    analysis_data(d); session$flushReact()
    calls$reset()
    no_coords <- d; no_coords$Latitude <- NA_real_
    analysis_data(no_coords); session$flushReact()
    expect_true(all(c("Reference Records", "Germplasm Records") %in% cleared()))
    expect_false("addCircleMarkers" %in% calls$methods())

    # Run with nothing to analyse does not error and leaves no result
    analysis_data(d[0, ]); session$flushReact()
    session$setInputs(generate_buffers = 1)
    expect_null(gap_result())
  })
})

test_that("banner and footer icons use the icon font the app loads (L-8)", {
  banner <- as.character(app_banner_ui(list(show = TRUE, text = "Beta", contact_label = "Questions?")))
  footer <- as.character(footer_ui())
  for (html in list(banner, footer)) {
    expect_false(grepl('class="bi ', html, fixed = TRUE))      # Bootstrap Icons are not shipped
    expect_true(grepl("fa-", html, fixed = TRUE))              # Font Awesome is (shiny::icon)
  }
  deps <- vapply(htmltools::findDependencies(footer_ui()), function(d) d$name, character(1))
  expect_true("font-awesome" %in% deps)
})
