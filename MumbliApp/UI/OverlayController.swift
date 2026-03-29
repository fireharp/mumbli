import AppKit
import SwiftUI

/// Controls the floating overlay window that shows a listening indicator during dictation.
@MainActor
final class OverlayController {
    private var window: NSWindow?
    private var dismissTimer: Timer?

    /// Show the overlay at center-bottom of main screen.
    func show() {
        NSLog("[Overlay] show() called")
        // Clean up any existing overlay immediately
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        window = nil

        let contentView = NSHostingView(rootView: ListeningIndicatorView())
        contentView.frame = NSRect(x: 0, y: 0, width: 140, height: 52)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = .clear

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
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
        })
    }
}

// MARK: - Listening Indicator SwiftUI View

/// A compact listening indicator with 3 pulsing dots and a "Listening" label.
struct ListeningIndicatorView: View {
    @State private var isAnimating = false

    private let dotCount = 3

    var body: some View {
        HStack(spacing: 6) {
            // Pulsing dots
            HStack(spacing: 6) {
                ForEach(0..<dotCount, id: \.self) { index in
                    PulsingDot(
                        isAnimating: isAnimating,
                        delay: Double(index) * 0.15
                    )
                }
            }

            Text("Listening")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .accessibilityIdentifier("mumbli-listening-label")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                // Hairline stroke for edge definition
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityIdentifier("mumbli-listening-indicator")
        .onAppear {
            isAnimating = true
        }
    }
}

/// A single dot that pulses in scale and opacity with a staggered delay.
struct PulsingDot: View {
    let isAnimating: Bool
    let delay: Double

    @State private var phase: Bool = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
            .scaleEffect(phase ? 1.4 : 1.0)
            .opacity(phase ? 1.0 : 0.4)
            .animation(
                .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: phase
            )
            .onAppear {
                if isAnimating {
                    phase = true
                }
            }
            .onChange(of: isAnimating) { newValue in
                phase = newValue
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
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
