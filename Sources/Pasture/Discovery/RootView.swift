import SwiftUI
import LoomKit
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
            ConversationListView()
        } else if hasCompletedOnboarding && connection.hasEverConnected {
            ConversationListView()
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
                ConversationListView()
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
    private let palette = ModelEnvironment.chat(for: nil).palette

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
        EnvironmentBackground(environment: .chat(for: nil))
            .ignoresSafeArea()
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
                Text("Pasture")
                    .font(.custom("Nunito-ExtraBold", size: 34))
                    .foregroundStyle(.white)

                Text("Where your models roam free.")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)

                Text("The easiest way to use Ollama on your iPhone.")
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

            VStack(spacing: 6) {
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
                    VStack(spacing: 3) {
                        Text("Pasture for Mac is available on")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                        Link("pasture.sh →", destination: URL(string: "https://pasture.sh")!)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                        Text("Open it on your Mac, then tap below.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                }

                OnboardingPrimaryCTA(
                    title: "My Mac is ready →",
                    palette: palette,
                    reduceTransparency: reduceTransparency,
                    action: onContinue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
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

    /// Once a Mac is seen we keep showing it — prevents the list from flashing
    /// in and out as Loom's peer refresh cycles.
    @State private var stickyHelpers: [LoomPeerSnapshot] = []
    @State private var showDiagnostics = false
    @State private var glyphBreathe = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 32)

                PasturePresenceGlyph(palette: palette)
                    .opacity(glyphOpacity)
                    .scaleEffect(glyphBreathe && glyphShouldAnimate ? 1.02 : 0.98)

                statusCapsule

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                }

                // Mac buttons — shown as soon as any Mac has been seen.
                // Not hidden when the list briefly empties during a refresh.
                if !stickyHelpers.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(stickyHelpers) { peer in
                            macConnectButton(for: peer)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Error text only when failed AND no Mac is available to tap.
                if let msg = errorMessage, stickyHelpers.isEmpty {
                    Text(msg)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    OnboardingPrimaryCTA(
                        title: "Try again",
                        palette: palette,
                        reduceTransparency: reduceTransparency,
                        action: {
                            stickyHelpers = []
                            onRetry()
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }

                if isFailed {
                    TroubleshootingChecklist()
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 16)

                Button(showDiagnostics ? "Hide diagnostics" : "Show diagnostics") {
                    withAnimation(.easeInOut(duration: 0.2)) { showDiagnostics.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

                if showDiagnostics {
                    WaitingDiagnosticsCard(connection: connection)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            latchHelpers(connection.availableHelpers)
            startGlyphAnimationIfNeeded()
        }
        .onChange(of: connection.availableHelpers) { _, helpers in
            latchHelpers(helpers)
        }
        .onChange(of: state) { _, _ in
            startGlyphAnimationIfNeeded()
        }
    }

    // MARK: - Helpers

    private func latchHelpers(_ helpers: [LoomPeerSnapshot]) {
        if !helpers.isEmpty { stickyHelpers = helpers }
    }

    private func macConnectButton(for peer: LoomPeerSnapshot) -> some View {
        Button {
            Task { await connection.connectToHelper(peerID: peer.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: peer.deviceType.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(peer.name)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
            }
            .foregroundStyle(ctaTextColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .modifier(OnboardingPrimaryCTAModifier(palette: palette, reduceTransparency: reduceTransparency))
    }

    private var ctaTextColor: Color {
        if #available(iOS 26.0, *), !reduceTransparency { return .white }
        return palette.userBubble
    }

    // MARK: - State-derived

    private var statusTitle: String {
        switch state {
        case .discovering:
            return stickyHelpers.isEmpty ? "Listening for your Mac…" : "Your Mac is nearby — tap to connect."
        case .connecting(let name):
            return "Connecting to \(name)…"
        case .reconnecting(let name, _):
            return "Connecting to \(name ?? "your Mac")…"
        case .failed:
            return stickyHelpers.isEmpty ? "Couldn't find your Mac." : "Tap your Mac below to connect."
        case .connected(let name):
            return "Connected to \(name)"
        }
    }

    private var isLoading: Bool {
        switch state {
        case .discovering, .connecting, .reconnecting: return true
        case .failed, .connected: return false
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
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

    private var glyphOpacity: Double {
        if case .failed = state { return stickyHelpers.isEmpty ? 0.55 : 1.0 }
        return 1.0
    }

    private var glyphShouldAnimate: Bool {
        switch state {
        case .discovering, .connecting, .reconnecting: return true
        case .failed, .connected: return false
        }
    }

    private var glyphDuration: Double {
        switch state {
        case .connecting: return 1.4
        case .discovering, .reconnecting: return 2.4
        case .failed, .connected: return 0
        }
    }

    private func startGlyphAnimationIfNeeded() {
        guard glyphShouldAnimate else {
            glyphBreathe = false
            return
        }
        glyphBreathe = false
        withAnimation(.easeInOut(duration: glyphDuration).repeatForever(autoreverses: true)) {
            glyphBreathe = true
        }
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

            Image(systemName: "leaf.fill")
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
