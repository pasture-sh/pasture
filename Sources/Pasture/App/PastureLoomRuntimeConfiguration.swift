import Foundation
import Loom
import LoomKit
import LoomCloudKit

enum PastureLoomRuntimeConfiguration {
    static let serviceType = "_pasture._tcp"
    static let serviceMetadata = ["service": "pasture"]
    static let cloudKitContainerInfoKey = "PastureCloudKitContainerIdentifier"
    static let tailscaleHostnameKey = "pasture.tailscale.hostname"

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

    /// Overlay directory that probes Tailscale (or any overlay) hosts.
    /// The seed provider reads from UserDefaults on every refresh, so the user
    /// can enter or change their Mac's Tailscale hostname in settings at any time
    /// and Loom will pick it up within the next 30-second refresh cycle.
    static func overlayDirectoryConfiguration() -> LoomOverlayDirectoryConfiguration {
        LoomOverlayDirectoryConfiguration(
            probePort: Loom.defaultOverlayProbePort,
            refreshInterval: .seconds(30),
            probeTimeout: .seconds(3),
            seedProvider: {
                guard let hostname = UserDefaults.standard.string(forKey: tailscaleHostnameKey),
                      !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return [] }
                return [LoomOverlaySeed(host: hostname.trimmingCharacters(in: .whitespacesAndNewlines))]
            }
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
