import Foundation
import AppKit

/// Single source of truth for runtime-only app state persisted via `UserDefaults`.
///
/// # Persistence rules for LightMD
///
/// LightMD uses exactly two persistence layers, and each attribute lives in
/// exactly one of them:
///
/// 1. **User-chosen preferences** → `~/Library/Application Support/LightMD/preferences.json`
///    Managed by `ThemeManager` / `UserPreferences`. This is for settings the
///    user explicitly configures via the Preferences UI (theme, font family,
///    font size, …). Structured JSON so it can grow without key sprawl.
///
/// 2. **Runtime/session state** → `UserDefaults` via this type (`AppRuntimeState`).
///    This is for state the user does NOT set explicitly but that should
///    survive relaunch (last window frame, last update-check timestamp, …).
///    All keys are defined here as constants so they never depend on SwiftUI
///    view-hierarchy types or on a property-wrapper call site — previously
///    SwiftUI's automatic window-state restoration generated keys from the
///    view tree, and any modifier change orphaned the old frame.
///
/// When adding a new persisted attribute, decide which bucket it belongs to
/// and add it here (or to `UserPreferences`) — not as a one-off `@AppStorage`
/// scattered around the codebase.
///
/// `UserDefaults` is thread-safe, so this type is free to be used from any
/// actor / thread without synchronization.
final class AppRuntimeState: @unchecked Sendable {
    static let shared = AppRuntimeState()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastUpdateCheck = "lastUpdateCheck"
        static let windowFrame = "LightMD.windowFrame"
    }

    private init() {
        purgeLegacySwiftUIWindowFrames()
    }

    // MARK: - Last update check

    var lastUpdateCheck: TimeInterval {
        get { defaults.double(forKey: Keys.lastUpdateCheck) }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheck) }
    }

    // MARK: - Window frame

    /// Returns the last saved window frame, or `nil` if none has been saved.
    func savedWindowFrame() -> NSRect? {
        guard let dict = defaults.dictionary(forKey: Keys.windowFrame),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double,
              w > 0, h > 0
        else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    func saveWindowFrame(_ frame: NSRect) {
        let dict: [String: Double] = [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "w": Double(frame.width),
            "h": Double(frame.height)
        ]
        defaults.set(dict, forKey: Keys.windowFrame)
    }

    // MARK: - Legacy cleanup

    /// Older builds let SwiftUI auto-persist window frames under keys derived
    /// from the view-hierarchy Swift types (e.g. `NSWindow Frame SwiftUI.
    /// ModifiedContent<…, AlertModifier<…>>-1-AppWindow-1`). Those keys
    /// changed every time a modifier was added or removed, so they never
    /// applied to the current build and just accumulated as dead entries in
    /// the plist. Purge them once at startup so the plist stays tidy and the
    /// system never tries to restore an ancient frame from a mismatched key.
    private func purgeLegacySwiftUIWindowFrames() {
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys
        where key.hasPrefix("NSWindow Frame SwiftUI.") {
            defaults.removeObject(forKey: key)
        }
    }
}
