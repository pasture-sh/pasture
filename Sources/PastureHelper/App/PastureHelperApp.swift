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
    private let loomContainer: LoomContainer = {
        do {
            return try LoomContainer(
                for: PastureLoomRuntimeConfiguration.makeConfiguration(
                    serviceName: Host.current().localizedName ?? "Pasture"
                )
            )
        } catch {
            fatalError("[PastureHelper] Failed to initialise Loom. In Xcode, ensure the correct Apple Team is selected under target → Signing & Capabilities. Error: \(error)")
        }
    }()
    private var menuBarController: MenuBarController?
    private let onboardingController = OnboardingWindowController()
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(loomContext: loomContainer.mainContext)
        onboardingController.showIfNeeded()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.menuBarController?.handleWakeFromSleep()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
