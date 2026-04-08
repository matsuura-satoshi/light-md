import Foundation
import cmark

class MarkdownRenderer {

    func renderHTML(from markdown: String) -> String {
        let content = stripFrontmatter(markdown)
        let options = CMARK_OPT_DEFAULT | CMARK_OPT_HARDBREAKS
        guard let html = cmark_gfm_markdown_to_html(
            content, content.utf8.count, options
        ) else {
            return "<p>Error rendering markdown</p>"
        }
        defer { free(html) }
        return String(cString: html)
    }

    private func stripFrontmatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---") else { return markdown }
        let lines = markdown.components(separatedBy: "\n")
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return lines[(i + 1)...].joined(separator: "\n")
            }
        }
        return markdown
    }
}
