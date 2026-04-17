import Foundation
import SwiftUI
import Observation
import AppKit

struct ThemeInfo: Identifiable, Codable {
    var id: String { name }
    let name: String
    let displayName: String
    let isBuiltin: Bool
}

enum ContentWidthPreset: String, Codable, CaseIterable {
    case comfortable
    case wide
    case extraWide
    case unlimited

    var displayName: String {
        switch self {
        case .comfortable: return "Comfortable (65ch)"
        case .wide:        return "Wide (75ch)"
        case .extraWide:   return "Extra Wide (90ch)"
        case .unlimited:   return "Unlimited"
        }
    }

    /// CSS value assigned to `--content-width`. Flows through the existing
    /// font-override hot-swap so width changes apply without a full reload.
    var cssValue: String {
        switch self {
        case .comfortable: return "min(65ch, 92vw)"
        case .wide:        return "min(75ch, 92vw)"
        case .extraWide:   return "min(90ch, 92vw)"
        case .unlimited:   return "92vw"
        }
    }
}

struct UserPreferences: Codable {
    var selectedTheme: String = "warm-light"
    var fontFamily: String = "system-sans"
    var fontSize: Int = 16
    var contentWidth: ContentWidthPreset = .wide

    init() {}

    private enum CodingKeys: String, CodingKey {
        case selectedTheme
        case fontFamily
        case fontSize
        case contentWidth
    }

    // Tolerant decoding so preferences.json files written by earlier versions
    // (which lack newer keys like `contentWidth`) still load cleanly instead
    // of wiping the user's theme/font choices back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedTheme = try c.decodeIfPresent(String.self, forKey: .selectedTheme) ?? "warm-light"
        self.fontFamily    = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? "system-sans"
        self.fontSize      = try c.decodeIfPresent(Int.self,    forKey: .fontSize) ?? 16
        self.contentWidth  = try c.decodeIfPresent(ContentWidthPreset.self, forKey: .contentWidth) ?? .wide
    }
}

enum ThemeError: LocalizedError {
    case invalidName(String)
    case nameAlreadyExists(String)
    case sourceMissing(String)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidName(let n): return "Invalid theme name: \"\(n)\". Use letters, digits, spaces, hyphens or underscores."
        case .nameAlreadyExists(let n): return "A theme named \"\(n)\" already exists."
        case .sourceMissing(let n): return "Source theme \"\(n)\" could not be read."
        case .writeFailed(let err): return "Failed to write theme: \(err.localizedDescription)"
        }
    }
}

@MainActor
@Observable
class ThemeManager {
    static let shared = ThemeManager()

    var preferences = UserPreferences()

    /// Bumped whenever the themes directory contents change on disk.
    /// `availableThemes` reads this so SwiftUI re-renders Pickers bound to it.
    private var themesFolderVersion: Int = 0

