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


# --- T-07 (audit H-1, M-2, L-2, L-3, L-14) --------------------------------------------

# A fileInput-style list for a temp file written from raw bytes or lines.
temp_upload <- function(lines = NULL, bytes = NULL, name = "upload.csv") {
  tmp <- tempfile(fileext = paste0(".", tools::file_ext(name)))
  if (!is.null(bytes)) writeBin(bytes, tmp) else writeLines(lines, tmp, useBytes = TRUE)
  list(name = name, datapath = tmp, size = file.size(tmp))
}
UPLOAD_HEADER <- "Accession Number,Taxon Name,Current Germplasm Type,Collection Date,Latitude,Longitude,Locality,Collector"

test_that("a Windows-1252 CSV loads as valid UTF-8 instead of crashing the map (H-1)", {
  # "Caf\xe9 Ni\xf1o" as Excel's "CSV (Comma delimited)" writes it on Windows
  row <- c(charToRaw("A1,Quercus alba,G,2001-01-01,33.5,-84.2,Caf"), as.raw(0xe9),
           charToRaw(" Ni"), as.raw(0xf1), charToRaw("o,Someone"))
  res <- read_upload_file(temp_upload(bytes = c(charToRaw(paste0(UPLOAD_HEADER, "\n")), row, charToRaw("\n"))))
  expect_equal(res$status, "success")
  expect_equal(res$data$Locality, "Caf\u00e9 Ni\u00f1o")
  chr <- unlist(res$data[vapply(res$data, is.character, logical(1))])
  expect_true(all(validUTF8(chr[!is.na(chr)])))
  # the two calls that used to throw "invalid multibyte string"
  d <- merge_and_index(data.frame(), res$data)
  expect_no_error(point_labels(d))
})

test_that("a UTF-8 CSV, with or without a byte-order mark, is read unchanged (H-1)", {
  line <- "A1,Quercus alba,G,2001-01-01,33.5,-84.2,Caf\u00e9 Ni\u00f1o,Someone"
  plain <- read_upload_file(temp_upload(bytes = charToRaw(enc2utf8(paste0(UPLOAD_HEADER, "\n", line, "\n")))))
  expect_equal(plain$data$Locality, "Caf\u00e9 Ni\u00f1o")
  bom <- read_upload_file(temp_upload(bytes = c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(enc2utf8(paste0(UPLOAD_HEADER, "\n", line, "\n"))))))
  expect_equal(bom$status, "success")
  expect_equal(bom$data$Locality, "Caf\u00e9 Ni\u00f1o")
  expect_equal(bom$data$`Accession Number`, "A1")
})

test_that("Excel date cells in Collection Date come through as dates, not serial numbers (M-2)", {
  path <- fixture_path("upload_excel_date_cells.xlsx")
  res <- read_upload_file(list(name = "dates.xlsx", datapath = path, size = file.size(path)))
  expect_equal(res$status, "success")
  expect_equal(res$data$`Collection Date`, c("2011-08-14", "2011-08-03", "2011"))   # text cell untouched
  expect_equal(res$data$Latitude, c(35.70725, 35.140667, 35.2))
  expect_equal(res$data$`Accession Number`[1], "574679236")
  # the existing all-text workbook is unaffected
  old <- read_upload_file(fixture_file("upload_sample_manual_properly_formatted_excel.xlsx"))
  expect_equal(nrow(old$data), 200)
  expect_false(any(grepl("^[0-9]{5}$", old$data$`Collection Date`)))
})

test_that("headers that collapse to the same column are reported by name (L-2)", {
  res <- read_upload_file(temp_upload(c(
    paste0(UPLOAD_HEADER, ",latitude"),
    "A1,Quercus alba,G,2001-01-01,33.5,-84.2,Somewhere,Someone,33.5")))
  expect_equal(res$status, "validation_error")
  expect_match(res$message, "Latitude")
  expect_match(res$message, "more than once", fixed = TRUE)
})

test_that("semicolon- and tab-delimited files load (L-3)", {
  semi <- read_upload_file(temp_upload(c(
    gsub(",", ";", UPLOAD_HEADER),
    "A1;Quercus alba;G;2001-01-01;33,5;-84,2;Somewhere, near the river;Someone",
    "A2;Quercus alba;H;2001-01-02;34.5;-85.2;Elsewhere;Someone")))
  expect_equal(semi$status, "success")
  expect_equal(nrow(semi$data), 2)
  expect_equal(semi$data$Latitude, c(33.5, 34.5))          # decimal comma accepted
  expect_equal(semi$data$Longitude, c(-84.2, -85.2))
  expect_equal(semi$data$Locality[1], "Somewhere, near the river")

  tab <- read_upload_file(temp_upload(c(
    gsub(",", "\t", UPLOAD_HEADER),
    "A1\tQuercus alba\tG\t2001-01-01\t33.5\t-84.2\tSomewhere\tSomeone")))
  expect_equal(tab$status, "success")
  expect_equal(tab$data$Latitude, 33.5)

  # a comma file whose text fields contain semicolons is still a comma file
  comma <- read_upload_file(temp_upload(c(
    UPLOAD_HEADER, 'A1,Quercus alba,G,2001-01-01,33.5,-84.2,"a; b; c; d; e; f; g; h; i",Someone')))
  expect_equal(comma$status, "success")
  expect_equal(comma$data$Locality, "a; b; c; d; e; f; g; h; i")
})

test_that("files that are not a delimited table get a specific message (L-3)", {
  xlsx <- fixture_file("upload_sample_manual_properly_formatted_excel.xlsx")
  renamed <- read_upload_file(list(name = "really_excel.csv", datapath = xlsx$datapath))
  expect_equal(renamed$status, "validation_error")
  expect_match(renamed$message, "Excel")

  empty <- read_upload_file(temp_upload(character(0)))
  expect_equal(empty$status, "validation_error")
  expect_match(empty$message, "empty")

  one_col <- read_upload_file(temp_upload(c("just one column", "value")))
  expect_equal(one_col$status, "validation_error")
  expect_match(one_col$message, "single column")
})

test_that("a missing Latitude column and a missing Longitude column are each filled with NA (L-14)", {
  base <- readr::read_csv(fixture_file("upload_sample_small.csv")$datapath, col_types = readr::cols(.default = "c"))
  no_lat <- tempfile(fileext = ".csv"); readr::write_csv(base[, names(base) != "Latitude"], no_lat)
  res <- read_upload_file(list(name = "no_lat.csv", datapath = no_lat))
  expect_equal(res$status, "success")
  expect_true(all(is.na(res$data$Latitude)))
  expect_false(all(is.na(res$data$Longitude)))

  # the workbook fixture named "..._missing_lat" actually lacks Longitude
  res2 <- read_upload_file(fixture_file("upload_sample_manual_properly_formatted_excel_missing_lat.xlsx"))
  expect_true(all(is.na(res2$data$Longitude)))
  expect_false(all(is.na(res2$data$Latitude)))
})
