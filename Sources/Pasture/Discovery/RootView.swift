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
    @State private var toastDismissTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await connection.handleAppForeground() }
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
                    Task { await connection.startDiscovery() }
                },
                onContinueToPairing: {
                    onboardingStep = .waiting
                },
                onRetry: {
                    Task { await connection.startDiscovery() }
                }
            )
            .onChange(of: onboardingStep) { _, step in
                guard step == .waiting else { return }
                Task { await connection.startDiscovery() }
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

        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
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
    @EnvironmentObject private var connection: ConnectionManager

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

            VStack(spacing: 12) {
                Text("Pasture")
                    .font(.custom("Nunito-ExtraBold", size: 34))
                    .foregroundStyle(.white)

                TypingTaglineView()

                Text("The easiest way to use Ollama on your iPhone")
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

private struct TypingTaglineView: View {
    private let taglines = [
        "Where your models roam free",
        "Private by nature",
        "Fast as instinct",
        "Local AI wherever you go",
        "Ready to graze?",
    ]

    @State private var displayedText = ""
    @State private var cursorOpacity: Double = 1

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Text(displayedText)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: 2, height: 29)
                .opacity(cursorOpacity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorOpacity = 0
            }
        }
        .task {
            await runLoop()
        }
    }

    private func runLoop() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        var index = 0
        while !Task.isCancelled {
            let tagline = taglines[index]
            for charCount in 1...tagline.count {
                guard !Task.isCancelled else { return }
                let end = tagline.index(tagline.startIndex, offsetBy: charCount)
                displayedText = String(tagline[..<end])
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            while !displayedText.isEmpty {
                guard !Task.isCancelled else { return }
                displayedText = String(displayedText.dropLast())
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            index = (index + 1) % taglines.count
        }
    }
}

private enum HelperSearchState: Equatable {
    case searching
    case macFound
    case timedOut
}

private struct InstallHelperStepView: View {
    let palette: EnvironmentPalette
    let onContinue: () -> Void
    @EnvironmentObject private var connection: ConnectionManager
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var searchState: HelperSearchState = .searching
    @State private var stickyHelpers: [LoomPeerSnapshot] = []

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "desktopcomputer")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white.opacity(iconOpacity))
                .animation(.easeInOut(duration: 0.4), value: searchState)

            VStack(spacing: 10) {
                Text(headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: searchState)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .transition(.opacity)
                }
            }

            if case .searching = searchState {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.85)
                    .transition(.opacity)
            }

            Spacer()

            VStack(spacing: 16) {
                switch searchState {
                case .searching:
                    EmptyView()

                case .macFound:
                    ForEach(stickyHelpers, id: \.id) { peer in
                        MacConnectButton(peer: peer, palette: palette, reduceTransparency: reduceTransparency)
                            .padding(.horizontal, 24)
                    }

                case .timedOut:
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
                        HStack(spacing: 4) {
                            Text("Get Pasture for Mac at")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                            Link("pasture.sh →", destination: URL(string: "https://pasture.sh")!)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.90))
                        }
                    }

                    Button("My Mac is open →") {
                        onContinue()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.bottom, 30)
            .animation(.easeInOut(duration: 0.35), value: searchState == .macFound)
        }
        .onAppear { latchHelpers(connection.availableHelpers) }
        .onChange(of: connection.availableHelpers) { _, helpers in latchHelpers(helpers) }
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if case .searching = searchState {
                withAnimation { searchState = .timedOut }
            }
        }
    }

    // MARK: - State-derived

    private var headline: String {
        switch searchState {
        case .searching: return "Looking for your Mac\u{2026}"
        case .macFound:  return "Your Mac is here"
        case .timedOut:  return "Set up Pasture on your Mac"
        }
    }

    private var subtitle: String? {
        switch searchState {
        case .searching: return "Keep this screen open"
        case .macFound:  return nil
        case .timedOut:  return "Download and open Pasture for Mac, then come back here."
        }
    }

    private var iconOpacity: Double {
        searchState == .timedOut ? 0.80 : 0.90
    }

    // MARK: - Helpers

    private func latchHelpers(_ helpers: [LoomPeerSnapshot]) {
        guard !helpers.isEmpty else { return }
        stickyHelpers = helpers
        searchState = .macFound
    }

    // MARK: - Download URL

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

private struct MacConnectButton: View {
    let peer: LoomPeerSnapshot
    let palette: EnvironmentPalette
    let reduceTransparency: Bool
    @EnvironmentObject private var connection: ConnectionManager

    var body: some View {
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 32)

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
                        ForEach(stickyHelpers, id: \.id) { peer in
                            MacConnectButton(peer: peer, palette: palette, reduceTransparency: reduceTransparency)
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
        }
        .onChange(of: connection.availableHelpers) { _, helpers in
            latchHelpers(helpers)
        }
    }


    // MARK: - Helpers

    private func latchHelpers(_ helpers: [LoomPeerSnapshot]) {
        if !helpers.isEmpty { stickyHelpers = helpers }
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
