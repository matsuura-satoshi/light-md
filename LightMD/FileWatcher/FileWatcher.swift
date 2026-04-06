import Foundation

@MainActor
class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.1
    private var currentURL: URL?

    var onChange: (@MainActor () -> Void)?

    func watch(url: URL) {
        stop()
        currentURL = url

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let flags = source.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    let savedURL = self.currentURL
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, let url = savedURL else { return }
                            self.watch(url: url)
                            self.debounceAndNotify()
                        }
                    }
                    return
                }
                self.debounceAndNotify()
            }
        }

        source.setCancelHandler { [weak self] in
            MainActor.assumeIsolated {
                if let fd = self?.fileDescriptor, fd >= 0 {
                    close(fd)
                }
            }
        }

        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    private func debounceAndNotify() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    nonisolated deinit {
        // DispatchSource cancel is thread-safe
        source?.cancel()
    }
}
