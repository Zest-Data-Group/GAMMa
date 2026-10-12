# ABOUT MODULE ------------------------------------------------------------------------
# The copy lives in appData/about.md. It is rendered with placeholder substitution
# (version, public URL, contact address; see render_markdown_file()) and then
# dressed up on the client: every "##" section becomes a card with alternating
# backgrounds, a table of contents is built from the section headings, and
# external links open in a new tab (#67, #70).
aboutUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "about-page",
      # Quick navigation: jump to the working pages, plus a contents list that
      # the script below fills from the section headings.
      div(
        class = "about-nav container",
        div(
          class = "about-nav-buttons",
          actionButton(ns("go_data"), tagList(icon("database"), " Go to Data Analysis"), class = "btn btn-success"),
          actionButton(ns("go_gap"),  tagList(icon("map"), " Go to Gap Analysis"),       class = "btn btn-outline-success"),
          actionButton(ns("go_home"), tagList(icon("house"), " Home"),                   class = "btn btn-outline-secondary")
        ),
        tags$nav(class = "about-toc", `aria-label` = "On this page", id = ns("toc"))
      ),
      div(
        id = ns("about_content"),
        class = "about-article container",
        render_markdown_file("appData/about.md", markdown_vars())
      ),
      tags$script(HTML(sprintf(
        "(function () {
           var root = document.getElementById('%s');
           var toc  = document.getElementById('%s');
           if (!root) return;
           // Markdown links render without target=_blank; clicking one would
           // navigate away and end the Shiny session.
           root.querySelectorAll('a[href^=\"http\"]').forEach(function (a) {
             a.setAttribute('target', '_blank');
             a.setAttribute('rel', 'noopener noreferrer');
           });
           // Wrap each h2 and what follows it into a section card.
           var nodes = Array.prototype.slice.call(root.childNodes), section = null, n = 0, links = [];
           nodes.forEach(function (node) {
             if (node.nodeType === 1 && node.tagName === 'H2') {
               n += 1;
               section = document.createElement('section');
               section.className = 'about-section ' + (n %% 2 ? 'about-section--a' : 'about-section--b');
               section.id = 'about-sec-' + n;
               root.insertBefore(section, node);
               links.push({ id: section.id, text: node.textContent });
               var top = document.createElement('a');
               top.href = '#' + root.id; top.className = 'about-top-link'; top.textContent = 'Back to top';
               section.appendChild(node); section.appendChild(top);
             } else if (section) {
               var back = section.querySelector('.about-top-link');
               section.insertBefore(node, back);
             }
           });
           if (toc && links.length) {
             var ul = document.createElement('ul');
             links.forEach(function (l) {
               var li = document.createElement('li'), a = document.createElement('a');
               a.href = '#' + l.id; a.textContent = l.text; li.appendChild(a); ul.appendChild(li);
             });
             toc.appendChild(ul);
           }
         })();",
        ns("about_content"), ns("toc")
      ))),
      footer_ui()
    )
  )
}

aboutServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    list(
      go_data = reactive(input$go_data),
      go_gap  = reactive(input$go_gap),
      go_home = reactive(input$go_home)
    )
  })
}
