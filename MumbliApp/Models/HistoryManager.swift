import Foundation
import AppKit

/// A single dictation history entry.
struct DictationEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(text: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
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
    func addEntry(text: String) {
        let entry = DictationEntry(text: text)
        entries.insert(entry, at: 0)
        saveEntries()
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
