import SwiftUI
import LoomKit
import SwiftData

@main
struct PastureApp: App {
    private let loomContainer: LoomContainer
    @StateObject private var connectionManager: ConnectionManager

    init() {
        let container = try! LoomContainer(
            for: LoomContainerConfiguration(
                serviceType: "_pasture._tcp",
                serviceName: UIDevice.current.name,
                trust: .sameAccountAutoTrust,
                advertisementMetadata: ["service": "pasture"]
            )
        )
        self.loomContainer = container
        _connectionManager = StateObject(
            wrappedValue: ConnectionManager(loomContext: container.mainContext)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connectionManager)
        }
        .loomContainer(loomContainer, autostart: false)
        .modelContainer(for: [ConversationHistoryRecord.self])
    }
}