    private let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LightMD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var themesDir: URL {
        let dir = appSupportDir.appendingPathComponent("themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var themesDirectory: URL { themesDir }

    private var preferencesFile: URL {
        appSupportDir.appendingPathComponent("preferences.json")
    }

    init() {
        loadPreferences()
    }

    // MARK: - Background Color

    var backgroundColor: Color {
        switch preferences.selectedTheme {
        case "warm-light": return Color(hex: 0xfaf9f6)
        case "warm-dark": return Color(hex: 0x1c1b19)
        case "classic-light": return Color(hex: 0xffffff)
        default: return Color(hex: 0xfaf9f6)
        }
    }

    /// Theme-appropriate accent color, used for UI affordances like the
    /// drop-target highlight and TOC active-row indicator. Kept in sync
    /// with the --accent CSS variable of each built-in theme.
    var accentColor: Color {
        switch preferences.selectedTheme {
        case "warm-light": return Color(hex: 0xc9a96e)
        case "warm-dark": return Color(hex: 0xc9a96e)
        case "classic-light": return Color(hex: 0x374151)
        default: return Color(hex: 0xc9a96e)
        }
    }

    // MARK: - Current CSS

    var currentCSS: String {
        if BuiltinThemes.names.contains(preferences.selectedTheme) {
            return BuiltinThemes.css(for: preferences.selectedTheme)
        }
        let file = themesDir.appendingPathComponent("\(preferences.selectedTheme).css")
        if let css = try? String(contentsOf: file, encoding: .utf8) {
            return css
        }
        return BuiltinThemes.css(for: "warm-light")
    }

    var fontOverrideCSS: String {
        let family: String
        switch preferences.fontFamily {
        case "system-sans": family = #"-apple-system, "Helvetica Neue", sans-serif"#
        case "serif": family = #"Georgia, "Times New Roman", serif"#
        case "mono": family = #""SF Mono", Menlo, monospace"#
        default: family = preferences.fontFamily
        }
        return """
        :root { \
        --font-body: \(family); \
        --font-size: \(preferences.fontSize)px; \
        --content-width: \(preferences.contentWidth.cssValue); \
        }
        """
    }

    // MARK: - Theme listing

    var availableThemes: [ThemeInfo] {
        _ = themesFolderVersion  // establish dependency for SwiftUI observation
        var themes = BuiltinThemes.names.map { name in
            ThemeInfo(name: name, displayName: BuiltinThemes.displayName(for: name), isBuiltin: true)
        }

        if let files = try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil) {
            let customs = files
                .filter { $0.pathExtension == "css" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .filter { name in !themes.contains(where: { $0.name == name }) }
                .sorted()
            for name in customs {
                themes.append(ThemeInfo(name: name, displayName: name, isBuiltin: false))
            }
        }

        return themes
    }

    /// Called by the themes watcher when the directory contents change.
    func refreshAvailableThemes() {
        themesFolderVersion &+= 1
    }

    // MARK: - File URLs

    /// Returns the on-disk URL for a theme's .css file.
    /// - builtin themes: bundle URL (read-only)
    /// - custom themes: Application Support URL (writable)
    func themeFileURL(for name: String) -> URL? {
        if BuiltinThemes.names.contains(name) {
            return BuiltinThemes.bundleURL(for: name)
        }
        let url = themesDir.appendingPathComponent("\(name).css")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Custom theme CRUD

    func saveCustomTheme(name: String, css: String) {
        let file = themesDir.appendingPathComponent("\(name).css")
        try? css.write(to: file, atomically: true, encoding: .utf8)
        refreshAvailableThemes()
    }

    func deleteCustomTheme(name: String) {
        let file = themesDir.appendingPathComponent("\(name).css")
        try? FileManager.default.removeItem(at: file)
        if preferences.selectedTheme == name {
            preferences.selectedTheme = "warm-light"
            savePreferences()
        }
        refreshAvailableThemes()
    }

    /// Duplicates a theme (builtin or custom) into a new custom theme file.
    /// Throws `ThemeError` on validation or I/O failure.
    @discardableResult
    func duplicateTheme(from sourceName: String, to newName: String) throws -> String {
        let validated = try validateThemeName(newName)
        if availableThemes.contains(where: { $0.name == validated }) {
            throw ThemeError.nameAlreadyExists(validated)
        }

        let sourceCSS: String
        if BuiltinThemes.names.contains(sourceName) {
            sourceCSS = BuiltinThemes.css(for: sourceName)
        } else {
            let sourceURL = themesDir.appendingPathComponent("\(sourceName).css")
            guard let css = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                throw ThemeError.sourceMissing(sourceName)
            }
            sourceCSS = css
        }

        let destURL = themesDir.appendingPathComponent("\(validated).css")
        do {
            try sourceCSS.write(to: destURL, atomically: true, encoding: .utf8)
        } catch {
            throw ThemeError.writeFailed(underlying: error)
        }
        refreshAvailableThemes()
        return validated
    }

    /// Generates a non-colliding "{base} Copy", "{base} Copy 2", … default name.
    func suggestedDuplicateName(for sourceName: String) -> String {
        let baseDisplay = BuiltinThemes.names.contains(sourceName)
            ? BuiltinThemes.displayName(for: sourceName)
            : sourceName
        let base = "\(baseDisplay) Copy"
        let existing = Set(availableThemes.map(\.name))
        if !existing.contains(base) { return base }
        for i in 2...999 {
            let candidate = "\(base) \(i)"
            if !existing.contains(candidate) { return candidate }
        }
        return base
    }

    private func validateThemeName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThemeError.invalidName(raw) }
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_"))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw ThemeError.invalidName(raw)
        }
        return trimmed
    }

    // MARK: - NSWorkspace integration

    func openThemeInEditor(_ name: String) {
        guard let url = themeFileURL(for: name) else { return }
        // Builtin CSS inside the app bundle is read-only; opening it in an editor
        // would let the user save changes to an ephemeral location that disappears
        // on next install. For builtins we reveal in Finder instead to make the
        // "clone first, then edit" flow obvious.
        if BuiltinThemes.names.contains(name) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealThemeInFinder(_ name: String) {
        guard let url = themeFileURL(for: name) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openThemesFolder() {
        NSWorkspace.shared.open(themesDir)
    }

    // MARK: - Persistence

    func loadPreferences() {
        guard let data = try? Data(contentsOf: preferencesFile),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else { return }
        preferences = prefs
    }

    func savePreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        try? data.write(to: preferencesFile, options: .atomic)
    }
}
