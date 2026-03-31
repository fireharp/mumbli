import AppKit
import Combine
import SwiftUI

/// Controls the floating overlay window that shows a listening indicator during dictation.
@MainActor
final class OverlayController {
    private var window: NSWindow?
    private var dismissTimer: Timer?
    private var audioLevelProvider: AudioLevelProvider?
    private var audioLevelCancellable: AnyCancellable?
    private var overlayState: OverlayStateProvider?

    /// Show the overlay at center-bottom of main screen.
    /// - Parameters:
    ///   - audioCaptureManager: Optional audio capture manager to drive mic-reactive dots.
    ///   - mode: The activation mode, used to visually distinguish hold vs hands-free.
    func show(audioCaptureManager: AudioCaptureManager? = nil, mode: ActivationMode = .hold) {
        NSLog("[Overlay] show() called, mode=\(mode)")
        // Clean up any existing overlay immediately
        dismissTimer?.invalidate()
        dismissTimer = nil
        audioLevelCancellable?.cancel()
        window?.orderOut(nil)
        window = nil

        let audioProvider = AudioLevelProvider()
        self.audioLevelProvider = audioProvider

        let stateProvider = OverlayStateProvider()
        self.overlayState = stateProvider

        if let acm = audioCaptureManager {
            audioLevelCancellable = acm.$audioLevel
                .receive(on: RunLoop.main)
                .sink { [weak audioProvider] level in
                    audioProvider?.pushLevel(level)
                }
        }

        let hostingView = NSHostingView(rootView: OverlayRootView(audioLevelProvider: audioProvider, stateProvider: stateProvider, mode: mode))
        let frame = NSRect(x: 0, y: 0, width: 56, height: 56)
        hostingView.frame = frame

        // NSHostingView draws an opaque background by default, which shows as a
        // visible rectangle behind the rounded pill shape. To fix this:
        // 1. Wrap in a plain NSView with a transparent layer
        // 2. Force the hosting view's layer to be transparent
        // 3. Apply cornerRadius + masksToBounds on all layers
        let wrapper = NSView(frame: frame)
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = .clear
        wrapper.layer?.cornerRadius = 14
        wrapper.layer?.masksToBounds = true
        wrapper.addSubview(hostingView)

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.cornerRadius = 14
        hostingView.layer?.masksToBounds = true

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = wrapper
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setAccessibilityIdentifier("mumbli-overlay-window")
        window.alphaValue = 0

        // Position at center-bottom of main screen, 40px above bottom
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - window.frame.width / 2
            let y = screenFrame.origin.y + 40
            // Start 8px lower for slide-up animation
            window.setFrameOrigin(NSPoint(x: x, y: y - 8))
            NSLog("[Overlay] Positioned at (%.0f, %.0f) on screen %@", x, y, NSStringFromRect(screenFrame))

            window.orderFrontRegardless()

            // Slide up + fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
                window.animator().setFrameOrigin(NSPoint(x: x, y: y))
            }
        } else {
            let position = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: position.x + 8, y: position.y - window.frame.height - 8))
            NSLog("[Overlay] No main screen — fallback to mouse position")
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }
        }

        self.window = window
    }

    /// Switch the overlay to processing state (spinning indicator).
    /// The overlay stays visible until explicitly dismissed.
    func showProcessing() {
        NSLog("[Overlay] showProcessing() called")
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        overlayState?.isProcessing = true
    }

    /// Dismiss the overlay, optionally after a brief delay.
    func dismiss(afterDelay delay: TimeInterval = 0) {
        NSLog("[Overlay] dismiss(afterDelay: %.2f) called", delay)
        dismissTimer?.invalidate()
        if delay > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    self?.performDismiss()
                }
            }
        } else {
            performDismiss()
        }
    }

    private func performDismiss() {
        guard let window = window else { return }
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        let currentOrigin = window.frame.origin
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            // Slide down 4px during fade out (back toward bottom edge)
            window.animator().setFrameOrigin(NSPoint(x: currentOrigin.x, y: currentOrigin.y - 4))
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.audioLevelProvider = nil
            self?.overlayState = nil
        })
    }
}

// MARK: - Listening Indicator SwiftUI View

/// A compact listening indicator with 5 waveform bars that act as a VU meter.
/// Bar heights respond proportionally to audio level with center-outward stagger.
/// In hands-free mode, uses orange bars, a static orange border, and a red REC dot.
struct ListeningIndicatorView: View {
    @ObservedObject var audioLevelProvider: AudioLevelProvider
    let mode: ActivationMode

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 3
    private let restHeightOuter: CGFloat = 6
    private let restHeightCenter: CGFloat = 8
    private let maxHeight: CGFloat = 24
    /// Per-bar multipliers: center bar is tallest.
    private let multipliers: [CGFloat] = [0.6, 0.8, 1.0, 0.8, 0.6]
    /// Stagger delay order from center outward: center=0, inner=1, outer=2.
    private let staggerOrder: [Int] = [2, 1, 0, 1, 2]

