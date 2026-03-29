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
                .assign(to: \.audioLevel, on: audioProvider)
        }

        let hostingView = NSHostingView(rootView: OverlayRootView(audioLevelProvider: audioProvider, stateProvider: stateProvider, mode: mode))
        let frame = NSRect(x: 0, y: 0, width: 56, height: 56)
        hostingView.frame = frame

        // NSHostingView draws an opaque background by default, which shows as a
        // visible rectangle behind the rounded pill shape. To fix this:
        // 1. Wrap in a plain NSView with a transparent layer
        // 2. Force the hosting view's layer to be transparent
        // 3. Disable drawsBackground on the hosting view
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

/// A compact listening indicator with 5 waveform bars (Siri-style).
/// In hands-free mode, uses orange bars, a static orange border, and a red REC dot.
struct ListeningIndicatorView: View {
    @ObservedObject var audioLevelProvider: AudioLevelProvider
    let mode: ActivationMode

    private let barCount = 5
    /// Per-bar multipliers — center bar leads, edges lag.
    private let barMultipliers: [CGFloat] = [0.6, 0.8, 1.0, 0.8, 0.6]
    /// Stagger delay from center outward: center=0, adjacent=15ms, outer=30ms.
    private let staggerDelays: [Double] = [0.030, 0.015, 0.0, 0.015, 0.030]

    private var isHandsFree: Bool { mode == .handsFree }

    var body: some View {
        HStack(spacing: 0) {
            // Red REC dot for hands-free mode
            if isHandsFree {
                Circle()
                    .fill(Color.red)
                    .frame(width: 4, height: 4)
                    .opacity(0.8)
                    .padding(.trailing, 6)
            }

            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        audioLevel: audioLevelProvider.audioLevel,
                        multiplier: barMultipliers[index],
                        staggerDelay: staggerDelays[index],
                        restHeight: index == 2 ? 8 : 6,
                        isHandsFree: isHandsFree
                    )
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
        // Glow when audio level > 0.3
        .shadow(
            color: audioLevelProvider.audioLevel > 0.3
                ? Color.accentColor.opacity(Double(audioLevelProvider.audioLevel) * 0.25)
                : .black.opacity(0.12),
            radius: audioLevelProvider.audioLevel > 0.3 ? 8 : 12,
            x: 0, y: audioLevelProvider.audioLevel > 0.3 ? 0 : 4
        )
        .accessibilityIdentifier("mumbli-listening-indicator")
    }
}

/// Observable object that tracks whether the overlay is in listening or processing state.
class OverlayStateProvider: ObservableObject {
    @Published var isProcessing = false
}

/// Observable object that bridges audio level data to SwiftUI.
class AudioLevelProvider: ObservableObject {
    @Published var audioLevel: Float = 0.0
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

/// A compact processing indicator with a native macOS spinner.
/// Shown after Fn release while transcription + polishing API calls happen.
struct ProcessingIndicatorView: View {
    let wasHandsFree: Bool

    var body: some View {
        ProgressView()
            .scaleEffect(0.6)
            .frame(width: 16, height: 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
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
    }
}

/// A single waveform bar that reacts to microphone audio levels.
/// Uses orange color in hands-free mode, accent color in hold mode.
struct WaveformBar: View {
    let audioLevel: Float
    let multiplier: CGFloat
    let staggerDelay: Double
    let restHeight: CGFloat
    var isHandsFree: Bool = false

    private let barWidth: CGFloat = 3
    private let maxHeight: CGFloat = 24

    private var barHeight: CGFloat {
        let level = CGFloat(min(max(CGFloat(audioLevel), 0), 1))
        return restHeight + level * (maxHeight - restHeight) * multiplier
    }

    private var barOpacity: Double {
        let level = Double(min(max(Double(audioLevel), 0), 1))
        return 0.7 + level * 0.3
    }

    private var barColor: Color {
        isHandsFree ? .orange : .accentColor
    }

    var body: some View {
        Capsule()
            .fill(barColor)
            .frame(width: barWidth, height: barHeight)
            .opacity(barOpacity)
            .animation(
                .spring(response: 0.10, dampingFraction: 0.75).delay(staggerDelay),
                value: CGFloat(audioLevel)
            )
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
