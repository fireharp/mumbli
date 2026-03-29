import SwiftUI

@main
struct MumbliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app — no main window.
        // MenuBarController (UI layer) handles the NSStatusItem.
        Settings {
            EmptyView()
        }
    }
}
