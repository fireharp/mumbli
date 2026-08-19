import Foundation

/// One-time background migration of legacy WAV recordings to whichever
/// compressed format RecordingManager currently targets (Opus, or its AAC/WAV
/// fallback — see RecordingManager's doc comment for why Opus is the default).
///
/// Runs once per launch, after HistoryManager loads its entries. Sequential
/// and low-priority: this exists to shrink a backlog that took months to
/// accumulate, not to race anything — there is no user-facing wait on it.
///
/// Resumable by construction. The remaining `.wav` files in the recordings
/// directory ARE the work list: nothing is tracked separately, so a
/// mid-migration app quit just means fewer files left to process next
/// launch. `RecordingManager.migrateWAV` is itself idempotent (reuses a
/// verified destination file from an interrupted prior attempt, discards and
/// redoes an unverified one), so re-running against a partially-migrated
/// directory is safe.
enum RecordingMigrator {
    static func migrateIfNeeded(historyManager: HistoryManager) {
        let wavURLs = RecordingManager.shared.listRecordings().filter { $0.pathExtension.lowercased() == "wav" }
        guard !wavURLs.isEmpty else { return }

        NSLog("[RecordingMigrator] Starting backlog migration: %d WAV files", wavURLs.count)
        Task.detached(priority: .utility) {
            var migrated = 0
            var failed = 0
            for wavURL in wavURLs {
                guard let newURL = RecordingManager.shared.migrateWAV(at: wavURL) else {
                    failed += 1
                    continue
                }

                let oldFilename = wavURL.lastPathComponent
                let newFilename = newURL.lastPathComponent
                await MainActor.run {
                    historyManager.renameRecording(from: oldFilename, to: newFilename)
                }

                // Only delete the source once the replacement is confirmed on
                // disk and history points at it — never leave a dictation
                // referencing a file that doesn't exist.
                try? FileManager.default.removeItem(at: wavURL)
                migrated += 1
            }
            NSLog("[RecordingMigrator] Backlog migration finished: %d migrated, %d left as WAV (unencodable or already failing)", migrated, failed)
        }
    }
}
