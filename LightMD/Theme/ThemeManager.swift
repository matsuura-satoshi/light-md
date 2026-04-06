import Foundation
import Observation

struct ThemeInfo: Identifiable, Codable {
    var id: String { name }
    let name: String
    let displayName: String
    let isBuiltin: Bool
}

struct UserPreferences: Codable {
    var selectedTheme: String = "warm-light"
    var fontFamily: String = "system-sans"
    var fontSize: Int = 16
}

@MainActor
@Observable
class ThemeManager {
    var preferences = UserPreferences()

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

    private var preferencesFile: URL {
        appSupportDir.appendingPathComponent("preferences.json")
    }

    init() {
        loadPreferences()
    }

    // MARK: - Current CSS

    var currentCSS: String {
        let builtins = ["warm-light", "warm-dark", "classic-light"]
        if builtins.contains(preferences.selectedTheme) {
            return BuiltinThemes.css(for: preferences.selectedTheme)
        }
        // Try loading custom theme
        let file = themesDir.appendingPathComponent("\(preferences.selectedTheme).css")
        if let css = try? String(contentsOf: file, encoding: .utf8) {
            return css
        }
        return BuiltinThemes.warmLight
    }

    var fontOverrideCSS: String {
        let family: String
        switch preferences.fontFamily {
        case "system-sans": family = #"-apple-system, "Helvetica Neue", sans-serif"#
        case "serif": family = #"Georgia, "Times New Roman", serif"#
        case "mono": family = #""SF Mono", Menlo, monospace"#
        default: family = preferences.fontFamily
        }
        return ":root { --font-body: \(family); --font-size: \(preferences.fontSize)px; }"
    }

    // MARK: - Theme listing

    var availableThemes: [ThemeInfo] {
        var themes = [
            ThemeInfo(name: "warm-light", displayName: "Warm Light", isBuiltin: true),
            ThemeInfo(name: "warm-dark", displayName: "Warm Dark", isBuiltin: true),
            ThemeInfo(name: "classic-light", displayName: "Classic Light", isBuiltin: true),
        ]

        if let files = try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "css" {
                let name = file.deletingPathExtension().lastPathComponent
                if !themes.contains(where: { $0.name == name }) {
                    themes.append(ThemeInfo(name: name, displayName: name, isBuiltin: false))
                }
            }
        }

        return themes
    }

    // MARK: - Custom themes

    func saveCustomTheme(name: String, css: String) {
        let file = themesDir.appendingPathComponent("\(name).css")
        try? css.write(to: file, atomically: true, encoding: .utf8)
    }

    func deleteCustomTheme(name: String) {
        let file = themesDir.appendingPathComponent("\(name).css")
        try? FileManager.default.removeItem(at: file)
        if preferences.selectedTheme == name {
            preferences.selectedTheme = "warm-light"
            savePreferences()
        }
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
