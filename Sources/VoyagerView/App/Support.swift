import Foundation
import os

/// Logs to the unified log (subsystem `com.voyagerview.app`) and to stderr, so `swift run` shows it too.
/// `log stream --predicate 'subsystem == "com.voyagerview.app"'` works for the bundled app.
enum Log {
    private static let logger = Logger(subsystem: "com.voyagerview.app", category: "app")
    private static let start = Date()

    static func info(_ message: @autoclosure () -> String) {
        let m = message()
        logger.notice("\(m, privacy: .public)")
        write(m)
    }

    static func error(_ message: @autoclosure () -> String) {
        let m = message()
        logger.error("\(m, privacy: .public)")
        write("ERROR " + m)
    }

    private static func write(_ m: String) {
        let now = Date()
        let t = String(format: "%9.3f", now.timeIntervalSince(start))
        let line = Data("[\(t)] \(m)\n".utf8)
        FileHandle.standardError.write(line)
        fileQueue.async {
            let stamp = Data("\(stampFormatter.string(from: now)) ".utf8)
            fileHandle?.write(stamp + line)
        }
    }

    static let fileURL: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/VoyagerView.log")
    private static let fileQueue = DispatchQueue(label: "com.voyagerview.log", qos: .utility)
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    /// ~/Library/Logs/VoyagerView.log, truncated at launch when over 2 MB.
    private static let fileHandle: FileHandle? = {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > 2_000_000 {
            try? fm.removeItem(at: fileURL)
        }
        if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: fileURL)
        _ = try? h?.seekToEnd()
        return h
    }()
}

enum AppPaths {
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VoyagerView", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var config: URL { supportDir.appendingPathComponent("config.json") }
    static var layoutCache: URL { supportDir.appendingPathComponent("layout.json") }
}
