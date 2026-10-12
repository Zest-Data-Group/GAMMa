# Merge new data into current data, enforce schema, and re-index
merge_and_index <- function(current_data, new_data) {
  # Defensive: ensure inputs exist
  if (is.null(current_data)) current_data <- dplyr::tibble()
  if (is.null(new_data)) new_data <- dplyr::tibble()

  # 1. Combine data first (bind_rows safely handles non-matching columns)
  combined <- dplyr::bind_rows(current_data, new_data)

  # Early exit if empty
  if (nrow(combined) == 0) return(dplyr::tibble())

  # 2. Define the strict, master schema (excluding index, which we generate last)
  expected_cols <- c(
    "Accession Number", "Taxon Name", "Current Germplasm Type",
    "Collection Date", "Latitude", "Longitude", "Locality",
    "Collector", "issues", "source"
  )

  # 3. Inject any missing columns as NA (e.g., if 'issues' is missing)
  missing_cols <- setdiff(expected_cols, names(combined))
  if (length(missing_cols) > 0) {
    combined[missing_cols] <- NA
  }

  # 4. Enforce strict types, subset to only approved columns, and add index
  combined |>
    dplyr::mutate(
      # Force everything except coordinates to character
      dplyr::across(dplyr::all_of(setdiff(expected_cols, c("Latitude", "Longitude"))), as.character),
      # Force coordinates to numeric
      Latitude = as.numeric(Latitude),
      Longitude = as.numeric(Longitude)
    ) |>
    dplyr::mutate(
      `Current Germplasm Type` = toupper(trimws(`Current Germplasm Type`)),
      `Taxon Name` = trimws(`Taxon Name`)
    ) |>
    # Drop any rogue columns uploaded by the user
    dplyr::select(dplyr::all_of(expected_cols)) |>
    dplyr::mutate(index = dplyr::row_number()) |>
    flag_invalid_germplasm()
}

# Rows whose Current Germplasm Type is not G/H are kept (they still show in the
# tables, in grey on the map) but every gap-analysis metric ignores them. Record
# how many there are so the UI can warn the user.
flag_invalid_germplasm <- function(df) {
  n <- sum(!df$`Current Germplasm Type` %in% c("G", "H"))
  attr(df, "invalid_germplasm") <- n
  df
}


# --- Helper: status banner (#73) ---
# A dismissible Bootstrap alert placed above the page content. Copy comes from
# landing_text$banner; the address from CONTACT_EMAIL (global.R).
app_banner_ui <- function(banner = if (exists("landing_text")) landing_text$banner else NULL) {
  if (is.null(banner) || !isTRUE(banner$show)) return(NULL)
  email <- if (exists("CONTACT_EMAIL")) CONTACT_EMAIL else "hello@zestdg.com"
  div(
    class = "alert alert-warning alert-dismissible app-banner mb-0",
    role = "alert",
    tags$i(class = "bi bi-info-circle-fill me-2"),
    tags$span(banner$text),
    tags$span(
      class = "app-banner-contact",
      banner$contact_label,
      tags$a(href = paste0("mailto:", email), email)
    ),
    tags$button(type = "button", class = "btn-close", `data-bs-dismiss` = "alert", `aria-label` = "Close")
  )
}

# --- Helper: render a markdown file with {{PLACEHOLDER}} substitution ---
# Same rendering path as shiny::includeMarkdown(), but the text is read first so
# values such as the version, the public URL and the contact address can be
# filled in from one place (#71, #73). Relative image paths resolve against the
# app root (e.g. "www/x.svg"), and local images are inlined by the renderer.
render_markdown_file <- function(path, vars = list()) {
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  for (nm in names(vars)) txt <- gsub(paste0("{{", nm, "}}"), vars[[nm]], txt, fixed = TRUE)
  html <- if (utils::packageVersion("markdown") < "1.3") {
    markdown::markdownToHTML(text = txt, fragment.only = TRUE)
  } else {
    markdown::mark(text = txt, output = NULL)
  }
  Encoding(html) <- "UTF-8"
  HTML(html)
}

# The placeholders every app markdown file may use.
markdown_vars <- function() {
  list(
    APP_VERSION   = if (exists("APP_VERSION")) APP_VERSION else "dev",
    APP_URL       = if (exists("APP_URL")) APP_URL else "",
    CONTACT_EMAIL = if (exists("CONTACT_EMAIL")) CONTACT_EMAIL else "hello@zestdg.com",
    YEAR          = format(Sys.Date(), "%Y")
  )
}

# --- Helper: Modern Footer UI Component ---
# Shared by the landing page and the About page. Links come from REPO_URL in
# global.R (update that one constant when the repository moves); the version
# comes from the VERSION file via APP_VERSION.
footer_ui <- function() {
  repo_url <- if (exists("REPO_URL")) REPO_URL else "https://github.com/Zest-Data-Group/GAMMa"
  version  <- if (exists("APP_VERSION")) APP_VERSION else "dev"
  email    <- if (exists("CONTACT_EMAIL")) CONTACT_EMAIL else "hello@zestdg.com"
  tags$footer(
    class = "footer-modern",
    div(
      class = "container",
      div(
        class = "row",

        # COLUMN 1: Partners & Logos
        div(
          class = "col-md-5 footer-col",
          h5("Supported By"),
          div(
            class = "footer-logos",
            tags$a(
              href = "https://www.bgci.org/",
              target = "_blank",
              tags$img(src = "bgci.png", alt = "BGCI Logo")
            ),
            tags$a(
              href = "https://www.usbg.gov/",
              target = "_blank",
              tags$img(src = "usbg.jpg", alt = "USBG Logo")
            ),
            tags$a(
              href = "https://www.imls.gov/",
              target = "_blank",
              tags$img(src = "imls_logo_2c.jpg", alt = "IMLS Logo")
            ),
            tags$a(
              href = "https://atlantabg.org/",
              target = "_blank",
              tags$img(src = "abg.jpg", alt = "ABG Logo")
            )
          )
        ),

        # COLUMN 2: About the Tool
        div(
          class = "col-md-4 footer-col",
          h5("About This Tool"),
          p(
            "This dashboard supports global conservation efforts by providing gap analysis and data exploration tools for prioritized taxa."
          ),
          p(tags$a(href = paste0(repo_url, "#readme"), target = "_blank", "Read Documentation", class = "footer-link"))
        ),

        # COLUMN 3: Contact / Links
        div(
          class = "col-md-3 footer-col",
          h5("Contact"),
          tags$ul(
            class = "list-unstyled",
            tags$li(
              tags$i(class = "bi bi-envelope"),
              tags$a(href = paste0("mailto:", email), paste0(" ", email), class = "footer-link")
            ),
            tags$li(
              tags$i(class = "bi bi-github"),
              tags$a(href = repo_url, target = "_blank", " View Source Code", class = "footer-link")
            ),
            tags$li(
              tags$i(class = "bi bi-bug"),
              tags$a(href = paste0(repo_url, "/issues/new"), target = "_blank", " Report an Issue", class = "footer-link")
            )
          )
        )
      ),

      # Bottom Copyright Row
      div(
        class = "row mt-4 pt-3 border-top border-secondary",
        div(
          class = "col-md-6 text-muted small",
          paste(
            "©",
            format(Sys.Date(), "%Y"),
            "Global Conservation Consortia. All rights reserved."
          )
        ),
        div(
          class = "col-md-6 text-end text-muted small",
          paste("Version", version)
        )
      )
    )
  )
}
