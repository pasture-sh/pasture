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
    private let palette = ModelEnvironment.onboardingDefault.palette

    var body: some View {
        ZStack {
            BackgroundView()

            switch step {
            case .welcome:
                WelcomeStepView(palette: palette, onGetStarted: onGetStarted)
            case .installHelper:
                InstallHelperStepView(palette: palette, onContinue: onContinueToPairing)
            case .waiting:
                WaitingForMacStepView(
                    state: connectionState,
                    palette: palette,
                    onRetry: onRetry
                )
            }
        }
        .fontDesign(.rounded)
    }
}

private struct BackgroundView: View {
    var body: some View {
        EnvironmentBackground(environment: .onboardingDefault)
    }
}

private struct WelcomeStepView: View {
    let palette: EnvironmentPalette
    let onGetStarted: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            PasturePresenceGlyph(palette: palette)

            VStack(spacing: 12) {
                Text("LOCAL AI, MADE CALM")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.62))

                Text("Pasture")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your AI.\nAt home.")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text("A quieter, friendlier way to use Ollama from your iPhone.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    .padding(.horizontal, 36)
            }

            Spacer()

            OnboardingPrimaryCTA(
                title: "Get started",
                palette: palette,
                reduceTransparency: reduceTransparency,
                action: onGetStarted
            )
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
        }
    }
}

private struct InstallHelperStepView: View {
    let palette: EnvironmentPalette
    let onContinue: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            HStack(spacing: 16) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 34, weight: .semibold))
                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Image(systemName: "iphone")
                    .font(.system(size: 30, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.95))

            VStack(spacing: 10) {
                Text("Open Pasture on your Mac")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("No accounts, IP addresses, or setup rituals. Keep this screen open and your Mac will appear automatically.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            VStack(alignment: .leading, spacing: 10) {
                onboardingNote("Same Wi-Fi on both devices")
                onboardingNote("Ollama installed on your Mac")
                onboardingNote("Pasture for Mac left open while pairing")
            }
            .padding(18)
            .modifier(OnboardingCardModifier())
            .padding(.horizontal, 24)

            Spacer()

            if let helperDownloadURL {
                OnboardingPrimaryCTA(
                    title: "Get Pasture for Mac",
                    palette: palette,
                    reduceTransparency: reduceTransparency
                ) {
                    openURL(helperDownloadURL)
                }
                .padding(.horizontal, 24)
            } else {
                Text("Pasture for Mac is currently distributed privately. Open it on your Mac, then continue here.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button("Pasture for Mac is open", action: onContinue)
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
        }
    }

    private func onboardingNote(_ text: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
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
    @EnvironmentObject private var connection: ConnectionManager
    let state: ConnectionManager.ConnectionState
    let palette: EnvironmentPalette
    let onRetry: () -> Void

    @State private var showTroubleshooting = false
    @State private var showDiagnostics = false
    @State private var llamaBreathe = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            PasturePresenceGlyph(palette: palette)
                .opacity(llamaOpacity)
                .scaleEffect(llamaScale)

            statusCapsule

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.9)
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

            if !connection.availableHelpers.isEmpty {
                AvailableMacsCard(connection: connection)
                    .padding(.horizontal, 20)
            }

            Button(showDiagnostics ? "Hide diagnostics" : "Show diagnostics") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDiagnostics.toggle()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))

            if showDiagnostics {
                WaitingDiagnosticsCard(connection: connection)
                    .padding(.horizontal, 20)
            }

            if errorMessage != nil {
                OnboardingPrimaryCTA(
                    title: "Try again",
                    palette: palette,
                    reduceTransparency: reduceTransparency,
                    action: onRetry
                )
                .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .task {
            showTroubleshooting = false
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            showTroubleshooting = true
        }
        .onAppear {
            startLlamaAnimationIfNeeded()
        }
        .onChange(of: state) { _, _ in
            startLlamaAnimationIfNeeded()
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

    @ViewBuilder
    private var statusCapsule: some View {
        Text(statusTitle)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.84))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .modifier(OnboardingStatusCapsuleModifier(palette: palette, reduceTransparency: reduceTransparency))
            .padding(.horizontal, 24)
    }

    private var llamaOpacity: Double {
        if case .failed = state { return 0.55 }
        return 1.0
    }

    private var llamaScale: CGFloat {
        guard llamaShouldAnimate else { return 1.0 }
        return llamaBreathe ? 1.02 : 0.98
    }

    private var llamaShouldAnimate: Bool {
        switch state {
        case .discovering, .connecting, .reconnecting:
            return true
        case .failed, .connected:
            return false
        }
    }

    private var llamaDuration: Double {
        switch state {
        case .connecting:
            return 1.4
        case .discovering, .reconnecting:
            return 2.4
        case .failed, .connected:
            return 0
        }
    }

    private func startLlamaAnimationIfNeeded() {
        guard llamaShouldAnimate else {
            llamaBreathe = false
            return
        }
        llamaBreathe = false
        withAnimation(.easeInOut(duration: llamaDuration).repeatForever(autoreverses: true)) {
            llamaBreathe = true
        }
    }
}

