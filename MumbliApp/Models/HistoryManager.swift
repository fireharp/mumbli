import Foundation
import AppKit

/// A single dictation history entry.
struct DictationEntry: Codable, Identifiable {
    let id: UUID
    var text: String
    let timestamp: Date
    /// Relative filename of the saved recording (e.g. "2026-04-01_134652.caf" —
    /// or ".wav"/".m4a" for entries predating Opus or the AAC/WAV fallback
    /// tiers), if any.
    var recordingFilename: String?
    /// True when STT failed and the entry is a placeholder awaiting reprocessing.
    var isFailed: Bool
    /// Per-stage pipeline telemetry for this dictation. Nil for entries recorded
    /// before telemetry was persisted, and for failed entries.
    var metrics: PipelineMetrics?
    /// Commitment hash of the signed proof-of-use receipt covering this dictation,
    /// i.e. the local pointer into receipts.jsonl. Nil when proof-of-use is off.
    ///
    /// Only the hash is stored here — the receipt body itself stays deliberately
    /// content-free so it reveals nothing about what was dictated.
    var receiptCommitment: String?

    init(text: String, timestamp: Date = Date(), recordingFilename: String? = nil, isFailed: Bool = false,
         metrics: PipelineMetrics? = nil, receiptCommitment: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.recordingFilename = recordingFilename
        self.isFailed = isFailed
        self.metrics = metrics
        self.receiptCommitment = receiptCommitment
    }

    // Backwards-compatible decoding: missing keys get defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        recordingFilename = try c.decodeIfPresent(String.self, forKey: .recordingFilename)
        isFailed = try c.decodeIfPresent(Bool.self, forKey: .isFailed) ?? false
        metrics = try c.decodeIfPresent(PipelineMetrics.self, forKey: .metrics)
        receiptCommitment = try c.decodeIfPresent(String.self, forKey: .receiptCommitment)
    }
}

