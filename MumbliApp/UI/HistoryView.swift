import SwiftUI

/// SwiftUI view displaying dictation history entries in a scrollable list.
struct HistoryView: View {
    @ObservedObject var historyManager: HistoryManager

    var body: some View {
        VStack(spacing: 0) {
            if historyManager.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(historyManager.entries) { entry in
                            HistoryEntryRow(entry: entry, historyManager: historyManager, onRetry: { entry in
                                NotificationCenter.default.post(
                                    name: .mumbliRetryDictation,
                                    object: nil,
                                    userInfo: ["entryID": entry.id.uuidString, "recordingFilename": entry.recordingFilename ?? ""]
                                )
                            })
                            .accessibilityIdentifier("mumbli-history-entry")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("mumbli-history-list")
                .frame(maxHeight: 300)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                // Soft radial glow behind icon
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(0.1),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(0.5),
                                Color(nsColor: .systemBlue).opacity(0.35),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("No dictations yet")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Text("Hold **Fn** to start dictating")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .accessibilityIdentifier("mumbli-history-empty")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// A single row in the history list with hover state and smooth copy feedback.
@MainActor
struct HistoryEntryRow: View {
    let entry: DictationEntry
    let historyManager: HistoryManager
    var onRetry: ((DictationEntry) -> Void)?

    @State private var showCheckmark = false
    @State private var isHovered = false
    @State private var isRetrying = false

    /// Mirrors the "Show timing details" setting; the popover redraws on change.
    @AppStorage("showEntryTelemetry") private var showTelemetry = true

    private var hasRecording: Bool { entry.recordingFilename != nil }

    /// Telemetry is only shown for successful entries that actually carry metrics —
    /// entries dictated before telemetry was persisted simply keep the old layout.
    private var telemetry: PipelineMetrics? {
        guard showTelemetry, !entry.isFailed else { return nil }
        return entry.metrics
    }

    var body: some View {
        Button(action: { entry.isFailed ? retryEntry() : copyEntry() }) {
            VStack(alignment: .leading, spacing: 0) {
                mainRow
                if let telemetry {
                    TelemetryStrip(metrics: telemetry, receiptCommitment: entry.receiptCommitment)
                        .padding(.top, 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(entry.isFailed
                        ? Color(nsColor: .systemRed).opacity(isHovered ? 0.08 : 0.04)
                        : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        entry.isFailed
                            ? Color(nsColor: .systemRed).opacity(0.12)
                            : (isHovered ? Color.primary.opacity(0.04) : Color.clear),
                        lineWidth: 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
                // Recording indicator
                if hasRecording {
                    Image(systemName: entry.isFailed ? "exclamationmark.circle.fill" : "waveform.circle")
                        .font(.system(size: 13))
                        .foregroundColor(entry.isFailed ? Color(nsColor: .systemRed) : Color(nsColor: .systemTeal).opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 4) {
                    if entry.isFailed {
                        Text("Transcription failed — tap to retry")
                            .lineLimit(1)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(nsColor: .systemRed).opacity(0.85))
                    } else {
                        Text(entry.text)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.primary)
                    }

                    Text(entry.timestamp.relativeFormatted())
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }

                Spacer(minLength: 4)

                ZStack {
                    if entry.isFailed {
                        // Retry spinner or arrow
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(nsColor: .systemOrange))
                                .opacity(isHovered ? 1 : 0.6)
                        }
                    } else {
                        // Copy icon (shown on hover, hidden when checkmark is shown)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .opacity(isHovered && !showCheckmark ? 1 : 0)
                            .scaleEffect(isHovered && !showCheckmark ? 1 : 0.8)

                        // Checkmark (shown after copy)
                        if showCheckmark {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(nsColor: .systemGreen),
                                            Color(nsColor: .systemTeal),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .font(.system(size: 14))
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                                .accessibilityIdentifier("mumbli-history-checkmark")
                        }
                    }
                }
                .frame(width: 20)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
    }

    private func copyEntry() {
        historyManager.copyToClipboard(entry)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            showCheckmark = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCheckmark = false
            }
        }
    }

    private func retryEntry() {
        guard !isRetrying else { return }
        isRetrying = true
        onRetry?(entry)
    }
}

// MARK: - Per-entry telemetry

/// Condensed pipeline telemetry for one dictation: a proportional stage bar, the
/// per-stage timings, and provenance (model, audio length, signed receipt).
private struct TelemetryStrip: View {
    let metrics: PipelineMetrics
    let receiptCommitment: String?

    private static let sttColor = Color(nsColor: .systemBlue)
    private static let polishColor = Color(nsColor: .systemPurple)
    private static let injectColor = Color(nsColor: .systemTeal)

    /// Negative values mean the stage never ran (PipelineTimer returns -1 for a
    /// missing mark), so clamp before using them for bar widths.
    private func stage(_ value: Double) -> Double { max(value, 0) }

    private var isSlow: Bool { metrics.totalMs >= PipelineMetrics.slowThresholdMs }

    private var totalLabel: String {
        metrics.totalMs >= 1000
            ? String(format: "%.2fs", metrics.totalMs / 1000)
            : String(format: "%.0fms", metrics.totalMs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            stageBar
            HStack(spacing: 4) {
                Text("stt \(Int(stage(metrics.sttMs)))")
                Text("·")
                Text("polish \(Int(stage(metrics.polishMs)))")
                Text("·")
                Text("inject \(Int(stage(metrics.injectMs)))")
                Spacer(minLength: 4)
                Text(totalLabel)
                    .fontWeight(.medium)
                    .foregroundColor(isSlow ? Color(nsColor: .systemOrange) : .secondary)
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))

            HStack(spacing: 4) {
                Text(metrics.shortPolishModel)
                Text("·")
                Text(String(format: "%.1fs audio", metrics.audioDurationSec))
                if let receiptCommitment {
                    Text("·")
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Color(nsColor: .systemGreen).opacity(0.8))
                    Text(receiptCommitment.prefix(4) + "…" + receiptCommitment.suffix(4))
                        .font(.system(size: 9.5, design: .monospaced))
                }
            }
            .font(.system(size: 10))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .lineLimit(1)
        }
        .accessibilityIdentifier("mumbli-history-telemetry")
    }

    private var stageBar: some View {
        GeometryReader { geo in
            let stt = stage(metrics.sttMs)
            let polish = stage(metrics.polishMs)
            let inject = stage(metrics.injectMs)
            let sum = max(stt + polish + inject, 1)
            // Width is apportioned by measured stage time; gaps come out of the total
            // so the bar never overflows its row.
            let usable = max(geo.size.width - 4, 1)
            HStack(spacing: 2) {
                Capsule().fill(Self.sttColor.opacity(0.75))
                    .frame(width: usable * stt / sum)
                Capsule().fill(Self.polishColor.opacity(0.75))
                    .frame(width: usable * polish / sum)
                Capsule().fill(Self.injectColor.opacity(0.75))
                    .frame(width: usable * inject / sum)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Date Formatting

extension Date {
    /// Format date as a relative string (e.g., "2m ago", "1h ago", "Yesterday").
    func relativeFormatted() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: self)
        }
    }
}
