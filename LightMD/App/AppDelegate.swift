import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+T → new tab
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.charactersIgnoringModifiers == "t" {
                NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
                return nil  // consume the event
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
