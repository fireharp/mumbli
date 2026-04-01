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

    private var hasRecording: Bool { entry.recordingFilename != nil }

    var body: some View {
        Button(action: { entry.isFailed ? retryEntry() : copyEntry() }) {
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
