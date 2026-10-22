# Golden behaviour of read_upload_file() captured from the sample files in appData/.

test_that("rejects unsupported file extensions before reading", {
  res <- read_upload_file(list(name = "data.txt", datapath = tempfile()))
  expect_equal(res$status, "validation_error")
  expect_match(res$message, "Invalid file type")
})

test_that("well-formed CSV loads all rows with the expected columns", {
  res <- read_upload_file(fixture_file("upload_sample.csv"))
  expect_equal(res$status, "success")
  expect_equal(nrow(res$data), 200)
  expect_equal(res$message_type, "message")
  expect_match(res$message, "Successfully loaded 200 records")
  expect_true(all(c("Latitude", "Longitude", "issues", "index", "source") %in% names(res$data)))
  expect_true(is.numeric(res$data$Latitude))
  expect_true(all(res$data$source == "upload"))
  expect_equal(res$data$index, seq_len(200))
})

test_that("small fixtures load", {
  expect_equal(nrow(read_upload_file(fixture_file("upload_sample_small.csv"))$data), 5)
  expect_equal(nrow(read_upload_file(fixture_file("Magnolia_acuminata_data_small.csv"))$data), 8)
  expect_equal(nrow(read_upload_file(fixture_file("Magnolia_acuminata_data.csv"))$data), 200)
})

test_that("missing coordinates produce a warning-type message with the count", {
  res <- read_upload_file(fixture_file("upload_sample_manual_15miss_coords.csv"))
  expect_equal(res$status, "success")
  expect_equal(res$message_type, "warning")
  expect_match(res$message, "15 records have invalid coordinates")
  expect_equal(sum(is.na(res$data$Latitude) | is.na(res$data$Longitude)), 15)
})

test_that("missing optional 'issues' column is injected as NA", {
  res <- read_upload_file(fixture_file("upload_sample_manual_no_issues_col.csv"))
  expect_equal(res$status, "success")
  expect_true("issues" %in% names(res$data))
  expect_true(all(is.na(res$data$issues)))
})

test_that("Excel files read the first sheet with all-text coercion", {
  res <- read_upload_file(fixture_file("upload_sample_manual_properly_formatted_excel.xlsx"))
  expect_equal(res$status, "success")
  expect_equal(nrow(res$data), 200)
  expect_match(res$message, "first sheet only")

  res2 <- read_upload_file(fixture_file("upload_sample_manual_properly_formatted_excel_missing_lat.xlsx"))
  expect_equal(res2$status, "success")
  expect_equal(res2$message_type, "warning")
  expect_match(res2$message, "200 records have invalid coordinates")
})

test_that("missing required columns are reported by name and nothing is loaded", {
  res <- read_upload_file(fixture_file("upload_sample_missing_2_cols.csv"))
  expect_equal(res$status, "validation_error")   # a user problem, not a crash
  expect_null(res$data)
  expect_match(res$message, "Missing columns: Locality, Collector")
})

test_that("an unreadable file is caught and returned as a system error", {
  bad <- tempfile(fileext = ".xlsx")
  writeLines("this is not an xlsx", bad)
  res <- read_upload_file(list(name = "bad.xlsx", datapath = bad))
  expect_equal(res$status, "system_error")
  expect_match(res$message, "Critical error reading file")
})

test_that("headers are matched ignoring case and surrounding whitespace", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c(
    "accession number, TAXON NAME ,current germplasm type,Collection date,latitude,LONGITUDE,locality,collector,Issues,Extra",
    "A1,Quercus alba,g,2001-01-01,33.5,-84.2,Somewhere,Someone,,x"
  ), tmp)
  res <- read_upload_file(list(name = "odd_headers.csv", datapath = tmp))
  expect_equal(res$status, "success")
  expect_true(all(c("Accession Number", "Taxon Name", "Current Germplasm Type", "Collection Date",
                    "Latitude", "Longitude", "Locality", "Collector", "issues") %in% names(res$data)))
  expect_equal(res$data$Latitude, 33.5)
  expect_true("Extra" %in% names(res$data))        # unknown columns pass through untouched
  merged <- merge_and_index(data.frame(), res$data)
  expect_false("Extra" %in% names(merged))          # ...and are dropped by the schema gate
  expect_equal(merged$`Current Germplasm Type`, "G")
})

# --- T-01: rows whose Current Germplasm Type is not G/H are dropped at upload ---

# Write a temp CSV: the 8-row small fixture plus extra rows whose germplasm type
# is given by `types` (all with valid coordinates). Returns a fileInput-style list.
small_fixture_plus_types <- function(types) {
  base <- readLines(fixture_file("Magnolia_acuminata_data_small.csv")$datapath)
  extra <- vapply(seq_along(types), function(i) sprintf(
    '9%07d,Magnolia acuminata (L.) L.,%s,2015,%.4f,%.4f,Extra locality %d,Tester,,%d',
    i, types[i], 36 + i * 0.1, -82 - i * 0.1, i, 300000 + i
  ), character(1))
  tmp <- tempfile(fileext = ".csv")
  writeLines(c(base, extra), tmp)
  list(name = "mixed_types.csv", datapath = tmp, size = file.size(tmp))
}

test_that("rows with a blank or unrecognised germplasm type are dropped with a warning", {
  res <- read_upload_file(small_fixture_plus_types(c("", "X")))
  expect_equal(res$status, "success")
  expect_equal(nrow(res$data), 8)
  expect_equal(res$n_dropped_type, 2)
  expect_equal(res$message_type, "warning")
  expect_match(res$message, "2 records")
  expect_true(all(res$data$`Current Germplasm Type` %in% c("G", "H")))
  expect_equal(res$data$index, seq_len(8))                      # re-indexed after the drop
  expect_setequal(res$dropped_values, c("blank", "X"))          # NA (empty cell) is reported as "blank"
  expect_equal(res$n_dropped_values, 2)
})

test_that("dropped type values keep the user's spelling, capped at 5 with the full distinct count", {
  bad <- c("seed", "Seed", " x ", "Living", "H2", "unknown")
  res <- read_upload_file(small_fixture_plus_types(bad))
  expect_equal(res$status, "success")
  expect_equal(nrow(res$data), 8)
  expect_equal(res$n_dropped_type, 6)
  expect_equal(res$n_dropped_values, 6)
  expect_length(res$dropped_values, 5)
  expect_equal(res$dropped_values, c("seed", "Seed", "x", "Living", "H2"))   # raw case; readr trims padding
})

test_that("lower-case and padded G/H values are kept, nothing dropped", {
  res <- read_upload_file(small_fixture_plus_types(c("g", " h ")))
  expect_equal(res$status, "success")
  expect_equal(nrow(res$data), 10)
  expect_equal(res$n_dropped_type, 0)
  expect_equal(res$dropped_values, character(0))
  expect_equal(res$n_dropped_values, 0)
  expect_equal(res$message_type, "message")
})

test_that("a file with no G or H rows at all is a validation error", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c(
    "Accession Number,Taxon Name,Current Germplasm Type,Collection Date,Latitude,Longitude,Locality,Collector",
    "A1,Quercus alba,X,2001,33.5,-84.2,Here,Someone",
    "A2,Quercus alba,X,2002,33.6,-84.3,There,Someone"
  ), tmp)
  res <- read_upload_file(list(name = "all_x.csv", datapath = tmp))
  expect_equal(res$status, "validation_error")
  expect_null(res$data)
  expect_match(res$message, "G or H")
})
