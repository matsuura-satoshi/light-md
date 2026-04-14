import Foundation
import Observation

@MainActor
@Observable
class PendingFileQueue {
    static let shared = PendingFileQueue()

    private(set) var urls: [URL] = []

    func enqueue(_ url: URL) {
        urls.append(url)
    }

    func dequeue() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}
