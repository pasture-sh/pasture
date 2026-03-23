import Foundation
import os.log

private let log = Logger(subsystem: "com.amrith.PastureHelper", category: "BackupManager")

actor BackupManager {
    static let shared = BackupManager()

    private let base = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Pasture")

    func write(filename: String, content: String) {
        let target = base.appendingPathComponent(filename).standardized

        // Reject writes that resolve outside ~/Documents/Pasture/ (path traversal guard)
        guard target.path.hasPrefix(base.standardized.path + "/") else {
            log.error("Backup rejected: '\(filename)' resolves outside the Pasture directory.")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            log.error("Backup write failed for '\(filename)': \(error.localizedDescription)")
        }
    }
}
