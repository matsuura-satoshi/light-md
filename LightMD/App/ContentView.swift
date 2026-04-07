import SwiftUI
import WebKit

struct ContentView: View {
    @State private var appState = AppState()
    @State private var tocHeadings: [TOCHeading] = []
    @State private var activeHeadingID: String?
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main content — always fills full width
            if appState.renderedHTML.isEmpty {
                appState.themeManager.backgroundColor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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

            // TOC sidebar — overlaid on the right, doesn't push content
            if appState.isTOCVisible && !tocHeadings.isEmpty {
                TOCSidebar(
                    headings: tocHeadings,
                    activeID: activeHeadingID
                ) { id in
                    appState.scrollToHeading(id)
                }
                .transition(.move(edge: .trailing))
            }

            // Transparent drop zone — always active, passes clicks through
            DropOverlay(onDrop: { url in
                appState.openFile(url)
            }, isTargeted: $isDropTargeted)

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
        .focusedValue(\.appState, appState)
        .onAppear {
            if appState.currentFileURL == nil, let pending = PendingFileQueue.shared.dequeue() {
                appState.openFile(pending)
            }
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
}
