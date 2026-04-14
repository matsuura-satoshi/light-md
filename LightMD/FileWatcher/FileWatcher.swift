import Foundation

@MainActor
class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var rewatchWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.1
    private var currentURL: URL?

    var onChange: (@MainActor () -> Void)?

    func watch(url: URL) {
        stop()
        currentURL = url

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                let flags = source.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    // Atomic-save editors (vim, VSCode, Obsidian, ...) replace
                    // the file via rename, unlinking the old inode our fd is
                    // bound to. Re-open against the path to track the new one.
                    self.scheduleRewatch()
                    return
                }
                self.debounceAndNotify()
            }
        }

        // Bind fd by value so each source's cancel handler closes the exact
        // descriptor it was created with — a shared property would get
        // overwritten by the next watch() and we'd close the wrong fd.
        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        rewatchWorkItem?.cancel()
        rewatchWorkItem = nil
    }

    private func scheduleRewatch() {
        guard let url = currentURL else { return }
        rewatchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.watch(url: url)
                self.debounceAndNotify()
            }
        }
        rewatchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
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
        source?.cancel()
    }
}
