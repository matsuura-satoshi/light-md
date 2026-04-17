import SwiftUI

struct PreferencesView: View {
    private let themeManager = ThemeManager.shared

    @State private var duplicateSource: ThemeInfo?
    @State private var duplicateName: String = ""
    @State private var errorMessage: String?
    @State private var deleteTarget: ThemeInfo?

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 520, height: 520)
        .onChange(of: themeManager.preferences.selectedTheme) { _, _ in
            themeManager.savePreferences()
        }
        .onChange(of: themeManager.preferences.fontFamily) { _, _ in
            themeManager.savePreferences()
        }
        .onChange(of: themeManager.preferences.fontSize) { _, _ in
            themeManager.savePreferences()
        }
        .onChange(of: themeManager.preferences.contentWidth) { _, _ in
            themeManager.savePreferences()
        }
        .alert("Duplicate Theme", isPresented: duplicateBinding, presenting: duplicateSource) { source in
            TextField("Name", text: $duplicateName)
            Button("Cancel", role: .cancel) { duplicateSource = nil }
            Button("Duplicate") { performDuplicate(source: source) }
        } message: { source in
            Text("Create a copy of \"\(source.displayName)\" in your themes folder.")
        }
        .alert("Delete Theme", isPresented: deleteBinding, presenting: deleteTarget) { target in
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                themeManager.deleteCustomTheme(name: target.name)
                deleteTarget = nil
            }
        } message: { target in
            Text("\"\(target.displayName)\" will be removed from your themes folder. This cannot be undone.")
        }
        .alert("Error", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var appearanceTab: some View {
        Form {
            Section("Theme") {
                VStack(spacing: 4) {
                    ForEach(themeManager.availableThemes) { theme in
                        ThemeRow(
                            theme: theme,
                            isSelected: themeManager.preferences.selectedTheme == theme.name,
                            onSelect: { themeManager.preferences.selectedTheme = theme.name },
                            onDuplicate: { startDuplicate(from: theme) },
                            onEdit: { themeManager.openThemeInEditor(theme.name) },
                            onReveal: { themeManager.revealThemeInFinder(theme.name) },
                            onDelete: { deleteTarget = theme }
                        )
                    }
                }
                HStack {
                    Button {
                        themeManager.openThemesFolder()
                    } label: {
                        Label("Open Themes Folder", systemImage: "folder")
                    }
                    Spacer()
                    Text("Drop .css files into the folder to add themes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }

            Section("Font") {
                Picker("Family", selection: Bindable(themeManager).preferences.fontFamily) {
                    Text("System Sans").tag("system-sans")
                    Text("Serif").tag("serif")
                    Text("Mono").tag("mono")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Size: \(themeManager.preferences.fontSize)px")
                    Slider(
                        value: Binding(
                            get: { Double(themeManager.preferences.fontSize) },
                            set: { themeManager.preferences.fontSize = Int($0) }
                        ),
                        in: Double(AppState.fontSizeMin)...Double(AppState.fontSizeMax),
                        step: 1
                    )
                }
            }

            Section("Layout") {
                Picker("Content Width", selection: Bindable(themeManager).preferences.contentWidth) {
                    ForEach(ContentWidthPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                Text("Content scales with window width up to the chosen maximum. Unlimited fills the window — useful for tables and wide code blocks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Alert bindings

    private var duplicateBinding: Binding<Bool> {
        Binding(
            get: { duplicateSource != nil },
            set: { if !$0 { duplicateSource = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Duplicate flow

    private func startDuplicate(from theme: ThemeInfo) {
        duplicateName = themeManager.suggestedDuplicateName(for: theme.name)
        duplicateSource = theme
    }

    private func performDuplicate(source: ThemeInfo) {
        defer { duplicateSource = nil }
        do {
            let created = try themeManager.duplicateTheme(from: source.name, to: duplicateName)
            themeManager.preferences.selectedTheme = created
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ThemeRow: View {
    let theme: ThemeInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.system(size: 16))

            ThemeSwatch(themeName: theme.name)

            Text(theme.displayName)
                .foregroundStyle(.primary)

            if theme.isBuiltin {
                Text("Built-in")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            Spacer()

            HStack(spacing: 4) {
                if !theme.isBuiltin {
                    iconButton("pencil", help: "Edit in external editor", action: onEdit)
                }
                iconButton("doc.on.doc", help: "Duplicate", action: onDuplicate)
                iconButton("folder", help: "Reveal in Finder", action: onReveal)
                if !theme.isBuiltin {
                    iconButton("trash", help: "Delete", action: onDelete)
                }
            }
            .opacity(isHovered || isSelected ? 1 : 0.55)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct ThemeSwatch: View {
    let themeName: String

    private var colors: (bg: Color, accent: Color) {
        switch themeName {
        case "warm-light": return (Color(hex: 0xfaf9f6), Color(hex: 0xc9a96e))
        case "warm-dark": return (Color(hex: 0x1c1b19), Color(hex: 0xc9a96e))
        case "classic-light": return (Color(hex: 0xffffff), Color(hex: 0x374151))
        default: return (Color(hex: 0xe8e4dd), Color(hex: 0x8a7d6b))
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
