import Foundation
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
            trust: .sameAccountAutoTrust,
            advertisementMetadata: serviceMetadata
        )
    }

    static func cloudKitConfiguration(bundle: Bundle = .main) -> LoomCloudKitConfiguration? {
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
