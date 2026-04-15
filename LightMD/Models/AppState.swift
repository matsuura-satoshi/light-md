import Foundation
import AppKit
import Observation

@MainActor
@Observable
class AppState {
    let id = UUID()
    var currentFileURL: URL?
    var markdownContent: String = ""

    /// Rendered HTML body (from Markdown). Only changes when the .md file
    /// changes — theme/font edits leave it alone.
    var bodyHTML: String = ""

    /// Full HTML document including theme CSS. Used for the initial load and
    /// whenever `bodyHTML` changes. CSS-only updates bypass this and hot-swap
    /// the `<style>` tags via `themeCSS` / `fontOverrideCSS` below.
    var renderedHTML: String = ""

    /// Current theme CSS string. Bumped on theme change, CSS-file live reload,
    /// and full rebuilds. Watched by `MarkdownWebView` for hot swap.
    var themeCSS: String = ""

    /// Font override CSS (:root variables). Same hot-swap path as `themeCSS`.
    var fontOverrideCSS: String = ""

    var isTOCVisible = false
    var scrollTarget: String?
    var exportTrigger: UUID?

    /// Body font size bounds shared between the Preferences slider and the
    /// Cmd+(+/-) shortcut. Cmd+(+/-) mutates `preferences.fontSize` directly
    /// so the live preview and the exported PDF always use the same size.
    static let fontSizeMin: Int = 10
    static let fontSizeMax: Int = 40
    static let fontSizeDefault: Int = 16
    static let fontSizeShortcutStep: Int = 2

    let themeManager = ThemeManager.shared
    private let renderer = MarkdownRenderer()
    private let fileWatcher = FileWatcher()
    private let themesWatcher = ThemesWatcher()

    init() {
        fileWatcher.onChange = { [weak self] in
            self?.reloadFile()
        }
        themesWatcher.onThemesListChanged = { [weak self] in
            self?.themeManager.refreshAvailableThemes()
            self?.handleThemesListChanged()
        }
        themesWatcher.onActiveThemeChanged = { [weak self] in
            self?.liveReloadCSS()
        }
        themesWatcher.startWatchingFolder(themeManager.themesDirectory)
        bindActiveThemeWatcher()
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

    /// Full rebuild — regenerates body HTML from markdown AND refreshes CSS.
    /// Triggers a WKWebView `loadHTMLString` (scroll position is preserved by
    /// MarkdownWebView).
    func rebuildHTML() {
        bodyHTML = renderer.renderHTML(from: markdownContent)
        themeCSS = themeManager.currentCSS
        fontOverrideCSS = themeManager.fontOverrideCSS
        renderedHTML = HTMLTemplateBuilder.build(
            body: bodyHTML,
            themeCSS: themeCSS,
            fontOverrideCSS: fontOverrideCSS
        )
    }

    /// CSS-only refresh. Updates `themeCSS` / `fontOverrideCSS` without
    /// rebuilding `renderedHTML`, so `MarkdownWebView` takes the hot-swap
    /// path (evaluateJavaScript instead of full reload).
    func refreshCSSOnly() {
        themeCSS = themeManager.currentCSS
        fontOverrideCSS = themeManager.fontOverrideCSS
    }

    /// Called by `ThemesWatcher` when the active custom theme CSS file is
    /// edited externally. Also switches the watched file if the selection
    /// changed to a builtin/custom boundary.
    func liveReloadCSS() {
        refreshCSSOnly()
    }

    /// Must be called when `selectedTheme` changes so the active-theme
    /// watcher is bound to the new file (or cleared for builtin themes).
    func bindActiveThemeWatcher() {
        let name = themeManager.preferences.selectedTheme
        if BuiltinThemes.names.contains(name) {
            themesWatcher.setActiveThemeFile(nil)
        } else {
            themesWatcher.setActiveThemeFile(themeManager.themeFileURL(for: name))
        }
    }

    /// If the active custom theme file disappeared from the folder (deleted
    /// externally), fall back to warm-light.
    private func handleThemesListChanged() {
        let name = themeManager.preferences.selectedTheme
        guard !BuiltinThemes.names.contains(name) else { return }
        if themeManager.themeFileURL(for: name) == nil {
            themeManager.preferences.selectedTheme = "warm-light"
            themeManager.savePreferences()
            bindActiveThemeWatcher()
            refreshCSSOnly()
        }
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

    func zoomIn() {
        let new = min(themeManager.preferences.fontSize + Self.fontSizeShortcutStep, Self.fontSizeMax)
        guard new != themeManager.preferences.fontSize else { return }
        themeManager.preferences.fontSize = new
        themeManager.savePreferences()
    }

    func zoomOut() {
        let new = max(themeManager.preferences.fontSize - Self.fontSizeShortcutStep, Self.fontSizeMin)
        guard new != themeManager.preferences.fontSize else { return }
        themeManager.preferences.fontSize = new
        themeManager.savePreferences()
    }

    func zoomReset() {
        guard themeManager.preferences.fontSize != Self.fontSizeDefault else { return }
        themeManager.preferences.fontSize = Self.fontSizeDefault
        themeManager.savePreferences()
    }

    func requestExport() { exportTrigger = UUID() }
    func scrollToHeading(_ id: String) { scrollTarget = id }
}
