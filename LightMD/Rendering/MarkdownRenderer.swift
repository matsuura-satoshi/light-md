import Foundation
import cmark

class MarkdownRenderer {

    func renderHTML(from markdown: String) -> String {
        let options = CMARK_OPT_DEFAULT | CMARK_OPT_HARDBREAKS
        guard let html = cmark_gfm_markdown_to_html(
            markdown, markdown.utf8.count, options
        ) else {
            return "<p>Error rendering markdown</p>"
        }
        defer { free(html) }
        return String(cString: html)
    }
}
