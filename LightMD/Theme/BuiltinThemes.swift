import Foundation

enum BuiltinThemes {

    static let names: [String] = ["warm-light", "warm-dark", "classic-light"]

    static func displayName(for name: String) -> String {
        switch name {
        case "warm-light": return "Warm Light"
        case "warm-dark": return "Warm Dark"
        case "classic-light": return "Classic Light"
        default: return name
        }
    }

    static func css(for name: String) -> String {
        if let url = bundleURL(for: name),
           let css = try? String(contentsOf: url, encoding: .utf8) {
            return css
        }
        // Fallback if bundle lookup fails: try warm-light, then a diagnostic stub
        if name != "warm-light",
           let url = bundleURL(for: "warm-light"),
           let css = try? String(contentsOf: url, encoding: .utf8) {
            return css
        }
        return "body { font-family: -apple-system, sans-serif; color: #c00; padding: 2em; } body::before { content: 'LightMD: built-in theme CSS not found in bundle.'; }"
    }

    static func bundleURL(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "css")
    }
}
