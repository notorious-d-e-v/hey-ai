import Foundation

/// Appends timestamped lines to ~/Library/Logs/HeyAI/heyai.log. Only wake events,
/// actions and errors are logged — never the running transcript.
enum Log {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HeyAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("heyai.log")
    }()

    private static let queue = DispatchQueue(label: "heyai.log")
    private static let formatter = ISO8601DateFormatter()
    private static let maxBytes = 2_000_000

    static func info(_ message: String) {
        let date = Date()
        queue.async {
            let line = "\(formatter.string(from: date)) \(message)\n"
            FileHandle.standardError.write(Data(line.utf8))
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > maxBytes { try? FileManager.default.removeItem(at: url) }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
