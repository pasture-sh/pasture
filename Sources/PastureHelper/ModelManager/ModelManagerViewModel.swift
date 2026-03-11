import Foundation

@MainActor
final class ModelManagerViewModel: ObservableObject {
    @Published private(set) var installedModels: [OllamaModel] = []
    @Published private(set) var isLoadingInstalled = false
    @Published private(set) var activeDownload: ModelDownloadState?
    @Published private(set) var deletingModelName: String?
    @Published var errorMessage: String?

    var installedModelNames: Set<String> {
        Set(installedModels.map(\.name))
    }

    func refreshInstalledModels() async {
        isLoadingInstalled = true
        errorMessage = nil

        do {
            installedModels = try await OllamaAPIClient.shared.fetchTags()
                .sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        } catch {
            errorMessage = "Couldn’t load installed models: \(error.localizedDescription)"
        }

        isLoadingInstalled = false
    }

    func isInstalled(_ curatedModel: CuratedModel) -> Bool {
        installedModelNames.contains(curatedModel.id)
            || installedModelNames.contains(where: { $0.hasPrefix("\(curatedModel.id):") })
    }

    func download(_ curatedModel: CuratedModel) async {
        guard activeDownload == nil else { return }
        guard !isInstalled(curatedModel) else { return }

        activeDownload = ModelDownloadState(
            modelID: curatedModel.id,
            displayName: curatedModel.displayName,
            status: "Starting download…",
            fraction: nil
        )
        errorMessage = nil

        var didSucceed = false
        let stream = await OllamaAPIClient.shared.pull(model: curatedModel.id)

        do {
            for try await progress in stream {
                activeDownload = ModelDownloadState(
                    modelID: curatedModel.id,
                    displayName: curatedModel.displayName,
                    status: progress.status.capitalized,
                    fraction: progress.total == nil ? nil : progress.fraction
                )
                if progress.status == "success" {
                    didSucceed = true
                }
            }
        } catch {
            if error is CancellationError {
                errorMessage = "Download cancelled."
            } else {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }

        activeDownload = nil

        if didSucceed {
            await refreshInstalledModels()
        } else if errorMessage == nil {
            errorMessage = "Download ended before completion."
        }
    }

    func deleteInstalledModel(named modelName: String) async {
        guard deletingModelName == nil else { return }

        deletingModelName = modelName
        errorMessage = nil

        do {
            try await OllamaAPIClient.shared.delete(model: modelName)
            await refreshInstalledModels()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }

        deletingModelName = nil
    }
}

struct ModelDownloadState: Equatable {
    let modelID: String
    let displayName: String
    let status: String
    let fraction: Double?
}
