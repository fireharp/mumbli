import Foundation

/// Append-only JSONL store for signed usage receipts.
final class UsageReceiptStore {
    static let shared = UsageReceiptStore()

    private let queue = DispatchQueue(label: "com.mumbli.proof.receipts", qos: .utility)
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private init() {
        try? FileManager.default.createDirectory(
            at: ProofOfUseConfig.proofDirectory,
            withIntermediateDirectories: true
        )
    }

    func append(_ item: PouReceiptWithCommitment) throws {
        let line = try encoder.encode(item)
        var payload = line
        payload.append(UInt8(ascii: "\n"))
        try queue.sync {
            if FileManager.default.fileExists(atPath: ProofOfUseConfig.receiptsFile.path) {
                let handle = try FileHandle(forWritingTo: ProofOfUseConfig.receiptsFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            } else {
                try payload.write(to: ProofOfUseConfig.receiptsFile, options: .atomic)
            }
        }
    }

    func receiptCount() -> Int {
        queue.sync {
            guard let data = try? String(contentsOf: ProofOfUseConfig.receiptsFile, encoding: .utf8) else {
                return 0
            }
            return data.split(separator: "\n", omittingEmptySubsequences: true).count
        }
    }
}
