import Foundation

/// Precise timing for each stage of the dictation pipeline.
/// Uses CFAbsoluteTimeGetCurrent() for sub-millisecond precision.
final class PipelineTimer {
    private var marks: [(String, CFAbsoluteTime)] = []

    init() {
        mark("pipeline_start")
    }

    func mark(_ label: String) {
        marks.append((label, CFAbsoluteTimeGetCurrent()))
    }

    /// Elapsed time in milliseconds between two marks.
    func elapsed(from: String, to: String) -> Double {
        guard let start = marks.first(where: { $0.0 == from })?.1,
              let end = marks.first(where: { $0.0 == to })?.1 else {
            return -1
        }
        return (end - start) * 1000.0
    }

    /// Total elapsed since pipeline_start.
    func totalElapsed() -> Double {
        guard let start = marks.first?.1 else { return -1 }
        return (CFAbsoluteTimeGetCurrent() - start) * 1000.0
    }

    func buildMetrics(
        audioBytes: Int,
        audioDurationSec: Double,
        sttProvider: String,
        polishModel: String
    ) -> PipelineMetrics {
        PipelineMetrics(
            audioBytes: audioBytes,
            audioDurationSec: audioDurationSec,
            sttMs: elapsed(from: "stt_start", to: "stt_end"),
            polishMs: elapsed(from: "polish_start", to: "polish_end"),
            injectMs: elapsed(from: "inject_start", to: "inject_end"),
            totalMs: totalElapsed(),
            sttProvider: sttProvider,
            polishModel: polishModel,
            timestamp: Date()
        )
    }
}

struct PipelineMetrics {
    let audioBytes: Int
    let audioDurationSec: Double
    let sttMs: Double
    let polishMs: Double
    let injectMs: Double
    let totalMs: Double
    let sttProvider: String
    let polishModel: String
    let timestamp: Date

    var jsonLine: String {
        let iso = ISO8601DateFormatter().string(from: timestamp)
        return "[METRICS] {\"audio_bytes\":\(audioBytes),\"audio_duration_s\":\(String(format: "%.2f", audioDurationSec)),\"stt_ms\":\(String(format: "%.1f", sttMs)),\"polish_ms\":\(String(format: "%.1f", polishMs)),\"inject_ms\":\(String(format: "%.1f", injectMs)),\"total_ms\":\(String(format: "%.1f", totalMs)),\"stt_provider\":\"\(sttProvider)\",\"polish_model\":\"\(polishModel)\",\"timestamp\":\"\(iso)\"}"
    }
}
