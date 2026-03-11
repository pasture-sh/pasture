import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        self.isEnabled = service.status == .enabled
    }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }

            isEnabled = service.status == .enabled
            errorMessage = nil
        } catch {
            isEnabled = service.status == .enabled
            errorMessage = "Couldn’t update launch-at-login: \(error.localizedDescription)"
        }
    }
}
