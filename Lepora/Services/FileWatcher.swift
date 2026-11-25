import Foundation

final class FileWatcher: @unchecked Sendable {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.leo.lepora.filewatcher", qos: .utility)

    func watch(url: URL, onChange: @escaping @Sendable () -> Void) {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        src.setEventHandler {
            onChange()
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        self.source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    deinit {
        stop()
    }
}
