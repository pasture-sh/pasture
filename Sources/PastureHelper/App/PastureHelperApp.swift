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
        for: LoomContainerConfiguration(
            serviceType: "_pasture._tcp",
            serviceName: Host.current().localizedName ?? "Pasture for Mac",
            trust: .sameAccountAutoTrust,
            advertisementMetadata: ["service": "pasture"]
        )
    )
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            loomContext: loomContainer.mainContext
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
