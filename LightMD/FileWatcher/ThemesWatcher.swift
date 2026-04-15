import Foundation

/// Watches the themes directory for add/delete/rename events and (optionally)
/// a single active theme CSS file for write/rename/delete events.
///
/// Pattern mirrors `FileWatcher.swift`: `DispatchSource.makeFileSystemObjectSource`
/// on a descriptor opened with `O_EVTONLY`. Atomic-save editors replace the file
/// via rename, so rename/delete triggers a re-open of the same path.
@MainActor
class ThemesWatcher {
    var onThemesListChanged: (@MainActor () -> Void)?
    var onActiveThemeChanged: (@MainActor () -> Void)?

    private var folderSource: DispatchSourceFileSystemObject?
    private var folderDebounce: DispatchWorkItem?

    private var activeSource: DispatchSourceFileSystemObject?
    private var activeDebounce: DispatchWorkItem?
    private var activeRewatch: DispatchWorkItem?
    private var activeURL: URL?

    private let debounceInterval: TimeInterval = 0.15

    // MARK: - Folder watching

    func startWatchingFolder(_ dir: URL) {
        stopFolderWatch()

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.debounceFolder()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        folderSource = source
    }

    private func debounceFolder() {
        folderDebounce?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.onThemesListChanged?()
            }
        }
        folderDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func stopFolderWatch() {
        folderSource?.cancel()
        folderSource = nil
        folderDebounce?.cancel()
        folderDebounce = nil
    }

    // MARK: - Active theme file watching

    /// Binds the watcher to a specific theme CSS file. Pass `nil` when the active
    /// theme is a builtin (which lives in the read-only bundle and can't change).
    func setActiveThemeFile(_ url: URL?) {
        stopActiveWatch()
        activeURL = url
        guard let url else { return }
        openActiveWatch(url: url)
    }

    private func openActiveWatch(url: URL) {
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
                    // Atomic save: editor replaces the file, unlinking the inode
                    // our fd is bound to. Re-open against the path.
                    self.scheduleActiveRewatch()
                    return
                }
                self.debounceActive()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        activeSource = source
    }

    private func scheduleActiveRewatch() {
        guard let url = activeURL else { return }
        activeRewatch?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.activeSource?.cancel()
                self.activeSource = nil
                self.openActiveWatch(url: url)
                self.debounceActive()
            }
        }
        activeRewatch = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func debounceActive() {
        activeDebounce?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.onActiveThemeChanged?()
            }
        }
        activeDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func stopActiveWatch() {
        activeSource?.cancel()
        activeSource = nil
        activeDebounce?.cancel()
        activeDebounce = nil
        activeRewatch?.cancel()
        activeRewatch = nil
        activeURL = nil
    }

    func stop() {
        stopFolderWatch()
        stopActiveWatch()
    }

    nonisolated deinit {
        folderSource?.cancel()
        activeSource?.cancel()
    }
}
