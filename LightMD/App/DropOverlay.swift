import SwiftUI
import AppKit

struct DropOverlay: NSViewRepresentable {
    let onDrop: (URL) -> Void
    @Binding var isTargeted: Bool

    func makeNSView(context: Context) -> DropOverlayView {
        let view = DropOverlayView()
        view.onDrop = onDrop
        view.onTargetChanged = { isTargeted in
            DispatchQueue.main.async {
                self.isTargeted = isTargeted
            }
        }
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: DropOverlayView, context: Context) {
        nsView.onDrop = onDrop
    }
}

class DropOverlayView: NSView {
    var onDrop: ((URL) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?

    // Allow mouse events to pass through to views below
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if hasMarkdownFile(sender) {
            onTargetChanged?(true)
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return hasMarkdownFile(sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetChanged?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }

        for url in items {
            if ["md", "markdown"].contains(url.pathExtension.lowercased()) {
                onDrop?(url)
                return true
            }
        }
        return false
    }

    private func hasMarkdownFile(_ info: NSDraggingInfo) -> Bool {
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }
        return items.contains { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
    }
}
