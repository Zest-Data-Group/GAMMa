# Server-side behaviour of the data-analysis module (Delete / Undo) via
# shiny::testServer. Seams: the `analysis_data` and `selected_points`
# reactiveVals passed in, and the module's `undo_available()` reactive.
#
# Every test starts with session$flushReact(): the DT table module's
# table-to-map sync observer fires once on the first flush with an empty table
# selection and resets selected_points(), exactly as it does at app start-up.
# Selecting before that flush would be undone before Delete ever ran.
use_app_root()

test_that("undo is unavailable once the dataset is no longer the one the delete produced (C-3)", {
  analysis_data <- reactiveVal(load_fixture_dataset("Magnolia_acuminata_data_small.csv"))
  selected_points <- reactiveVal(numeric(0))
  testServer(dataAnalysisServer, args = list(analysis_data = analysis_data, selected_points = selected_points), {
    session$flushReact()
    expect_equal(nrow(analysis_data()), 8)
    selected_points(c(1, 2))
    session$setInputs(deleteSelection = 1)
    expect_equal(nrow(analysis_data()), 6)
    expect_true(undo_available())

    # a GBIF gather / upload replaces the working dataset
    analysis_data(load_fixture_dataset("Magnolia_acuminata_data.csv"))
    session$flushReact()
    expect_false(undo_available())
    session$setInputs(undoLastDelete = 1)
    expect_equal(nrow(analysis_data()), 200)
  })
})

test_that("a Delete with nothing selected does not overwrite the real backup", {
  analysis_data <- reactiveVal(load_fixture_dataset("Magnolia_acuminata_data_small.csv"))
  selected_points <- reactiveVal(numeric(0))
  testServer(dataAnalysisServer, args = list(analysis_data = analysis_data, selected_points = selected_points), {
    session$flushReact()
    selected_points(c(1, 2))
    session$setInputs(deleteSelection = 1)
    expect_equal(nrow(analysis_data()), 6)

    selected_points(numeric(0))
    session$setInputs(deleteSelection = 2)   # "No records selected" warning, no change
    expect_equal(nrow(analysis_data()), 6)

    session$setInputs(undoLastDelete = 1)
    expect_equal(nrow(analysis_data()), 8)
    expect_equal(analysis_data()$index, 1:8)
  })
})

test_that("undo clears a selection made after the delete, so indices cannot drift (M-9)", {
  ten <- load_fixture_dataset("Magnolia_acuminata_data.csv")[1:10, ]
  analysis_data <- reactiveVal(ten)
  selected_points <- reactiveVal(numeric(0))
  testServer(dataAnalysisServer, args = list(analysis_data = analysis_data, selected_points = selected_points), {
    session$flushReact()
    selected_points(2)
    session$setInputs(deleteSelection = 1)
    expect_equal(nrow(analysis_data()), 9)

    selected_points(2)                       # original row 3, now at index 2
    session$setInputs(undoLastDelete = 1)
    expect_equal(nrow(analysis_data()), 10)
    expect_length(selected_points(), 0)
  })
})

test_that("delete then undo on an unchanged dataset restores every row with a positive count", {
  analysis_data <- reactiveVal(load_fixture_dataset("Magnolia_acuminata_data_small.csv"))
  selected_points <- reactiveVal(numeric(0))
  toasts <- character(0)
  local_mocked_bindings(
    showNotification = function(ui, ...) { toasts <<- c(toasts, as.character(ui)); invisible(NULL) },
    .package = "shiny"
  )
  testServer(dataAnalysisServer, args = list(analysis_data = analysis_data, selected_points = selected_points), {
    session$flushReact()
    selected_points(c(3, 5, 7))
    session$setInputs(deleteSelection = 1)
    expect_equal(nrow(analysis_data()), 5)

    session$setInputs(undoLastDelete = 1)
    expect_equal(nrow(analysis_data()), 8)
    expect_equal(analysis_data()$index, 1:8)
    expect_true(any(grepl("Successfully restored 3 records", toasts, fixed = TRUE)))

    # single-level undo: a second click does nothing
    session$setInputs(undoLastDelete = 2)
    expect_equal(nrow(analysis_data()), 8)
  })
})
