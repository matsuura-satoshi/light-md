import Foundation

@MainActor
class PendingFileQueue {
    static let shared = PendingFileQueue()

    private var urls: [URL] = []

    func enqueue(_ url: URL) {
        urls.append(url)
    }

    func dequeue() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}
