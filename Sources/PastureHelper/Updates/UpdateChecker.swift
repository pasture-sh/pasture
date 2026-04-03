import Foundation

/// Checks GitHub Releases for a newer version of PastureHelper.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var updateAvailable: AvailableUpdate?
    @Published private(set) var isChecking = false

    private let currentVersion: String
    private let releasesURL = URL(string: "https://api.github.com/repos/pasture-sh/pasture/releases/latest")!
    private let downloadURL = URL(string: "https://github.com/pasture-sh/pasture/releases/latest/download/PastureHelper.dmg")!

    struct AvailableUpdate {
        let version: String
        let downloadURL: URL
    }

    init() {
        self.currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(latestVersion, than: currentVersion) {
                updateAvailable = AvailableUpdate(version: latestVersion, downloadURL: downloadURL)
            } else {
                updateAvailable = nil
            }
        } catch {
            // Silently fail — update check is best-effort
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
