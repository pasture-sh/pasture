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
            button.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Pasture")
            button.image?.isTemplate = true
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

        let pastureGreen = NSColor(red: 0.690, green: 0.894, blue: 0.416, alpha: 1)

        let tintColor: NSColor
        let tooltip: String
        if !ollamaIsReachable {
            tintColor = .systemRed
            tooltip = "Pasture: Ollama not running"
        } else if connectedPeerName != nil {
            tintColor = pastureGreen
            tooltip = "Pasture: iPhone connected"
        } else if isPaused {
            tintColor = .systemOrange
            tooltip = "Pasture: discovery paused"
        } else if isAdvertising {
            tintColor = pastureGreen
            tooltip = "Pasture: ready"
        } else {
            tintColor = .systemGray
            tooltip = "Pasture: starting up"
        }

        button.contentTintColor = tintColor
        button.toolTip = tooltip
    }

    private func showModelManager() {
        popover.performClose(nil)
        modelManagerWindowController.showWindow()
    }
}
