import SwiftUI
import LoomKit
import SwiftData

@main
struct PastureApp: App {
    private let loomContainer: LoomContainer
    @StateObject private var connectionManager: ConnectionManager

    init() {
        let container: LoomContainer
        do {
            container = try LoomContainer(
                for: PastureLoomRuntimeConfiguration.makeConfiguration(
                    serviceName: UIDevice.current.name
                )
            )
        } catch {
            fatalError("[Pasture] Failed to initialise Loom. In Xcode, ensure the correct Apple Team is selected under target → Signing & Capabilities. Error: \(error)")
        }
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
        .modelContainer(for: [ConversationRecord.self, MessageRecord.self])
    }
}
