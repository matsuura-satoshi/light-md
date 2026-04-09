import SwiftUI

@main
struct LightMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.appState) private var focusedAppState
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("lastUpdateCheck") private var lastUpdateCheck: Double = 0

    @State private var showUpdateAvailableAlert = false
    @State private var showNoUpdateAlert = false
    @State private var showUpdateErrorAlert = false
    @State private var isManualCheck = false

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
                .onAppear {
                    checkForUpdatesOnLaunch()
                }
                .alert("Update Available", isPresented: $showUpdateAvailableAlert) {
                    Button("Download and Install") {
                        Task { await updateChecker.downloadAndInstall() }
                    }
                    Button("View Release Page") {
                        updateChecker.openReleasePage()
                    }
                    Button("Later", role: .cancel) {}
                } message: {
                    if let release = updateChecker.latestRelease {
                        Text("A new version (\(release.tagName)) is available. Current version: v\(updateChecker.currentVersion)")
                    }
                }
                .alert("No Updates Available", isPresented: $showNoUpdateAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("You are running the latest version (v\(updateChecker.currentVersion)).")
                }
                .alert("Update Check Failed", isPresented: $showUpdateErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(updateChecker.errorMessage ?? "An unknown error occurred.")
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LightMD") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }

                Button("Check for Updates...") {
                    isManualCheck = true
                    Task { await performUpdateCheck() }
                }
                .disabled(updateChecker.isChecking)
            }

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

    private func checkForUpdatesOnLaunch() {
        let now = Date().timeIntervalSince1970
        let oneDayInSeconds: Double = 24 * 60 * 60
        guard now - lastUpdateCheck >= oneDayInSeconds else { return }

        isManualCheck = false
        Task { await performUpdateCheck() }
    }

    private func performUpdateCheck() async {
        await updateChecker.checkForUpdates()
        lastUpdateCheck = Date().timeIntervalSince1970

        if updateChecker.updateAvailable {
            showUpdateAvailableAlert = true
        } else if updateChecker.errorMessage != nil {
            if isManualCheck {
                showUpdateErrorAlert = true
            }
        } else if isManualCheck {
            showNoUpdateAlert = true
        }
    }
}
