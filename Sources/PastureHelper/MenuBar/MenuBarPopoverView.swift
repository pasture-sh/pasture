import Foundation
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var advertiser: LoomAdvertiser
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    let onSetAdvertisingPaused: (Bool) -> Void
    let onSetLaunchAtLogin: (Bool) -> Void
    let onManageModels: () -> Void
    let onClearDiagnostics: () -> Void
    @State private var showDiagnostics = false
    @State private var showTailscaleSetup = false
    @State private var copiedIP = false
    @State private var copyResetTask: Task<Void, Never>?
    @StateObject private var tailscale = TailscaleMonitor()
    private let accentColor = PastureColors.accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "sun.horizon.fill")
                        .foregroundStyle(accentColor)
                    Text("Pasture")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                }

                Divider()

                // Ollama status
                ollamaStatusSection

                // Connected iPhone
                StatusRow(
                    icon: "iphone",
                    iconColor: advertiser.connectedPeerName != nil ? .blue : .secondary,
                    label: advertiser.connectedPeerName.map { "Connected: \($0)" } ?? "No iPhone connected"
                )

                Toggle(isOn: Binding(
                    get: { advertiser.isPaused },
                    set: { onSetAdvertisingPaused($0) }
                )) {
                    Text("Pause discovery")
                        .font(.callout)
                }
                .toggleStyle(.switch)

                Toggle(isOn: Binding(
                    get: { launchAtLoginManager.isEnabled },
                    set: { onSetLaunchAtLogin($0) }
                )) {
                    Text("Launch at login")
                        .font(.callout)
                }
                .toggleStyle(.switch)

                if let errorMessage = launchAtLoginManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                remoteAccessSection

                Divider()

                DisclosureGroup("Advanced diagnostics", isExpanded: $showDiagnostics) {
                    VStack(alignment: .leading, spacing: 6) {
                        DiagnosticValueRow(label: "Start attempts", value: "\(advertiser.diagnostics.startAttempts)")
                        DiagnosticValueRow(label: "Start successes", value: "\(advertiser.diagnostics.startSuccesses)")
                        DiagnosticValueRow(label: "Start failures", value: "\(advertiser.diagnostics.startFailures)")
                        DiagnosticValueRow(label: "Incoming connections", value: "\(advertiser.diagnostics.incomingConnections)")
                        DiagnosticValueRow(label: "Disconnections", value: "\(advertiser.diagnostics.disconnections)")
                        DiagnosticValueRow(label: "Health checks", value: "\(advertiser.diagnostics.healthChecks)")
                        DiagnosticValueRow(label: "Unreachable checks", value: "\(advertiser.diagnostics.unreachableChecks)")
                        DiagnosticValueRow(label: "Proxy requests", value: "\(advertiser.diagnostics.proxy.requestsReceived)")
                        DiagnosticValueRow(label: "Proxy decode failures", value: "\(advertiser.diagnostics.proxy.requestDecodeFailures)")
                        DiagnosticValueRow(label: "Proxy handler errors", value: "\(advertiser.diagnostics.proxy.handlerErrors)")
                        DiagnosticValueRow(label: "Proxy send failures", value: "\(advertiser.diagnostics.proxy.responseSendFailures)")

                        if let lastError = advertiser.diagnostics.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        }

                        if advertiser.diagnostics.proxy.recentEvents.isEmpty && advertiser.diagnostics.recentEvents.isEmpty {
                            Text("No diagnostic events yet.")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        } else {
                            ForEach(advertiser.diagnostics.recentEvents.suffix(6).reversed()) { event in
                                DiagnosticEventLine(
                                    label: "[HELPER] \(event.level.rawValue.uppercased()) \(formattedTimestamp(event.timestamp))",
                                    message: event.message,
                                    color: helperEventColor(for: event.level)
                                )
                            }

                            ForEach(advertiser.diagnostics.proxy.recentEvents.suffix(8).reversed()) { event in
                                DiagnosticEventLine(
                                    label: "[PROXY] \(event.level.rawValue.uppercased()) \(formattedTimestamp(event.timestamp))",
                                    message: event.message,
                                    color: proxyEventColor(for: event.level)
                                )
                            }
                        }

                        Button("Clear diagnostics", action: onClearDiagnostics)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                    }
                    .padding(.top, 6)
                }

                Divider()

                Button("Manage Models", action: onManageModels)
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))

                Button("Show Conversation Backups") {
                    let folder = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Pasture")
                    if !FileManager.default.fileExists(atPath: folder.path) {
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    }
                    NSWorkspace.shared.open(folder)
                }
                .foregroundStyle(.secondary)
                .font(.system(.footnote, design: .rounded))

                Button("Quit Pasture") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.secondary)
                .font(.system(.footnote, design: .rounded))
                Spacer()
            }
            .padding()
        }
        .frame(width: 300, height: 480)
        .background(PastureColors.popoverBackground)
        .colorScheme(.dark)
        .fontDesign(.rounded)
        .onAppear { tailscale.refresh() }
    }
}

