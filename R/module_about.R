# ABOUT MODULE ------------------------------------------------------------------------
aboutUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      id = ns("about_content"),
      class = "container",
      style = "max-width: 900px; padding: 40px;",
      # This line does all the work
      includeMarkdown("appData/about.md")
    ),
    # Markdown links render without target="_blank", so clicking one navigates
    # the app page away and ends the Shiny session. Open every external
    # (http/https) link on this page in a new tab instead.
    tags$script(HTML(sprintf(
      "document.querySelectorAll('#%s a[href^=\"http\"]').forEach(function (a) {
         a.setAttribute('target', '_blank');
         a.setAttribute('rel', 'noopener noreferrer');
       });",
      ns("about_content")
    ))),
    # Shared footer sits below the text column, not inside it
    footer_ui()
  )
}

aboutServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # No server logic needed
  })
}
