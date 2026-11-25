# The downloaded report must agree with the app: same colours, same category
# boundaries, same description of the method, and no uploaded text rendered as
# markup (T-05; audit M-11, M-12, M-14, L-9, L-10).

use_app_root()

render_report_html <- function(d, dist_km = 50) {
  L <- gap_layers()
  r <- run_gap_analysis(d, dist_km, land = L$land, ecoRegions = L$eco)
  out <- tempfile(fileext = ".html")
  render_gap_report(r, out)
  list(result = r, lines = readLines(out, warn = FALSE))
}

# The htmlwidget payloads embedded in a rendered report, parsed.
report_widgets <- function(lines) {
  page <- paste(lines, collapse = "\n")
  m <- gregexpr('<script type="application/json" data-for="[^"]+">(.*?)</script>', page, perl = TRUE)
  blocks <- regmatches(page, m)[[1]]
  lapply(blocks, function(b) {
    json <- sub('^<script type="application/json" data-for="[^"]+">', "", sub("</script>$", "", b))
    jsonlite::fromJSON(json, simplifyVector = FALSE)
  })
}

test_that("the gap palettes have fixed levels (M-11, M-14)", {
  pal <- gap_type_palette()
  expect_equal(pal(c("H", "G")), toupper(combinedColor))
  expect_equal(pal(c("G", "H")), toupper(rev(combinedColor)))

  ers <- gap_ers_palette()
  expect_equal(ers(c("Covered", "Gap Ecoregion")), toupper(ersexColors))
  # a single status must not be painted in a blend of the two colours
  expect_equal(ers(rep("Gap Ecoregion", 3)), rep(toupper(ersexColors[2]), 3))
  expect_equal(ers("Covered"), toupper(ersexColors[1]))
})

test_that("report buffers are coloured by their own type (M-14)", {
  rep <- render_report_html(load_fixture_dataset("Magnolia_acuminata_data_small.csv"))
  calls <- unlist(lapply(report_widgets(rep$lines), function(w) w$x$calls), recursive = FALSE)
  buffers <- Filter(function(cl) identical(cl$method, "addPolygons") && identical(cl$args[[3]], "Buffers"), calls)
  expect_length(buffers, 1)

  fill <- toupper(unlist(buffers[[1]]$args[[4]]$fillColor))
  # the popup says which type each polygon is, in the same order as the colours
  popup <- unlist(buffers[[1]]$args[[5]])
  expect_length(fill, length(popup))
  expect_true(any(grepl("Germplasm", popup)) && any(grepl("Reference", popup)))
  expect_equal(fill[grepl("Germplasm", popup)], rep(toupper(combinedColor[2]), sum(grepl("Germplasm", popup))))
  expect_equal(fill[grepl("Reference", popup)], rep(toupper(combinedColor[1]), sum(grepl("Reference", popup))))
})

test_that("uploaded text is never live markup in the report (M-12)", {
  d <- load_fixture_dataset("Magnolia_acuminata_data_small.csv")
  d$`Taxon Name` <- "<img src=x onerror=alert(1)>"
  d$Locality[1] <- "<script>alert(2)</script>"
  d$Locality[2] <- "Forest <near river> & lake"
  d$`Accession Number`[1] <- "A<b>1</b>"
  page <- paste(render_report_html(d)$lines, collapse = "\n")

  expect_false(grepl("<img src=x", page, fixed = TRUE))
  expect_false(grepl("<script>alert(2)", page, fixed = TRUE))
  expect_false(grepl("A<b>1</b>", page, fixed = TRUE))
  # the text is still there, escaped
  expect_true(grepl("&lt;img src=x onerror=alert(1)&gt;", page, fixed = TRUE))
  expect_true(grepl("&lt;near river&gt;", page, fixed = TRUE))
})

test_that("report text matches fcs_priority() and ERSex() (L-9, L-10)", {
  page <- gsub("\\s+", " ", paste(render_report_html(load_fixture_dataset("Magnolia_acuminata_data_small.csv"))$lines, collapse = " "))
  expect_true(grepl("FCS ≤ 25", page, fixed = TRUE))
  expect_true(grepl("FCS &gt; 75", page, fixed = TRUE) || grepl("FCS > 75", page, fixed = TRUE))
  expect_false(grepl("FCS &lt; 25", page, fixed = TRUE))
  expect_false(grepl("FCS < 25", page, fixed = TRUE))
  expect_true(grepl("containing at least one analysed record", page, fixed = TRUE))
  expect_false(grepl("occupied by the estimated range", page, fixed = TRUE))

  about <- paste(readLines("appData/about.md", warn = FALSE), collapse = " ")
  expect_false(grepl("occupied by the potential range", about, fixed = TRUE))
})
