import Foundation
import AppKit
import Observation

@MainActor
@Observable
class AppState {
    let id = UUID()
    var currentFileURL: URL?
    var markdownContent: String = ""
    var renderedHTML: String = ""
    let themeManager = ThemeManager.shared

    var isTOCVisible = false
    var zoomLevel: Double = 1.0
    var scrollTarget: String?
    var exportTrigger: UUID?

    private let renderer = MarkdownRenderer()
    private let fileWatcher = FileWatcher()

    init() {
        fileWatcher.onChange = { [weak self] in
            self?.reloadFile()
        }
    }

    func openFile(_ url: URL) {
        guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return }
        currentFileURL = url
        fileWatcher.watch(url: url)
        reloadFile()
    }

    func reloadFile() {
        guard let url = currentFileURL else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        markdownContent = content
        rebuildHTML()
    }

    func rebuildHTML() {
        let bodyHTML = renderer.renderHTML(from: markdownContent)
        renderedHTML = HTMLTemplateBuilder.build(
            body: bodyHTML,
            themeCSS: themeManager.currentCSS,
            fontOverrideCSS: themeManager.fontOverrideCSS
        )
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!,
                                      .init(filenameExtension: "markdown")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            openFile(url)
        }
    }

    func zoomIn() { zoomLevel = min(zoomLevel + 0.1, 3.0) }
    func zoomOut() { zoomLevel = max(zoomLevel - 0.1, 0.5) }
    func zoomReset() { zoomLevel = 1.0 }
    func requestExport() { exportTrigger = UUID() }
    func scrollToHeading(_ id: String) { scrollTarget = id }
}
