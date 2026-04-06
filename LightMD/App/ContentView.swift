import SwiftUI
import WebKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var tocHeadings: [TOCHeading] = []
    @State private var activeHeadingID: String?
    @State private var isTOCVisible = false
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Main content — always fills full width
            if appState.renderedHTML.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownWebView(
                    htmlContent: appState.renderedHTML,
                    onTOCExtracted: { headings in
                        tocHeadings = headings
                    },
                    onActiveHeadingChanged: { id in
                        activeHeadingID = id
                    }
                )
            }

            // TOC sidebar — overlaid on the right, doesn't push content
            if isTOCVisible && !tocHeadings.isEmpty {
                TOCSidebar(
                    headings: tocHeadings,
                    activeID: activeHeadingID
                ) { id in
                    scrollToHeading(id)
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
        .animation(.easeInOut(duration: 0.2), value: isTOCVisible)
        .onReceive(NotificationCenter.default.publisher(for: .toggleTOC)) { _ in
            isTOCVisible.toggle()
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(appState.currentFileURL?.lastPathComponent ?? "LightMD")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    Button {
                        NotificationCenter.default.post(name: .exportPDF, object: nil)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export as PDF")
                    .disabled(appState.renderedHTML.isEmpty)

                    Button {
                        isTOCVisible.toggle()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .help("Toggle Table of Contents")
                    .keyboardShortcut("t", modifiers: .command)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Open a Markdown file to get started")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Drag & drop a .md file or press \u{2318}O")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func scrollToHeading(_ id: String) {
        NotificationCenter.default.post(
            name: .scrollToHeading,
            object: nil,
            userInfo: ["id": id]
        )
    }
}

extension Notification.Name {
    static let scrollToHeading = Notification.Name("scrollToHeading")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
    static let exportPDF = Notification.Name("exportPDF")
    static let toggleTOC = Notification.Name("toggleTOC")
}
