import Foundation

/// Coalesces editor keystrokes, performs atomic writes off the UI thread, and keeps
/// the last scheduled snapshot alive even if its view controller is closed.
final class BufferedTextWriter {
    private final class Job {
        let text: String
        let url: URL
        let onError: (Error) -> Void
        private let lock = NSLock()
        private var cancelled = false
        init(text: String, url: URL, onError: @escaping (Error) -> Void) { self.text = text; self.url = url; self.onError = onError }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        @discardableResult func write(force: Bool = false) -> Result<Void, Error> {
            lock.lock(); let shouldWrite = force || !cancelled; lock.unlock()
            guard shouldWrite else { return .success(Void()) }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("filesChanged"), object: nil) }
                return .success(Void())
            } catch { DispatchQueue.main.async { self.onError(error) }; return .failure(error) }
        }
    }
    private static let queue = DispatchQueue(label: "extenddesk.notes.writer", qos: .utility)
    private var pending: Job?
    /// Invoke from the main thread with an immutable text snapshot.
    func schedule(_ text: String, to url: URL, onError: @escaping (Error) -> Void) {
        pending?.cancel()
        let job = Job(text: text, url: url, onError: onError); pending = job
        Self.queue.asyncAfter(deadline: .now() + 0.35) { job.write() }
    }
    /// Flush before changing a note's file path, or when the app backgrounds.
    func flush(completion: ((Result<Void, Error>) -> Void)? = nil) {
        let job = pending; pending = nil; job?.cancel()
        Self.queue.async { let result = job?.write(force: true) ?? .success(Void()); if let completion { DispatchQueue.main.async { completion(result) } } }
    }
}
