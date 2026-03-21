import SwiftUI

struct OnboardingView: View {
    let onGetStarted: () -> Void

    @State private var ollamaState: OllamaCheckState = .checking
    private let accentGreen = Color(red: 0.690, green: 0.894, blue: 0.416)

    enum OllamaCheckState {
        case checking, running, notRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 36)
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                stepCard(
                    icon: "leaf.fill",
                    iconColor: accentGreen,
                    title: "Lives in your menu bar",
                    body: "Pasture runs quietly in the background. Look for the green leaf icon in your menu bar at any time."
                )

                ollamaStepCard

                stepCard(
                    icon: "iphone",
                    iconColor: .blue,
                    title: "Connect your iPhone",
                    body: "Install Pasture on your iPhone and open it — your Mac and iPhone will find each other automatically on the same Wi-Fi network."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentGreen)
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(width: 480, height: 420)
        .fontDesign(.rounded)
        .task { await checkOllama() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 36))
                .foregroundStyle(accentGreen)

            Text("Welcome to Pasture")
                .font(.system(.title2, design: .rounded, weight: .bold))

            Text("Ollama on your iPhone, wherever you go.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var ollamaStepCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.purple)
                .frame(width: 28)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ollama powers the AI")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))

                switch ollamaState {
                case .checking:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking for Ollama…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .running:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Ollama is running — you're all set.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .notRunning:
                    Text("Ollama needs to be running on your Mac for Pasture to work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
                            Button("Open Ollama") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
                                Task { await checkOllama() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentGreen)
                            .foregroundStyle(.black.opacity(0.8))
                            .controlSize(.small)
                        }

                        Button("Download Ollama →") {
                            NSWorkspace.shared.open(URL(string: "https://ollama.com")!)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func stepCard(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func checkOllama() async {
        ollamaState = .checking
        let reachable = await OllamaAPIClient.shared.isReachable()
        ollamaState = reachable ? .running : .notRunning
    }
}