    private var isHandsFree: Bool { mode == .handsFree }

    private var barColor: Color {
        isHandsFree ? .orange : .accentColor
    }

    private func restHeight(for index: Int) -> CGFloat {
        index == 2 ? restHeightCenter : restHeightOuter
    }

    /// Returns the animated height for a bar at the given index.
    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevelProvider.audioLevel)
        let rest = restHeight(for: index)
        return rest + (level * multipliers[index] * (maxHeight - rest))
    }

    /// Returns the opacity for a bar: 0.7 at rest, 1.0 at full level.
    private func barOpacity(for index: Int) -> Double {
        let level = Double(audioLevelProvider.audioLevel)
        return 0.7 + (level * multipliers[index] * 0.3)
    }

    /// Stagger delay: 15ms per step from center outward.
    private func staggerDelay(for index: Int) -> Double {
        Double(staggerOrder[index]) * 0.015
    }

    var body: some View {
        HStack(spacing: 0) {
            // Red REC dot for hands-free mode
            if isHandsFree {
                Circle()
                    .fill(Color.red)
                    .frame(width: 4, height: 4)
                    .opacity(0.8)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("mumbli-rec-dot")
            }

            HStack(spacing: barGap) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(barColor)
                        .frame(width: barWidth, height: barHeight(for: index))
                        .opacity(barOpacity(for: index))
                        .animation(
                            .spring(response: 0.10, dampingFraction: 0.75, blendDuration: 0.0)
                                .delay(staggerDelay(for: index)),
                            value: audioLevelProvider.audioLevel
                        )
                        .accessibilityIdentifier("mumbli-vu-bar-\(index)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isHandsFree
                            ? Color.orange.opacity(0.35)
                            : Color.primary.opacity(0.08),
                        lineWidth: isHandsFree ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .shadow(
            color: audioLevelProvider.audioLevel > 0.3
                ? barColor.opacity(Double(audioLevelProvider.audioLevel) * 0.25)
                : .black.opacity(0.12),
            radius: audioLevelProvider.audioLevel > 0.3 ? 8 : 12,
            x: 0,
            y: audioLevelProvider.audioLevel > 0.3 ? 0 : 4
        )
        .accessibilityIdentifier("mumbli-listening-indicator")
    }
}

/// Observable object that tracks whether the overlay is in listening or processing state.
class OverlayStateProvider: ObservableObject {
    @Published var isProcessing = false
}

/// Observable object that bridges audio level data to SwiftUI.
/// Maintains a circular buffer of recent audio levels for animation stagger.
class AudioLevelProvider: ObservableObject {
    @Published var audioLevel: Float = 0.0

    /// Circular buffer of the 3 most recent audio levels (newest at index 0).
    @Published var recentLevels: [Float] = [0.0, 0.0, 0.0]

    /// Call this on each audio tick to update the buffer.
    func pushLevel(_ level: Float) {
        audioLevel = level
        recentLevels[2] = recentLevels[1]
        recentLevels[1] = recentLevels[0]
        recentLevels[0] = level
    }
}

/// Root view that switches between listening and processing indicators.
struct OverlayRootView: View {
    @ObservedObject var audioLevelProvider: AudioLevelProvider
    @ObservedObject var stateProvider: OverlayStateProvider
    let mode: ActivationMode

    var body: some View {
        if stateProvider.isProcessing {
            ProcessingIndicatorView(wasHandsFree: mode == .handsFree)
                .transition(.opacity)
        } else {
            ListeningIndicatorView(audioLevelProvider: audioLevelProvider, mode: mode)
                .transition(.opacity)
        }
    }
}

/// A compact processing indicator that reuses the 5 waveform bars at rest height,
/// sweeping a highlight left-to-right as a loading animation.
/// Shown after Fn release while transcription + polishing API calls happen.
struct ProcessingIndicatorView: View {
    let wasHandsFree: Bool

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 3
    private let restHeights: [CGFloat] = [6, 6, 8, 6, 6]

    @State private var highlightedIndex: Int = 0
    @State private var cycleTimer: Timer?

    var body: some View {
        HStack(spacing: barGap) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index == highlightedIndex ? Color.accentColor : Color.secondary)
                    .frame(width: barWidth, height: restHeights[index])
                    .opacity(index == highlightedIndex ? 1.0 : 0.35)
                    .animation(.easeInOut(duration: 0.15), value: highlightedIndex)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityIdentifier("mumbli-processing-indicator")
        .onAppear {
            highlightedIndex = 0
            cycleTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                DispatchQueue.main.async {
                    highlightedIndex = (highlightedIndex + 1) % barCount
                }
            }
        }
        .onDisappear {
            cycleTimer?.invalidate()
            cycleTimer = nil
        }
    }
}

// MARK: - NSVisualEffectView Bridge

/// Bridges NSVisualEffectView into SwiftUI for native macOS vibrancy/blur effects.
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
