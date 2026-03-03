import Foundation

/// A simple service to watch a directory for changes using DispatchSourceFileSystemObject.
/// Not actor-isolated; safe to use from any thread. The callback is invoked on the queue provided (default: main).
/// Changes are debounced (150 ms) so that bulk file operations (e.g. unzip, copy of many files)
/// trigger only a single reload rather than one per file-system event.
final class DirectoryWatcherService {
    private var directoryFileDescriptor: CInt?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private let watcherQueue: DispatchQueue
    private let url: URL
    private let onChange: () -> Void
    private var debounceWorkItem: DispatchWorkItem?

    /// - Parameters:
    ///   - url: The directory URL to watch.
    ///   - queue: The queue on which to call the onChange handler (default: main).
    ///   - onChange: Handler called when the directory changes.
    init(url: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        self.watcherQueue = queue
        startWatching()
    }

    private func startWatching() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: watcherQueue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleCallback()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryFileDescriptor {
                close(fd)
            }
            self?.directoryFileDescriptor = nil
        }

        directoryWatcher = source
        source.resume()
    }

    /// Coalesces rapid bursts of FS events into a single callback after 150 ms of silence.
    private func scheduleCallback() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = item
        watcherQueue.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    deinit {
        debounceWorkItem?.cancel()
        directoryWatcher?.cancel()
        if let fd = directoryFileDescriptor {
            close(fd)
        }
    }
}
