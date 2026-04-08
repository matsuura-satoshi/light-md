import SwiftUI

@main
struct LightMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.appState) private var focusedAppState

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if let state = focusedAppState {
                        state.openFile(url)
                    } else {
                        PendingFileQueue.shared.enqueue(url)
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    if let currentWindow = NSApp.keyWindow,
                       let wc = currentWindow.windowController {
                        wc.newWindowForTab(nil)
                        if let newWindow = NSApp.keyWindow,
                           newWindow !== currentWindow {
                            currentWindow.addTabbedWindow(newWindow, ordered: .above)
                            newWindow.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                .keyboardShortcut("t")

                Button("Open...") {
                    focusedAppState?.showOpenPanel()
                }
                .keyboardShortcut("o")
                .disabled(focusedAppState == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Export as PDF...") {
                    focusedAppState?.requestExport()
                }
                .keyboardShortcut("e")
                .disabled(focusedAppState?.renderedHTML.isEmpty ?? true)
            }
            CommandGroup(replacing: .printItem) {
                Button("Export as PDF...") {
                    focusedAppState?.requestExport()
                }
                .keyboardShortcut("p")
                .disabled(focusedAppState?.renderedHTML.isEmpty ?? true)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Table of Contents") {
                    focusedAppState?.isTOCVisible.toggle()
                }
                .keyboardShortcut("i")
            }
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    focusedAppState?.reloadFile()
                }
                .keyboardShortcut("r")

                Divider()

                Button("Zoom In") {
                    focusedAppState?.zoomIn()
                }
                .keyboardShortcut("+")

                Button("Zoom Out") {
                    focusedAppState?.zoomOut()
                }
                .keyboardShortcut("-")

                Button("Actual Size") {
                    focusedAppState?.zoomReset()
                }
                .keyboardShortcut("0")
            }
        }

        Settings {
            PreferencesView()
        }
    }
}
