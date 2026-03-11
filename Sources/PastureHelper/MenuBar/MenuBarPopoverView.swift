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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "hare.fill")
                        .foregroundStyle(.green)
                    Text("Pasture for Mac")
                        .font(.headline)
                    Spacer()
                }

                Divider()

                // Ollama status
                StatusRow(
                    icon: "circle.fill",
                    iconColor: ollamaStatusColor,
                    label: ollamaStatusLabel
                )

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
                    .tint(.blue)
                    .font(.subheadline)

                Button("Quit Pasture for Mac") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.secondary)
                .font(.footnote)
                Spacer()
            }
            .padding()
        }
        .frame(width: 300, height: 420)
    }
}

private extension MenuBarPopoverView {
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
