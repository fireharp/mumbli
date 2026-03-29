import AppKit
import SwiftUI

/// Manages the NSStatusItem in the macOS menu bar and its dropdown menu.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let historyManager: HistoryManager

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
    }

    /// Set up the menu bar status item.
    func setup() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Mumbli")
            button.action = #selector(togglePopover)
            button.target = self
            button.setAccessibilityIdentifier("mumbli-menu-bar-button")
        }

        self.statusItem = statusItem
    }

    @objc private func togglePopover() {
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let menuView = MenuBarDropdownView(
            historyManager: historyManager,
            onSettings: { [weak self] in
                self?.popover?.performClose(nil)
                self?.openSettings()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: menuView)

        popover.setAccessibilityIdentifier("mumbli-menu-bar-popover")

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        self.popover = popover
    }

    private func openSettings() {
        let settingsView = SettingsView()
        let controller = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Mumbli Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 340))
        window.setAccessibilityIdentifier("mumbli-settings-window")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Make MenuBarController work as an NSObject target for button actions
extension MenuBarController: NSObjectProtocol {
    nonisolated func isEqual(_ object: Any?) -> Bool { self === object as AnyObject }
    nonisolated var hash: Int { ObjectIdentifier(self).hashValue }
    nonisolated var superclass: AnyClass? { nil }
    nonisolated func `self`() -> Self { self }
    nonisolated func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    nonisolated func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    nonisolated func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }
    nonisolated func isProxy() -> Bool { false }
    nonisolated func isKind(of aClass: AnyClass) -> Bool { false }
    nonisolated func isMember(of aClass: AnyClass) -> Bool { false }
    nonisolated func conforms(to aProtocol: Protocol) -> Bool { false }
    nonisolated func responds(to aSelector: Selector!) -> Bool { false }
    nonisolated var description: String { "MenuBarController" }
}

// MARK: - Menu Bar Dropdown SwiftUI View

/// The SwiftUI content displayed inside the menu bar popover.
struct MenuBarDropdownView: View {
    @ObservedObject var historyManager: HistoryManager
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .systemPurple),
                                    Color(nsColor: .systemBlue),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Mumbli")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }

                Spacer()

                // Entry count badge
                if !historyManager.entries.isEmpty {
                    Text("\(historyManager.entries.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
                                )
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Subtle separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.primary.opacity(0.08), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // History
            HistoryView(historyManager: historyManager)

            // Subtle separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.primary.opacity(0.08), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            // Footer actions
            VStack(spacing: 2) {
                MenuBarActionButton(
                    icon: "gear",
                    label: "Settings",
                    accessibilityID: "mumbli-settings-button",
                    action: onSettings
                )

                MenuBarActionButton(
                    icon: "power",
                    label: "Quit Mumbli",
                    accessibilityID: "mumbli-quit-button",
                    isDestructive: true,
                    action: onQuit
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}

/// A styled menu bar action button with hover state.
struct MenuBarActionButton: View {
    let icon: String
    let label: String
    let accessibilityID: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDestructive && isHovered ? Color(nsColor: .systemRed).opacity(0.8) : .secondary)
                    .frame(width: 18)

                Text(label)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(isDestructive && isHovered ? Color(nsColor: .systemRed).opacity(0.8) : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityIdentifier(accessibilityID)
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
