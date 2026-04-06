import SwiftUI

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var tm = appState.themeManager
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 450, height: 350)
        .onChange(of: appState.themeManager.preferences.selectedTheme) { _, _ in
            appState.themeManager.savePreferences()
            appState.rebuildHTML()
        }
        .onChange(of: appState.themeManager.preferences.fontFamily) { _, _ in
            appState.themeManager.savePreferences()
            appState.rebuildHTML()
        }
        .onChange(of: appState.themeManager.preferences.fontSize) { _, _ in
            appState.themeManager.savePreferences()
            appState.rebuildHTML()
        }
    }

    private var appearanceTab: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: Bindable(appState.themeManager).preferences.selectedTheme) {
                    ForEach(appState.themeManager.availableThemes) { theme in
                        HStack {
                            ThemeSwatch(themeName: theme.name)
                            Text(theme.displayName)
                        }
                        .tag(theme.name)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Font") {
                Picker("Family", selection: Bindable(appState.themeManager).preferences.fontFamily) {
                    Text("System Sans").tag("system-sans")
                    Text("Serif").tag("serif")
                    Text("Mono").tag("mono")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Size: \(appState.themeManager.preferences.fontSize)px")
                    Slider(
                        value: Binding(
                            get: { Double(appState.themeManager.preferences.fontSize) },
                            set: { appState.themeManager.preferences.fontSize = Int($0) }
                        ),
                        in: 12...24,
                        step: 1
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ThemeSwatch: View {
    let themeName: String

    private var colors: (bg: Color, accent: Color) {
        switch themeName {
        case "warm-light": return (Color(hex: 0xfaf9f6), Color(hex: 0xc9a96e))
        case "warm-dark": return (Color(hex: 0x1c1b19), Color(hex: 0xc9a96e))
        case "classic-light": return (Color(hex: 0xffffff), Color(hex: 0x0366d6))
        default: return (Color(hex: 0xfaf9f6), Color(hex: 0xc9a96e))
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(colors.bg)
            .frame(width: 24, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(colors.accent, lineWidth: 1.5)
            )
    }
}
