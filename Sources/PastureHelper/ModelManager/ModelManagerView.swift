import SwiftUI
import PastureShared

struct ModelManagerView: View {
    @StateObject private var viewModel = ModelManagerViewModel()
    @State private var selectedTab: Tab = .library
    @State private var downloadTask: Task<Void, Never>?
    private let accentColor = PastureColors.accent

    enum Tab: String, CaseIterable, Identifiable {
        case library = "Library"
        case installed = "Installed"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Model tab", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if let activeDownload = viewModel.activeDownload {
                ActiveDownloadBanner(
                    state: activeDownload,
                    accentColor: accentColor,
                    onCancel: cancelActiveDownload
                )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Group {
                switch selectedTab {
                case .library:
                    CuratedLibraryTab(viewModel: viewModel) { model in
                        startDownload(model)
                    }
                case .installed:
                    InstalledModelsTab(viewModel: viewModel, accentColor: accentColor)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .fontDesign(.rounded)
        .task {
            await viewModel.refreshInstalledModels()
        }
        .onDisappear {
            cancelActiveDownload()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pasture")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("Manage Ollama models without Terminal.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await viewModel.refreshInstalledModels() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(accentColor)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func startDownload(_ model: CuratedModel) {
        guard downloadTask == nil else { return }
        downloadTask = Task {
            await viewModel.download(model)
            await MainActor.run {
                downloadTask = nil
            }
        }
    }

    private func cancelActiveDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}

private struct CuratedLibraryTab: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    let onDownload: (CuratedModel) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(CuratedModelLibrary.recommended) { model in
                    CuratedModelRow(
                        model: model,
                        isInstalled: viewModel.isInstalled(model),
                        isDownloading: viewModel.activeDownload?.modelID == model.id,
                        accentColor: PastureColors.accent,
                        cardColor: Color(red: 0.96, green: 0.94, blue: 0.86).opacity(0.3)
                    ) {
                        onDownload(model)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct InstalledModelsTab: View {
    @ObservedObject var viewModel: ModelManagerViewModel
    let accentColor: Color
    @State private var pendingDeleteModel: OllamaModel?

    var body: some View {
        Group {
            if viewModel.isLoadingInstalled && viewModel.installedModels.isEmpty {
                ProgressView("Loading installed models…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.installedModels.isEmpty {
                ContentUnavailableView(
                    "No Models Installed",
                    systemImage: "tray",
                    description: Text("Use the Library tab to download your first model.")
                )
            } else {
                List(viewModel.installedModels) { model in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .font(.body.weight(.semibold))
                            Text(modelDescription(for: model))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(ByteCountFormatter.string(fromByteCount: model.size ?? 0, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 72, alignment: .trailing)

                        Button(role: .destructive) {
                            pendingDeleteModel = model
                        } label: {
                            if viewModel.deletingModelName == model.name {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Delete")
                            }
                        }
                        .disabled(viewModel.deletingModelName != nil)
                        .tint(accentColor)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete \(pendingDeleteModel?.name ?? "this model")?",
            isPresented: Binding(
                get: { pendingDeleteModel != nil },
                set: { if !$0 { pendingDeleteModel = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let model = pendingDeleteModel {
                Button("Delete \(model.name)", role: .destructive) {
                    Task { await viewModel.deleteInstalledModel(named: model.name) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteModel = nil }
        } message: {
            Text("This permanently removes the model from Ollama. You can re-download it later.")
        }
    }

    private func modelDescription(for model: OllamaModel) -> String {
        let family = model.details?.family?.capitalized ?? "Unknown family"
        if let parameterSize = model.details?.parameterSize {
            return "\(family) • \(parameterSize)"
        }
        return family
    }
}

private struct CuratedModelRow: View {
    let model: CuratedModel
    let isInstalled: Bool
    let isDownloading: Bool
    let accentColor: Color
    let cardColor: Color
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.displayName)
                    .font(.headline)

                Text(model.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ModelTag(text: model.sizeLabel)
                    ForEach(model.tags, id: \.self) { tag in
                        ModelTag(text: tag)
                    }
                }
            }

            Spacer()

            Button(buttonTitle, action: onDownload)
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(isInstalled || isDownloading)
        }
        .padding(14)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        }
    }

    private var buttonTitle: String {
        if isInstalled { return "Installed" }
        if isDownloading { return "Downloading" }
        return "Download"
    }
}

private struct ModelTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary.opacity(0.8))
    }
}

private struct ActiveDownloadBanner: View {
    let state: ModelDownloadState
    let accentColor: Color
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading \(state.displayName)")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let fraction = state.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
