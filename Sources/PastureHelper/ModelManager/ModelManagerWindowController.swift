import AppKit
import SwiftUI

@MainActor
final class ModelManagerWindowController {
    private var window: NSWindow?

    func showWindow() {
        if window == nil {
            window = makeWindow()
        }

        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: ModelManagerView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Pasture for Mac — Models"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}
