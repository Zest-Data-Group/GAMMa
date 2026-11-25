# Canonical column names the app understands (see merge_and_index() in utils.R).
UPLOAD_KNOWN_COLS <- c(
  "Accession Number", "Taxon Name", "Current Germplasm Type", "Collection Date",
  "Latitude", "Longitude", "Locality", "Collector", "issues"
)

# Trim whitespace from header names and map case-insensitive matches of the
# known columns onto their canonical spelling. Unknown columns are left as-is
# (merge_and_index() drops them later).
normalise_upload_headers <- function(data) {
  nms <- trimws(names(data))
  key <- tolower(gsub("\\s+", " ", nms))
  canon_key <- tolower(UPLOAD_KNOWN_COLS)
  hit <- match(key, canon_key)
  nms[!is.na(hit)] <- UPLOAD_KNOWN_COLS[hit[!is.na(hit)]]
  names(data) <- nms
  data
}

# --- Delimited text: what kind of file is this? ---------------------------------
# Inspect the raw bytes before parsing so the common "Excel on Windows" exports
# load instead of crashing later or failing with a misleading message:
#   - encoding: valid UTF-8 is read as UTF-8, anything else as Windows-1252,
#     which is what Excel's "CSV (Comma delimited)" writes (audit H-1). Text
#     that is not valid UTF-8 used to pass validation and then take the session
#     down when the map built its labels.
#   - delimiter: comma, semicolon (Excel's default in many locales) or tab,
#     whichever the header line uses most outside quotes (audit L-3).
# Returns list(encoding, delim) or list(error = <message for the user>).
sniff_delimited_file <- function(path) {
  size <- file.size(path)
  if (is.na(size) || size == 0) return(list(error = "Data not loaded. The file is empty."))
  bytes <- readBin(path, "raw", n = size)
  if (length(bytes) >= 2 && identical(bytes[1:2], as.raw(c(0x50, 0x4b)))) {
    return(list(error = "Data not loaded. This looks like an Excel workbook saved with a .csv name. Upload it as .xlsx, or use Save As > CSV in Excel."))
  }
  if (any(bytes == as.raw(0))) {
    return(list(error = "Data not loaded. The file is not plain CSV text (it may be UTF-16 \"Unicode Text\"). In Excel use Save As > CSV UTF-8."))
  }
  text <- rawToChar(bytes)
  encoding <- if (validUTF8(text)) "UTF-8" else "windows-1252"
  # Convert before any string handling: regex functions refuse invalid UTF-8.
  text <- iconv(text, from = encoding, to = "UTF-8", sub = "")
  lines <- strsplit(text, "\r\n|\n|\r")[[1]]
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) == 0) return(list(error = "Data not loaded. The file is empty."))
  header <- gsub('"[^"]*"', "", lines[1])                            # ignore delimiters inside quotes
  counts <- vapply(c(",", ";", "\t"), function(d) lengths(regmatches(header, gregexpr(d, header, fixed = TRUE))), integer(1))
  if (max(counts) == 0) {
    return(list(error = "Data not loaded. The file parsed as a single column. Check that it is comma-, semicolon- or tab-delimited."))
  }
  list(encoding = encoding, delim = names(counts)[which.max(counts)])   # ties go to the comma
}

# Excel: read_excel(col_types = "text") returns a genuine date cell as its
# serial number ("40769" for 2011-08-14), which then showed in the table, the
# popups, the report and the export (audit M-2). Read the sheet a second time
# with typed cells and, in the Collection Date column only, replace date cells
# with an ISO date. Every other cell keeps its text reading.
restore_excel_dates <- function(data, path) {
  i <- which(tolower(gsub("\\s+", " ", trimws(names(data)))) == "collection date")
  if (length(i) != 1 || nrow(data) == 0) return(data)
  typed <- tryCatch(readxl::read_excel(path, sheet = 1, col_types = "list"), error = function(e) NULL)
  if (is.null(typed) || nrow(typed) != nrow(data) || ncol(typed) < i) return(data)
  cells <- typed[[i]]
  is_date <- vapply(cells, function(x) inherits(x, c("POSIXt", "Date")) && length(x) == 1 && !is.na(x), logical(1))
  if (any(is_date)) {
    data[[i]][is_date] <- vapply(cells[is_date], function(x) format(as.Date(x), "%Y-%m-%d"), character(1))
  }
  data
}

