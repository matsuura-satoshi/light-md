import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var appState = AppState()
    @State private var tocHeadings: [TOCHeading] = []
    @State private var activeHeadingID: String?
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Theme background — always rendered underneath so that the
            // transparent WKWebView never exposes the NSWindow default
            // background during its async HTML load.
            appState.themeManager.backgroundColor
                .ignoresSafeArea()

            // Main content — overlays the theme background once rendered.
            if !appState.renderedHTML.isEmpty {
                MarkdownWebView(
                    htmlContent: appState.renderedHTML,
                    zoomLevel: appState.zoomLevel,
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
                    activeID: activeHeadingID
                ) { id in
                    appState.scrollToHeading(id)
                }
                .transition(.move(edge: .trailing))
            }

            // Drop highlight overlay
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(hex: 0xc9a96e), lineWidth: 3)
                    .background(Color(hex: 0xc9a96e).opacity(0.08))
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
                HStack(spacing: 4) {
                    Button {
                        appState.requestExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export as PDF")
                    .disabled(appState.renderedHTML.isEmpty)

                    Button {
                        appState.isTOCVisible.toggle()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .help("Toggle Table of Contents")
                }
            }
        }
        .focusedSceneValue(\.appState, appState)
        .onAppear {
            drainPendingFiles()
        }
        .onChange(of: PendingFileQueue.shared.urls.count) { _, _ in
            drainPendingFiles()
        }
        .onChange(of: appState.themeManager.preferences.selectedTheme) { _, _ in
            if !appState.markdownContent.isEmpty {
                appState.rebuildHTML()
            }
        }
        .onChange(of: appState.themeManager.preferences.fontFamily) { _, _ in
            if !appState.markdownContent.isEmpty {
                appState.rebuildHTML()
            }
        }
        .onChange(of: appState.themeManager.preferences.fontSize) { _, _ in
            if !appState.markdownContent.isEmpty {
                appState.rebuildHTML()
            }
        }
    }

    private func drainPendingFiles() {
        if let pending = PendingFileQueue.shared.dequeue() {
            appState.openFile(pending)
        }
    }
}
