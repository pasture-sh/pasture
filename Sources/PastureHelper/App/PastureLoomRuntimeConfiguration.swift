import Foundation
import Loom
import LoomKit
import LoomCloudKit

enum PastureLoomRuntimeConfiguration {
    static let serviceType = "_pasture._tcp"
    static let serviceMetadata = ["service": "pasture"]
    static let cloudKitContainerInfoKey = "PastureCloudKitContainerIdentifier"

    static func makeConfiguration(
        serviceName: String,
        bundle: Bundle = .main
    ) -> LoomContainerConfiguration {
        LoomContainerConfiguration(
            serviceType: serviceType,
            serviceName: serviceName,
            cloudKit: cloudKitConfiguration(bundle: bundle),
            overlayDirectory: overlayDirectoryConfiguration(),
            trust: .sameAccountAutoTrust,
            advertisementMetadata: serviceMetadata
        )
    }

    /// On the Mac, we always start the overlay probe server so iPhones can
    /// discover this Mac via Tailscale or any other overlay network.
    /// The seed provider is empty because the Mac is the host, not the seeker.
    static func overlayDirectoryConfiguration() -> LoomOverlayDirectoryConfiguration {
        LoomOverlayDirectoryConfiguration(
            probePort: Loom.defaultOverlayProbePort,
            seedProvider: { [] }
        )
    }

    static func cloudKitConfiguration(bundle: Bundle = .main) -> LoomCloudKitConfiguration? {
        // XCTest sets this environment variable. Without proper code signing (CODE_SIGNING_ALLOWED=NO),
        // entitlements aren't embedded and CKContainer initialization crashes immediately.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }

        guard let containerIdentifier = bundle.object(
            forInfoDictionaryKey: cloudKitContainerInfoKey
        ) as? String else {
            return nil
        }

        let trimmed = containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return LoomCloudKitConfiguration(
            containerIdentifier: trimmed,
            shareTitle: "Pasture Device Access"
        )
    }

    static func runtimeWarning(bundle: Bundle = .main) -> String? {
        guard cloudKitConfiguration(bundle: bundle) == nil else { return nil }
        return "Same-account auto-trust is enabled, but this build has no CloudKit container configured. Nearby discovery can still work, but same-account trust and shared-peer features are unavailable until PastureCloudKitContainerIdentifier is set."
    }
}
