import SwiftUI
import AppKit

/// Invisible SwiftUI view that binds the hosting `NSWindow` to
/// `AppRuntimeState`'s persisted window frame.
///
/// Why this exists: SwiftUI's built-in window-state restoration for
/// `WindowGroup` only ever reapplies to the first window of a session (and
/// stores it under an auto-generated key derived from the view hierarchy,
/// which breaks whenever a modifier is added). LightMD opens a new window
/// per document, so the 2nd, 3rd, … window always came up at the default
/// size. This binder:
///
/// - applies the last saved frame on window appearance,
/// - cascades the new window if another LightMD window is already visible
///   so windows don't stack exactly on top of each other,
/// - observes `didResize` / `didMove` on its own window and writes the
///   latest frame back to `AppRuntimeState`.
///
/// Each binder only holds observers for its own window and removes them
/// when the view detaches or the window closes, so there are no ghost
/// observers.
struct WindowStateBinder: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = BinderView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        private weak var boundWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        @MainActor
        func bind(to window: NSWindow) {
            guard boundWindow !== window else { return }
            teardown()
            boundWindow = window
            applySavedFrame(to: window)
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { note in
                guard let w = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { AppRuntimeState.shared.saveWindowFrame(w.frame) }
            })
            observers.append(center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { note in
                guard let w = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { AppRuntimeState.shared.saveWindowFrame(w.frame) }
            })
        }

        func teardown() {
            let center = NotificationCenter.default
            for obs in observers { center.removeObserver(obs) }
            observers.removeAll()
            boundWindow = nil
        }

        @MainActor
        private func applySavedFrame(to window: NSWindow) {
            guard let saved = AppRuntimeState.shared.savedWindowFrame() else { return }
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? saved

            // Start from the saved size; position is chosen next.
            var frame = NSRect(origin: saved.origin, size: saved.size)

            // Cascade off of any other visible LightMD document window so
            // successive opens don't land exactly on top of each other.
            let siblings = NSApp.windows.filter {
                $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
            }
            if let reference = siblings.max(by: { $0.orderedIndex < $1.orderedIndex }) {
                let offset: CGFloat = 24
                frame.origin = NSPoint(
                    x: reference.frame.origin.x + offset,
                    y: reference.frame.origin.y - offset
                )
            }

            // Clamp into the visible frame so cascading off-screen is impossible.
            frame.size.width = min(frame.size.width, visible.width)
            frame.size.height = min(frame.size.height, visible.height)
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }

            window.setFrame(frame, display: true)
        }
    }

    private final class BinderView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            coordinator?.bind(to: window)
        }
    }
}

private extension NSWindow {
    /// Convenience for ordering — higher means more recently ordered to the
    /// front. Used to pick the "most recent sibling" for cascading.
    var orderedIndex: Int {
        NSApp.windows.firstIndex(of: self) ?? .max
    }
}