private struct AvailableMacsCard: View {
    let connection: ConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visible Macs")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(connection.availableHelpers) { peer in
                Button {
                    Task { await connection.connectToHelper(peerID: peer.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: peer.deviceType.systemImage)
                            .foregroundStyle(.white.opacity(0.92))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(peer.isNearby ? "Nearby" : "Reachable")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        if connection.connectedPeerID == peer.id {
                            Text("Connected")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(OnboardingCardModifier())
    }
}

private struct WaitingDiagnosticsCard: View {
    let connection: ConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovery diagnostics")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            diagnosticsRow("Discovery starts", "\(connection.diagnostics.discoveryStarts)")
            diagnosticsRow("Peer refreshes", "\(connection.diagnostics.peerRefreshes)")
            diagnosticsRow("Visible peers", "\(connection.diagnostics.visiblePeerCount)")
            diagnosticsRow("Visible helpers", "\(connection.diagnostics.visibleHelperCount)")
            diagnosticsRow("Connect attempts", "\(connection.diagnostics.connectAttempts)")
            diagnosticsRow("Connect successes", "\(connection.diagnostics.connectSuccesses)")

            if let loomRuntimeError = connection.diagnostics.loomRuntimeError,
               !loomRuntimeError.isEmpty {
                Text("Loom runtime: \(loomRuntimeError)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.95))
            }

            if let peerSummary = connection.diagnostics.lastPeerSnapshotSummary,
               !peerSummary.isEmpty {
                Text(peerSummary)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
            }

            let events = Array(connection.diagnostics.recentEvents.suffix(6).reversed())
            if !events.isEmpty {
                Divider()
                    .overlay(.white.opacity(0.12))

                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(event.level.rawValue.uppercased())] \(Self.timeFormatter.string(from: event.timestamp))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(eventColor(for: event.level))
                        Text(event.message)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(OnboardingCardModifier())
    }

    private func diagnosticsRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func eventColor(for level: ConnectionDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
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
        .modifier(OnboardingCardModifier())
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
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
    }
}

struct DiscoveringView: View {
    var status: String = "Looking for your Mac..."

    var body: some View {
        ZStack {
            BackgroundView()

            VStack(spacing: 18) {
                PasturePresenceGlyph(palette: ModelEnvironment.onboardingDefault.palette)

                Text(status)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

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

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                OnboardingPrimaryCTA(
                    title: "Try again",
                    palette: ModelEnvironment.onboardingDefault.palette,
                    reduceTransparency: false,
                    action: retry
                )
                .padding(.horizontal, 40)
            }
        }
    }
}

private struct PasturePresenceGlyph: View {
    let palette: EnvironmentPalette

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 112, height: 112)

            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 1)
                .frame(width: 112, height: 112)

            Image(systemName: "hare.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white.opacity(0.94))
        }
    }
}

private struct OnboardingPrimaryCTA: View {
    let title: String
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .modifier(OnboardingPrimaryCTAModifier(palette: palette, reduceTransparency: reduceTransparency))
    }

    private var textColor: Color {
        if #available(iOS 26.0, *), !reduceTransparency {
            return .white
        }
        return palette.userBubble
    }
}

private struct OnboardingPrimaryCTAModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(palette.userBubble.opacity(0.38)).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

private struct OnboardingStatusCapsuleModifier: ViewModifier {
    let palette: EnvironmentPalette
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(palette.nearLayer.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}

private struct OnboardingCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
    }
}
