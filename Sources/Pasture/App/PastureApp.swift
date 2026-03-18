import SwiftUI
import LoomKit
import SwiftData

@main
struct PastureApp: App {
    private let loomContainer: LoomContainer
    @StateObject private var connectionManager: ConnectionManager

    init() {
        let container = try! LoomContainer(
            for: PastureLoomRuntimeConfiguration.makeConfiguration(
                serviceName: UIDevice.current.name
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
