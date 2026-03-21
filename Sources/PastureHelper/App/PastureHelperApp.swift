import Foundation
import SwiftUI
import LoomKit

@main
struct PastureHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only — no dock icon (LSUIElement = true in Info.plist)
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let loomContainer = try! LoomContainer(
        for: PastureLoomRuntimeConfiguration.makeConfiguration(
            serviceName: Host.current().localizedName ?? "Pasture"
        )
    )
    private var menuBarController: MenuBarController?
    private let onboardingController = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(loomContext: loomContainer.mainContext)
        onboardingController.showIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
