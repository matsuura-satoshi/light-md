import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var appState = AppState()
    @State private var tocHeadings: [TOCHeading] = []
    @State private var activeHeadingID: String?
    @State private var isDropTargeted = false
    @State private var printShortcutMonitor: Any?

    var body: some View {
        ZStack(alignment: .trailing) {
            // Bridge to the hosting NSWindow: applies the persisted frame on
            // appear and writes the current frame back on resize/move. Zero
            // visual footprint.
            WindowStateBinder()
                .frame(width: 0, height: 0)

            // Theme background — always rendered underneath so that the
            // transparent WKWebView never exposes the NSWindow default
            // background during its async HTML load.
            appState.themeManager.backgroundColor
                .ignoresSafeArea()

            // Main content — overlays the theme background once rendered.
            if !appState.renderedHTML.isEmpty {
                MarkdownWebView(
                    htmlContent: appState.renderedHTML,
                    bodyHTML: appState.bodyHTML,
                    themeCSS: appState.themeCSS,
                    fontOverrideCSS: appState.fontOverrideCSS,
                    scrollTarget: appState.scrollTarget,
                    exportTrigger: appState.exportTrigger,
                    onTOCExtracted: { headings in
                        tocHeadings = headings
                    },
                    onActiveHeadingChanged: { id in
                        activeHeadingID = id
                    },
                    onScrollComplete: {
                        appState.scrollTarget = nil
                    }
                )
            }

            // TOC sidebar — overlaid on the right
            if appState.isTOCVisible {
                TOCSidebar(
                    headings: tocHeadings,
                    activeID: activeHeadingID,
                    accent: appState.themeManager.accentColor
                ) { id in
                    appState.scrollToHeading(id)
                }
                .transition(.move(edge: .trailing))
            }

            // Drop highlight overlay
            if isDropTargeted {
                let accent = appState.themeManager.accentColor
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent, lineWidth: 3)
                    .background(accent.opacity(0.08))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isTOCVisible)
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(appState.currentFileURL?.lastPathComponent ?? "LightMD")
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let url,
                      ["md", "markdown"].contains(url.pathExtension.lowercased())
                else { return }
                Task { @MainActor in
                    appState.openFile(url)
                }
            }
            return true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.requestExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export as PDF")
                .disabled(appState.renderedHTML.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isTOCVisible.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .help("Toggle Table of Contents")
            }
        }
        .focusedSceneValue(\.appState, appState)
        .onAppear {
            drainPendingFiles()
            installPrintShortcutMonitor()
        }
        .onDisappear {
            removePrintShortcutMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didEnqueuePendingFile)) { _ in
            drainPendingFiles()
        }
        .onChange(of: appState.themeManager.preferences.selectedTheme) { _, _ in
            appState.bindActiveThemeWatcher()
            if !appState.markdownContent.isEmpty {
                appState.refreshCSSOnly()
            }
        }
        .onChange(of: appState.themeManager.preferences.fontFamily) { _, _ in
            if !appState.markdownContent.isEmpty {
                appState.refreshCSSOnly()
            }
        }
        .onChange(of: appState.themeManager.preferences.fontSize) { _, _ in
            if !appState.markdownContent.isEmpty {
                appState.refreshCSSOnly()
            }
        }
        .onChange(of: appState.themeManager.preferences.contentWidth) { _, _ in
            if !appState.markdownContent.isEmpty {
                appState.refreshCSSOnly()
            }
        }
    }

    private func drainPendingFiles() {
        // Only the empty window claims a pending URL. Windows already
        // showing a file leave the queue alone so a new window/tab spawned
        // for the next double-click can pick it up via its own onAppear.
        guard appState.currentFileURL == nil else { return }
        if let pending = PendingFileQueue.shared.dequeue() {
            appState.openFile(pending)
        }
    }

    // SwiftUI's CommandGroup(replacing: .printItem) with .keyboardShortcut("p")
    // does not reliably install a Cmd+P key equivalent on macOS (same class of
    // issue as the Cmd+T saga — see commits 2e5cece / 9989347 / 7108e3e). A
    // local NSEvent monitor runs before WebKit and before the SwiftUI command
    // chain, so it is the robust escape hatch.
    private func installPrintShortcutMonitor() {
        guard printShortcutMonitor == nil else { return }
        let stateBox = appState
        printShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "p",
                  !stateBox.renderedHTML.isEmpty
            else { return event }
            stateBox.requestExport()
            return nil
        }
    }

    private func removePrintShortcutMonitor() {
        if let monitor = printShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            printShortcutMonitor = nil
        }
    }
}
