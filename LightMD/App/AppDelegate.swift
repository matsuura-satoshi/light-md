import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        DispatchQueue.main.async {
            self.setupTabMenuItem()
        }
    }

    private func setupTabMenuItem() {
        guard let mainMenu = NSApp.mainMenu else { return }
        // Find the File menu
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            // Look for the menu containing "New Window" (File menu)
            let hasNewWindow = submenu.items.contains { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }
            if hasNewWindow {
                let tabItem = NSMenuItem(
                    title: "New Tab",
                    action: #selector(NSResponder.newWindowForTab(_:)),
                    keyEquivalent: "t"
                )
                tabItem.keyEquivalentModifierMask = .command
                // Insert after "New Window"
                if let idx = submenu.items.firstIndex(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }) {
                    submenu.insertItem(tabItem, at: idx + 1)
                } else {
                    submenu.insertItem(tabItem, at: 0)
                }
                break
            }
        }
    }
}
