import SwiftUI
import LoomKit
import SwiftData

@main
struct PastureApp: App {
    private let loomContainer: LoomContainer
    private let modelContainer: ModelContainer
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

        // Explicitly disable CloudKit for SwiftData. The iCloud entitlement is
        // required by Loom for peer discovery, but its presence makes
        // .modelContainer(for:) auto-enable CloudKit sync. Our @Model schema
        // uses @Attribute(.unique) on id, which CloudKit doesn't support, and
        // saves fail silently against the auto-CloudKit store.
        let schema = Schema([ConversationRecord.self, MessageRecord.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("[Pasture] Failed to initialise SwiftData container: \(error)")
        }

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
        .modelContainer(modelContainer)
    }
}
