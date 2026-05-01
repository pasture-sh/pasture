import AppKit
import SwiftUI
import LoomKit
import Combine

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let advertiser: LoomAdvertiser
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let modelManagerWindowController = ModelManagerWindowController()
    private var cancellables: Set<AnyCancellable> = []

    init(loomContext: LoomContext) {
        advertiser = LoomAdvertiser(loomContext: loomContext)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = MenuBarPopoverView(
            advertiser: advertiser,
            launchAtLoginManager: launchAtLoginManager,
            onSetAdvertisingPaused: { [weak self] paused in
                Task { await self?.advertiser.setPaused(paused) }
            },
            onSetLaunchAtLogin: { [weak self] enabled in
                self?.launchAtLoginManager.setEnabled(enabled)
            },
            onManageModels: { [weak self] in
                self?.showModelManager()
            },
            onClearDiagnostics: { [weak self] in
                Task { await self?.advertiser.clearDiagnostics() }
            }
        )
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 300, height: 480)

        bindStatusIcon()

        Task {
            await advertiser.start()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func bindStatusIcon() {
        Publishers.CombineLatest4(
            advertiser.$isAdvertising,
            advertiser.$connectedPeerName,
            advertiser.$ollamaIsReachable,
            advertiser.$isPaused
        )
            .sink { [weak self] isAdvertising, connectedPeerName, ollamaIsReachable, isPaused in
                self?.updateStatusIcon(
                    isAdvertising: isAdvertising,
                    connectedPeerName: connectedPeerName,
                    ollamaIsReachable: ollamaIsReachable,
                    isPaused: isPaused
                )
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(
        isAdvertising: Bool,
        connectedPeerName: String?,
        ollamaIsReachable: Bool,
        isPaused: Bool
    ) {
        guard let button = statusItem.button else { return }

        // Use a colored palette only for anomaly states. Normal/idle states render
        // as a template image so macOS auto-tints for contrast against any wallpaper.
        let coloredTint: NSColor?
        let tooltip: String
        if !ollamaIsReachable {
            coloredTint = .systemRed
            tooltip = "Pasture: Ollama not running"
        } else if isPaused {
            coloredTint = .systemOrange
            tooltip = "Pasture: discovery paused"
        } else if connectedPeerName != nil {
            coloredTint = nil
            tooltip = "Pasture: iPhone connected"
        } else if isAdvertising {
            coloredTint = nil
            tooltip = "Pasture: ready"
        } else {
            coloredTint = nil
            tooltip = "Pasture: starting up"
        }

        let baseImage = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "Pasture")
        if let coloredTint {
            let config = NSImage.SymbolConfiguration(paletteColors: [coloredTint])
            let tinted = baseImage?.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            button.image = tinted
        } else {
            baseImage?.isTemplate = true
            button.image = baseImage
        }
        button.toolTip = tooltip
    }

    func handleWakeFromSleep() {
        Task { await advertiser.restartAfterWake() }
    }

    private func showModelManager() {
        popover.performClose(nil)
        modelManagerWindowController.showWindow()
    }
}
