import Foundation

extension Notification.Name {
    static let didEnqueuePendingFile = Notification.Name("LightMD.pendingFileQueue.enqueue")
}

@MainActor
class PendingFileQueue {
    static let shared = PendingFileQueue()

    private var urls: [URL] = []

    func enqueue(_ url: URL) {
        // Dedupe so onOpenURL + application(_:open:) firing for the same URL
        // on cold launch doesn't cause the file to be opened twice.
        guard !urls.contains(url) else { return }
        urls.append(url)
        NotificationCenter.default.post(name: .didEnqueuePendingFile, object: nil)
    }

    func dequeue() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}
