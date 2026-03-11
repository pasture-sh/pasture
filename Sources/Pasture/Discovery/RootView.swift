import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Routes between onboarding/discovery and the main chat experience.
struct RootView: View {
    @EnvironmentObject var connection: ConnectionManager
    @AppStorage("pasture.onboarding.completed") private var hasCompletedOnboarding = false
    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var connectionToastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            currentContent

            if let connectionToastMessage {
                ConnectionToast(message: connectionToastMessage)
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.25), value: connectionToastMessage)
        .onChange(of: connection.state) { _, newState in
            guard case .connected(let peerName) = newState else { return }
            handleConnected(peerName: peerName)
        }
    }

    @ViewBuilder
    private var currentContent: some View {
        if case .connected = connection.state {
            ChatView()
        } else if hasCompletedOnboarding && connection.hasEverConnected {
            ChatView()
                .overlay(alignment: .top) {
                    if let recoveryBannerMessage {
                        ConnectionRecoveryBanner(
                            message: recoveryBannerMessage,
                            showsRetry: showsRecoveryRetry
                        ) {
                            Task { await connection.startDiscovery() }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 12)
                    }
                }
                .task {
                    if case .connected = connection.state {
                        return
                    }
                    await connection.startDiscovery(resetReconnectAttempts: false)
                }
        } else if hasCompletedOnboarding {
            switch connection.state {
            case .discovering:
                DiscoveringView()
                    .task { await connection.startDiscovery() }

            case .connecting(let name):
                DiscoveringView(status: "Connecting to \(name)...")

            case .reconnecting(let name, _):
                DiscoveringView(status: "Reconnecting to \(name ?? "your Mac")...")

            case .failed(let message):
                ErrorView(message: message) {
                    Task { await connection.startDiscovery() }
                }

            case .connected:
                ChatView()
            }
        } else {
            OnboardingFlowView(
                step: onboardingStep,
                connectionState: connection.state,
                onGetStarted: {
                    onboardingStep = .installHelper
                },
                onContinueToPairing: {
                    onboardingStep = .waiting
                    Task { await connection.startDiscovery() }
                },
                onRetry: {
                    Task { await connection.startDiscovery() }
                }
            )
            .task {
                if onboardingStep == .waiting {
                    await connection.startDiscovery()
                }
            }
        }
    }

    private var recoveryBannerMessage: String? {
        switch connection.state {
        case .connected:
            return nil
        case .discovering:
            return "Looking for your Mac…"
        case .connecting(let peerName):
            return "Connecting to \(peerName)…"
        case .reconnecting(let peerName, let attempt):
            let target = peerName ?? "your Mac"
            return "Reconnecting to \(target)… (Attempt \(attempt))"
        case .failed(let message):
            return message
        }
    }

    private var showsRecoveryRetry: Bool {
        if case .failed = connection.state {
            return true
        }
        return false
    }

    private func handleConnected(peerName: String) {
        connectionToastMessage = "Connected to \(peerName)"

#if os(iOS)
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
#endif

        if !hasCompletedOnboarding {
            hasCompletedOnboarding = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    connectionToastMessage = nil
                }
            }
        }
    }
}

private enum OnboardingStep {
    case welcome
    case installHelper
    case waiting
}

private struct OnboardingFlowView: View {
    let step: OnboardingStep
    let connectionState: ConnectionManager.ConnectionState
    let onGetStarted: () -> Void
    let onContinueToPairing: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            BackgroundView()

            switch step {
            case .welcome:
                WelcomeStepView(onGetStarted: onGetStarted)
            case .installHelper:
                InstallHelperStepView(onContinue: onContinueToPairing)
            case .waiting:
                WaitingForMacStepView(
                    state: connectionState,
                    onRetry: onRetry
                )
            }
        }
    }
}

private struct BackgroundView: View {
    var body: some View {
        EnvironmentBackground(environment: .pasture)
    }
}

private struct WelcomeStepView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "hare.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                Text("Pasture")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your AI. At home.")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Spacer()

            Button("Get started", action: onGetStarted)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(red: 0.21, green: 0.44, blue: 0.19))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
        }
    }
}

private struct InstallHelperStepView: View {
    let onContinue: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            HStack(spacing: 18) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 38, weight: .semibold))
                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Image(systemName: "iphone")
                    .font(.system(size: 34, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.95))

            Text("First, open Pasture for Mac")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("No accounts. No IP addresses. Keep this screen open while your Mac appears automatically.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()

            if let helperDownloadURL {
                Button {
                    openURL(helperDownloadURL)
                } label: {
                    Text("Get Pasture for Mac")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color(red: 0.21, green: 0.44, blue: 0.19))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .padding(.horizontal, 24)
            } else {
                Text("Pasture for Mac is currently distributed privately. Open it on your Mac, then come back and continue.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }

            Button("Pasture for Mac is open", action: onContinue)
                .buttonStyle(.plain)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
        }
    }

    private var helperDownloadURL: URL? {
        let rawValue =
            (Bundle.main.object(forInfoDictionaryKey: "PastureMacDownloadURL") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "MacCompanionDownloadURL") as? String)

        guard let rawValue,
              let url = URL(string: rawValue),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return nil
        }
        return url
    }
}

private struct WaitingForMacStepView: View {
    let state: ConnectionManager.ConnectionState
    let onRetry: () -> Void

    @State private var showTroubleshooting = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "hare.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.95))

            Text(statusTitle)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if isLoading {
                ProgressView()
                    .tint(.white)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            if shouldShowChecklist {
                TroubleshootingChecklist()
                    .padding(.horizontal, 20)
            }

            if errorMessage != nil {
                Button("Try again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Color(red: 0.21, green: 0.44, blue: 0.19))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .padding(.top, 4)
            }

            Spacer()
        }
        .task {
            showTroubleshooting = false
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            showTroubleshooting = true
        }
    }

    private var statusTitle: String {
        switch state {
        case .discovering:
            return "Listening for your Mac..."
        case .connecting(let peerName):
            return "Connecting to \(peerName)..."
        case .reconnecting(let peerName, _):
            return "Reconnecting to \(peerName ?? "your Mac")..."
        case .failed:
            return "Having trouble finding your Mac."
        case .connected(let peerName):
            return "Connected to \(peerName)"
        }
    }

    private var isLoading: Bool {
        switch state {
        case .discovering, .connecting, .reconnecting:
            return true
        case .failed, .connected:
            return false
        }
    }

    private var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    private var shouldShowChecklist: Bool {
        showTroubleshooting || errorMessage != nil
    }
}

private struct TroubleshootingChecklist: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Having trouble?")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            ChecklistRow(text: "Pasture for Mac is open on your Mac")
            ChecklistRow(text: "Both devices are on the same Wi-Fi")
            ChecklistRow(text: "Ollama is installed and running")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ChecklistRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.square")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(text)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
        }
    }
}

private struct ConnectionToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct ConnectionRecoveryBanner: View {
    let message: String
    let showsRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: showsRetry ? "wifi.exclamationmark" : "arrow.trianglehead.2.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(showsRetry ? .orange : .blue)

            Text(message)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 6)

            if showsRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct DiscoveringView: View {
    var status: String = "Looking for your Mac..."

    var body: some View {
        ZStack {
            BackgroundView()

            VStack(spacing: 24) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)

                Text("Pasture")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text(status)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                ProgressView()
                    .tint(.white)
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            BackgroundView()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.green)
            }
        }
    }
}
