import AppKit
import SwiftUI

/// Controls the floating overlay window that shows a listening indicator during dictation.
@MainActor
final class OverlayController {
    private var window: NSWindow?
    private var dismissTimer: Timer?

    /// Show the overlay near the current cursor position.
    func show() {
        dismiss()

        let contentView = NSHostingView(rootView: ListeningIndicatorView())
        contentView.frame = NSRect(x: 0, y: 0, width: 80, height: 48)

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
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setAccessibilityIdentifier("mumbli-overlay-window")
        window.alphaValue = 0

        // Position near the active text cursor or fall back to mouse location
        let position = cursorScreenPosition() ?? NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: position.x + 8,
            y: position.y - window.frame.height - 8
        ))

        window.orderFront(nil)

        // Fade + scale in with spring-like ease
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        self.window = window
    }

    /// Dismiss the overlay, optionally after a brief delay.
    func dismiss(afterDelay delay: TimeInterval = 0) {
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })
    }

    /// Attempt to get the screen position of the focused text cursor via Accessibility API.
    private func cursorScreenPosition() -> NSPoint? {
        guard let systemWide = AXUIElementCreateSystemWide() as AXUIElement? else { return nil }

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return nil }

        var rangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeResult == .success, let range = rangeValue else { return nil }

        var boundsValue: AnyObject?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        )
        guard boundsResult == .success, let bounds = boundsValue else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }

        // AX coordinates have origin at top-left; convert to screen coordinates (bottom-left origin)
        guard let screen = NSScreen.main else { return nil }
        let screenHeight = screen.frame.height
        return NSPoint(x: rect.origin.x, y: screenHeight - rect.origin.y - rect.height)
    }
}

// MARK: - Listening Indicator SwiftUI View

/// An animated waveform indicator shown during active dictation with glassmorphism styling.
struct ListeningIndicatorView: View {
    @State private var isAnimating = false
    @State private var glowPulse = false

    private let barCount = 5
    private let barColors: [Color] = [
        Color(nsColor: .systemIndigo),
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemCyan),
        Color(nsColor: .systemTeal),
    ]

    var body: some View {
        HStack(spacing: 3) {
            // Audio waveform bars
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        isAnimating: isAnimating,
                        delay: Double(index) * 0.1,
                        color: barColors[index % barColors.count]
                    )
                }
            }
            .frame(width: 24, height: 18)

            Text("Listening")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .accessibilityIdentifier("mumbli-listening-label")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            ZStack {
                // Vibrancy blur background
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                // Subtle inner gradient for depth
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.02),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Animated glow ring
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(glowPulse ? 0.4 : 0.15),
                                Color(nsColor: .systemBlue).opacity(glowPulse ? 0.3 : 0.1),
                                Color(nsColor: .systemCyan).opacity(glowPulse ? 0.2 : 0.05),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .shadow(color: Color(nsColor: .systemPurple).opacity(0.15), radius: 16, x: 0, y: 4)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
        .accessibilityIdentifier("mumbli-listening-indicator")
        .onAppear {
            isAnimating = true
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }
}

/// A single animated waveform bar that oscillates with a given delay.
struct WaveformBar: View {
    let isAnimating: Bool
    let delay: Double
    let color: Color

    @State private var phase: CGFloat = 0.2

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3, height: isAnimating ? 16 * phase : 3)
            .animation(
                .easeInOut(duration: 0.4 + delay * 0.3)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                if isAnimating {
                    phase = 1.0
                }
            }
            .onChange(of: isAnimating) { newValue in
                phase = newValue ? 1.0 : 0.2
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