/// Manages local dictation history: persistence, retrieval, and clipboard operations.
@MainActor
final class HistoryManager: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []

    /// Total recorded audio across all history, in seconds. Nil until the one-time
    /// background backfill (below) finishes reading saved WAV files for entries that
    /// predate per-dictation telemetry — there can be thousands of those, so this is
    /// never computed synchronously on the main actor.
    @Published private(set) var totalDictatedSeconds: Double?

    private let fileURL: URL
    /// Per-file duration, keyed by recording filename, so a backfilled file is never
    /// read from disk twice.
    private var recordingDurationCache: [String: Double] = [:]
    /// Duration deltas from addEntry/removeEntry that arrive before the initial
    /// backfill scan completes. The scan's snapshot is taken at its own start, so
    /// without this an entry added mid-scan would silently never be counted.
    private var pendingDurationDelta: Double = 0

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mumbliDir = appSupport.appendingPathComponent("Mumbli", isDirectory: true)
        try? FileManager.default.createDirectory(at: mumbliDir, withIntermediateDirectories: true)
        self.fileURL = mumbliDir.appendingPathComponent("history.json")
        loadEntries()
        backfillTotalDuration()
        RecordingMigrator.migrateIfNeeded(historyManager: self)
    }

    /// Add a new dictation entry and persist. Returns the new entry's id so callers
    /// can attach a proof-of-use receipt once signing completes asynchronously.
    @discardableResult
    func addEntry(text: String, recordingFilename: String? = nil, metrics: PipelineMetrics? = nil) -> UUID {
        let entry = DictationEntry(text: text, recordingFilename: recordingFilename, metrics: metrics)
        entries.insert(entry, at: 0)
        saveEntries()
        addToTotalDuration(entry)
        return entry.id
    }

    /// Attach a signed receipt's commitment hash to an existing entry.
    func attachReceipt(id: UUID, commitment: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].receiptCommitment = commitment
        saveEntries()
    }

    /// Add a failed entry placeholder (recording saved, transcription failed).
    func addFailedEntry(recordingFilename: String) {
        let entry = DictationEntry(text: "", recordingFilename: recordingFilename, isFailed: true)
        entries.insert(entry, at: 0)
        saveEntries()
        addToTotalDuration(entry)
    }

    /// Mark a previously failed entry as successful with new text.
    func resolveEntry(id: UUID, text: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].text = text
        entries[idx].isFailed = false
        saveEntries()
    }

    /// Repoint every entry currently referencing `oldFilename` at `newFilename`.
    /// Used by RecordingMigrator once a WAV has been re-encoded and verified —
    /// no-op if nothing in history references the old name (e.g. an orphaned
    /// benchmark recording with no history entry at all).
    func renameRecording(from oldFilename: String, to newFilename: String) {
        var changed = false
        for idx in entries.indices where entries[idx].recordingFilename == oldFilename {
            entries[idx].recordingFilename = newFilename
            changed = true
        }
        guard changed else { return }
        recordingDurationCache.removeValue(forKey: oldFilename)
        saveEntries()
    }

    /// Full URL for a recording filename. Not actor-isolated: also called from the
    /// background backfill scan.
    nonisolated static func recordingURL(for filename: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Mumbli/recordings/\(filename)")
    }

    /// Copy the full text of an entry to the system pasteboard.
    func copyToClipboard(_ entry: DictationEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
    }

    /// Remove a specific entry.
    func removeEntry(_ entry: DictationEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
        subtractFromTotalDuration(entry)
    }

    /// Clear all history.
    func clearAll() {
        entries.removeAll()
        saveEntries()
        recordingDurationCache.removeAll()
        pendingDurationDelta = 0
        totalDictatedSeconds = 0
    }

    // MARK: - Total duration backfill

    /// One-time background scan that backfills total audio duration for entries
    /// recorded before PipelineMetrics existed, by reading each saved recording's
    /// duration through RecordingManager (a cheap header read for WAV, a decode
    /// for compressed formats — see RecordingManager's doc comment). Measured at
    /// ~0.7s for 5,000+ WAV files — fine off the main actor, not fine as part of
    /// rendering a popover.
    private func backfillTotalDuration() {
        let snapshot = entries.map { ($0.metrics?.audioDurationSec, $0.recordingFilename) }
        Task.detached(priority: .utility) { [weak self] in
            let (total, cache): (Double, [String: Double]) = {
                var total = 0.0
                var cache: [String: Double] = [:]
                for (metricsSeconds, filename) in snapshot {
                    if let metricsSeconds {
                        total += metricsSeconds
                    } else if let filename, let seconds = RecordingManager.shared.durationSeconds(filename: filename) {
                        total += seconds
                        cache[filename] = seconds
                    }
                }
                return (total, cache)
            }()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.recordingDurationCache.merge(cache) { _, new in new }
                self.totalDictatedSeconds = total + self.pendingDurationDelta
                self.pendingDurationDelta = 0
            }
        }
    }

    private func durationSeconds(for entry: DictationEntry) -> Double {
        if let metrics = entry.metrics { return metrics.audioDurationSec }
        guard let filename = entry.recordingFilename else { return 0 }
        if let cached = recordingDurationCache[filename] { return cached }
        let seconds = RecordingManager.shared.durationSeconds(filename: filename) ?? 0
        recordingDurationCache[filename] = seconds
        return seconds
    }

    private func addToTotalDuration(_ entry: DictationEntry) {
        let seconds = durationSeconds(for: entry)
        if totalDictatedSeconds != nil {
            totalDictatedSeconds! += seconds
        } else {
            pendingDurationDelta += seconds
        }
    }

    private func subtractFromTotalDuration(_ entry: DictationEntry) {
        let seconds = durationSeconds(for: entry)
        if totalDictatedSeconds != nil {
            totalDictatedSeconds! -= seconds
        } else {
            pendingDurationDelta -= seconds
        }
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([DictationEntry].self, from: data)
        } catch {
            print("HistoryManager: Failed to load history: \(error)")
        }
    }

    private func saveEntries() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("HistoryManager: Failed to save history: \(error)")
        }
    }
}
