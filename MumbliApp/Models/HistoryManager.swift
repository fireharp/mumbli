import Foundation
import AppKit

/// A single dictation history entry.
struct DictationEntry: Codable, Identifiable {
    let id: UUID
    var text: String
    let timestamp: Date
    /// Relative filename of the saved WAV recording (e.g. "2026-04-01_134652.wav"), if any.
    var recordingFilename: String?
    /// True when STT failed and the entry is a placeholder awaiting reprocessing.
    var isFailed: Bool

    init(text: String, timestamp: Date = Date(), recordingFilename: String? = nil, isFailed: Bool = false) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.recordingFilename = recordingFilename
        self.isFailed = isFailed
    }

    // Backwards-compatible decoding: missing keys get defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        recordingFilename = try c.decodeIfPresent(String.self, forKey: .recordingFilename)
        isFailed = try c.decodeIfPresent(Bool.self, forKey: .isFailed) ?? false
    }
}

/// Manages local dictation history: persistence, retrieval, and clipboard operations.
@MainActor
final class HistoryManager: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mumbliDir = appSupport.appendingPathComponent("Mumbli", isDirectory: true)
        try? FileManager.default.createDirectory(at: mumbliDir, withIntermediateDirectories: true)
        self.fileURL = mumbliDir.appendingPathComponent("history.json")
        loadEntries()
    }

    /// Add a new dictation entry and persist.
    func addEntry(text: String, recordingFilename: String? = nil) {
        let entry = DictationEntry(text: text, recordingFilename: recordingFilename)
        entries.insert(entry, at: 0)
        saveEntries()
    }

    /// Add a failed entry placeholder (recording saved, transcription failed).
    func addFailedEntry(recordingFilename: String) {
        let entry = DictationEntry(text: "", recordingFilename: recordingFilename, isFailed: true)
        entries.insert(entry, at: 0)
        saveEntries()
    }

    /// Mark a previously failed entry as successful with new text.
    func resolveEntry(id: UUID, text: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].text = text
        entries[idx].isFailed = false
        saveEntries()
    }

    /// Full URL for a recording filename.
    static func recordingURL(for filename: String) -> URL {
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
    }

    /// Clear all history.
    func clearAll() {
        entries.removeAll()
        saveEntries()
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
