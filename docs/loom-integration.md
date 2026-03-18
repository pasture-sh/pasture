# Loom Integration

Pasture treats Loom as infrastructure, not a casual dependency. Keep the version pinned, verify behavior on physical devices after every upgrade, and use the checked-out package source for the exact pinned version as the implementation reference.

## Current policy

- `project.yml` pins Loom with `exactVersion`
- `Package.resolved` must match the same Loom version
- `scripts/check_loom_consistency.sh` enforces that internal match
- `scripts/check_loom_upstream.sh` compares the pinned version against the latest upstream tag

## Runtime assumptions

- Bonjour service type: `_pasture._tcp`
- App metadata marker: `service=pasture`
- SwiftUI runtime uses `LoomKit`
- Same-account trust is intended to be CloudKit-backed

## Important trust caveat

Pasture uses `trust: .sameAccountAutoTrust`, but that only behaves as intended when `PastureCloudKitContainerIdentifier` is set and the Apple capabilities are configured for both app targets. Without a CloudKit container:

- nearby discovery can still function
- same-account auto-trust is not actually available
- shared-peer features are unavailable

This is surfaced in-app as a diagnostic warning.

## Upgrade workflow

1. Run `./scripts/check_loom_consistency.sh`
2. Run `./scripts/check_loom_upstream.sh`
3. If upstream is newer, create an upgrade branch
4. Update `project.yml`
5. Regenerate the Xcode project with `xcodegen generate`
6. Resolve packages in Xcode or via `xcodebuild -resolvePackageDependencies`
7. Run `./scripts/test_all.sh`
8. Validate on physical Mac + iPhone:
   - helper advertisement
   - iPhone discovery
   - first-time pairing/trust
   - reconnect after Wi-Fi toggle
   - streaming chat
   - model download/delete

## Source of truth

When Loom behavior is unclear, inspect the checked-out package source in Xcode's `SourcePackages/checkouts/Loom` directory for the exact pinned version rather than relying on memory or old snippets.