read_upload_file <- function(file_info) {
  
  # --- 1. Validation: File Extension ---
  file_ext <- tolower(tools::file_ext(file_info$name))
  if (!file_ext %in% c("csv", "xlsx", "xls")) {
    return(list(
      status  = "validation_error", 
      message = "Invalid file type. Please upload a .csv, .xlsx, or .xls file."
    ))
  }

  # --- 2. Safe Execution Block ---
  tryCatch({
    
    # A. Read File (All columns as text initially)
    delim <- ","
    if (file_ext == "csv") {
      kind <- sniff_delimited_file(file_info$datapath)
      if (!is.null(kind$error)) {
        return(list(status = "validation_error", message = kind$error))
      }
      delim <- kind$delim
      data <- readr::read_delim(
        file_info$datapath,
        delim = delim,
        col_types = readr::cols(.default = "c"),
        locale = readr::locale(encoding = kind$encoding),
        trim_ws = TRUE,
        progress = FALSE
      )
      # Belt and braces: nothing that is not valid UTF-8 leaves this function.
      data[] <- lapply(data, function(x) if (is.character(x)) iconv(x, from = "UTF-8", to = "UTF-8", sub = "") else x)
    } else {
      # Excel: read first sheet only, coerce all columns to character
      data <- readxl::read_excel(
        file_info$datapath,
        sheet = 1,
        col_types = "text"
      )
      data <- restore_excel_dates(data, file_info$datapath)
    }

    # B. Validation: Required Columns
    # Headers are matched ignoring case and surrounding whitespace (a very common
    # spreadsheet export problem) and renamed to the canonical spelling.
    data <- normalise_upload_headers(data)
    # Two headers that differ only in case or spacing ("Latitude", "latitude")
    # now carry the same name; say which, instead of failing later with
    # "duplicate names" (audit L-2).
    dup_cols <- intersect(unique(names(data)[duplicated(names(data))]), UPLOAD_KNOWN_COLS)
    if (length(dup_cols) > 0) {
      return(list(
        status  = "validation_error",
        message = paste0("Data not loaded. These columns appear more than once (header names are matched ignoring case and spaces): ",
                         paste(dup_cols, collapse = ", "), ". Remove or rename the extra column.")
      ))
    }
    required_cols <- c(
      "Accession Number", "Taxon Name", "Current Germplasm Type",
      "Collection Date", "Locality", "Collector"
    )

    missing_cols <- setdiff(required_cols, names(data))

    if (length(missing_cols) > 0) {
      return(list(
        status  = "validation_error",
        message = paste("Data not loaded.  Missing columns:", paste(missing_cols, collapse = ", "))
      ))
    }

    # C. Processing: Coordinates & Metadata
    data <- data %>%
      dplyr::mutate(
        # Create Lat/Lon as NA if they don't exist
        Latitude  = if ("Latitude" %in% names(.)) Latitude else NA_character_,
        Longitude = if ("Longitude" %in% names(.)) Longitude else NA_character_,
        
        # A semicolon-delimited file comes from a locale that writes 33,5
        Latitude  = if (delim == ";") sub(",", ".", Latitude, fixed = TRUE) else Latitude,
        Longitude = if (delim == ";") sub(",", ".", Longitude, fixed = TRUE) else Longitude,

        # Coerce to numeric
        Latitude  = suppressWarnings(as.numeric(Latitude)),
        Longitude = suppressWarnings(as.numeric(Longitude)),

        # Issues not required in upload, set to NA if missing
        issues = if ("issues" %in% names(.)) issues else NA_character_,
        
        # Add Metadata
        index  = dplyr::row_number(), 
        source = "upload"
      )

    # D. Germplasm type gate (T-01, audit C-2)
    # Only rows typed G or H (after trimws + toupper) take part in the analysis.
    # Anything else (blank, "SEED", "X", ...) is dropped here so it never enters
    # the working dataset; the caller shows a confirmation modal before committing.
    raw  <- data$`Current Germplasm Type`
    type <- toupper(trimws(raw))
    type[is.na(type)] <- ""
    keep <- type %in% c("G", "H")
    n_dropped_type <- sum(!keep)
    # The offending values as the user wrote them (an empty cell reads as NA and
    # is reported as "blank"), distinct, capped at 5 for the confirmation modal;
    # n_dropped_values is the uncapped distinct count so the modal can say
    # how many more there were.
    dropped_distinct <- unique(raw[!keep])
    dropped_distinct[is.na(dropped_distinct)] <- "blank"
    n_dropped_values <- length(dropped_distinct)
    dropped_values   <- head(dropped_distinct, 5)

    if (n_dropped_type > 0 && !any(keep)) {
      return(list(
        status  = "validation_error",
        message = "Data not loaded. No rows have a Current Germplasm Type of G or H."
      ))
    }

    data <- data[keep, ] %>%
      dplyr::mutate(index = dplyr::row_number())

    # E. Quality Check: Missing Coordinates
    n_missing_coords <- sum(is.na(data$Latitude) | is.na(data$Longitude))

    excel_note <- if (file_ext %in% c("xlsx", "xls")) " (first sheet only)" else ""

    if (n_missing_coords > 0) {
      msg_type <- "warning"
      msg_text <- paste0("Loaded ", nrow(data), " records", excel_note, ". Note: ", n_missing_coords,
                         " records have invalid coordinates and won't appear on the map.")
    } else {
      msg_type <- "message"
      msg_text <- paste0("Successfully loaded ", nrow(data), " records", excel_note, ".")
    }

    if (n_dropped_type > 0) {
      msg_type <- "warning"
      msg_text <- paste0(
        msg_text, " ", n_dropped_type, " record", if (n_dropped_type > 1) "s" else "",
        " with a blank or unrecognised Current Germplasm Type ",
        if (n_dropped_type > 1) "were" else "was", " dropped."
      )
    }

    # F. Return Success
    list(
      status = "success",
      data = data,
      message = msg_text,
      message_type = msg_type,
      n_dropped_type = n_dropped_type,
      dropped_values = dropped_values,
      n_dropped_values = n_dropped_values
    )

  }, error = function(e) {
    # System Crash Handler
    list(
      status  = "system_error", 
      message = paste("Critical error reading file:", e$message)
    )
  })
}