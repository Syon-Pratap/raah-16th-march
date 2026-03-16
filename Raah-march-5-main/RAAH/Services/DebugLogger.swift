import Foundation

/// Lightweight in-app log collector. Tap the version number 5× in Settings to open.
final class DebugLogger {
    static let shared = DebugLogger()
    private init() {}

    private(set) var entries: [Entry] = []
    private let lock = NSLock()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let tag: String
        let message: String

        var formatted: String {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss.SSS"
            return "[\(fmt.string(from: timestamp))] [\(tag)] \(message)"
        }
    }

    func log(_ tag: String, _ message: String) {
        let entry = Entry(timestamp: Date(), tag: tag, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > 200 { entries.removeFirst() }
        lock.unlock()
        print("[\(tag)] \(message)")  // still prints to Xcode console
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    var fullLog: String {
        lock.lock()
        let result = entries.map { $0.formatted }.joined(separator: "\n")
        lock.unlock()
        return result.isEmpty ? "No logs yet." : result
    }
}

// Convenience global
func dlog(_ tag: String, _ message: String) {
    DebugLogger.shared.log(tag, message)
}
