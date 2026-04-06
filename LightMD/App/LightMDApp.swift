import SwiftUI

@main
struct LightMDApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onOpenURL { url in
                    appState.openFile(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appState.showOpenPanel()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Export as PDF...") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("e")
                .disabled(appState.renderedHTML.isEmpty)
            }
            CommandGroup(replacing: .printItem) {
                Button("Export as PDF...") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("p")
                .disabled(appState.renderedHTML.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Table of Contents") {
                    NotificationCenter.default.post(name: .toggleTOC, object: nil)
                }
                .keyboardShortcut("i")
            }
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    appState.reloadFile()
                }
                .keyboardShortcut("r")

                Divider()

                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+")

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-")

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0")
            }
        }

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