private extension MenuBarPopoverView {
    // MARK: Ollama status

    @ViewBuilder var ollamaStatusSection: some View {
        StatusRow(
            icon: "circle.fill",
            iconColor: ollamaStatusColor,
            label: ollamaStatusLabel
        )

        if !advertiser.ollamaIsReachable {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ollama needs to be running on this Mac for Pasture to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
                        Button("Open Ollama") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .controlSize(.small)
                    }

                    Button("Download Ollama →") {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com")!)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(.leading, 24)
        }
    }

    // MARK: Remote Access

    @ViewBuilder var remoteAccessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remote Access")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            if tailscale.isActive, let ip = tailscale.tailscaleIP {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Tailscale active")
                        .font(.callout)
                }

                HStack(spacing: 6) {
                    Text(ip)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Spacer()

                    Button(copiedIP ? "Copied!" : "Copy") {
                        NSPasteboard.general.clearContents()
                        let success = NSPasteboard.general.setString(ip, forType: .string)
                        guard success else { return }
                        copiedIP = true
                        copyResetTask?.cancel()
                        copyResetTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copiedIP = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(copiedIP ? .green : nil)
                }

                Text("Copy this IP, then open Pasture on your iPhone → Settings → Tailscale Remote Access and paste it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("Tailscale not detected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("How to set up remote access", isExpanded: $showTailscaleSetup) {
                    VStack(alignment: .leading, spacing: 6) {
                        RemoteAccessStep(number: "1", text: "Install Tailscale on this Mac and sign in at tailscale.com.")
                        RemoteAccessStep(number: "2", text: "Install Tailscale on your iPhone and sign in to the same account.")
                        RemoteAccessStep(number: "3", text: "Come back here — your Tailscale IP will appear and you can copy it to Pasture on your iPhone.")

                        Button("Open tailscale.com →") {
                            NSWorkspace.shared.open(URL(string: "https://tailscale.com/download")!)
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                        .padding(.top, 2)
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Diagnostics helpers

    func formattedTimestamp(_ date: Date) -> String {
        Self.diagnosticsTimeFormatter.string(from: date)
    }

    func helperEventColor(for level: HelperDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    func proxyEventColor(for level: ProxyDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var ollamaStatusColor: Color {
        if !advertiser.ollamaIsReachable {
            return .red
        }
        if advertiser.isPaused {
            return .orange
        }
        if advertiser.isAdvertising {
            return .green
        }
        return .orange
    }

    var ollamaStatusLabel: String {
        if !advertiser.ollamaIsReachable {
            return "Ollama not running"
        }
        if advertiser.isPaused {
            return "Discovery paused"
        }
        if advertiser.isAdvertising {
            return "Advertising on network"
        }
        return "Starting up..."
    }

    static let diagnosticsTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct StatusRow: View {
    let icon: String
    let iconColor: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.caption)
                .frame(width: 16)
            Text(label)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

private struct DiagnosticValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

private struct RemoteAccessStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number + ".")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DiagnosticEventLine: View {
    let label: String
    let message: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
