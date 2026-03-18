# Pasture Handover for Claude Code

## Product Intent

Pasture is an iOS app with a macOS companion that makes Ollama feel normie-friendly:

- zero-config discovery of a Mac running Ollama
- private/local AI from iPhone to Mac without IP addresses or server URLs
- thoughtful, premium-feeling UI inspired by the calm atmosphere of Alto's Odyssey
- pro-capable underneath, but never intimidating on first use

Current naming assumption:

- app name stays `Pasture`
- website/domain: `pasture.sh`

## Repository

- Root: `/Users/amrith/Pasture`
- Xcode project is generated with XcodeGen from `project.yml`
- Regenerate after project spec edits:

```bash
cd /Users/amrith/Pasture
xcodegen generate
```

## Targets

### `Pasture`

- Platform: iOS 17.4+
- Responsibilities:
  - onboarding and discovery
  - connection management via LoomKit
  - chat UI
  - model selection / first model setup
  - runtime diagnostics
  - local persistence via SwiftData

### `PastureHelper`

- Platform: macOS 14+
- Responsibilities:
  - menu bar companion app
  - advertises presence via LoomKit
  - proxies structured requests to local Ollama on `localhost:11434`
  - reports helper diagnostics

## Core Architecture

### Transport

- Uses `Loom`, `LoomKit`, and `LoomCloudKit`
- Service type: `_pasture._tcp`
- Same-account auto-trust is intended architecture

Current nuance:

- Nearby discovery works
- same-account auto-trust is only fully active once a real CloudKit container is configured in Apple Developer + Xcode signing/capabilities

### Wire Protocol

JSON over Loom connection.

- iPhone -> Mac: `ProxyRequest`
- Mac -> iPhone: `ProxyResponse`

Request types:

- `tags`
- `chat`
- `pull`
- `delete`
- `cancel`

Response types:

- `tags`
- `chat`
- `pull`
- `delete`
- `cancel`
- `error`

### Ollama integration

The helper talks to Ollama's local HTTP API.

Key file:

- `Sources/PastureHelper/Ollama/OllamaAPIClient.swift`

This file is already solid and handles:

- installed model listing
- streaming chat
- streaming pull progress
- delete
- reachability checks

## Current Status

### Working

- iPhone discovers Mac helper on local network
- iPhone connects to helper
- helper proxies requests to Ollama
- chat works end-to-end on physical devices
- streaming responses work
- model listing works
- model pull/delete plumbing exists
- diagnostics exist on both iOS and macOS
- automated local pipeline passes:
  - iOS tests
  - macOS helper build

### Recently fixed

- Keychain/signing issues for Loom identity
- helper peer filtering bug on iPhone discovery
- stale Loom socket handling / reconnect behavior
- duplicate model fetch race
- CI brittleness around missing `Package.resolved` on clean runners
- readability and environment contrast pass
- horizon edge overscan fix
- keyboard dismissal support
- streaming Markdown rendering during generation

### Not production-ready yet

- conversation home screen
- multi-conversation persistence UX
- full macOS visual polish
- final design polish pass
- app icon / brand assets / screenshots
- App Store Connect / signing / distribution setup
- real CloudKit container configuration
- TestFlight/App Store metadata and compliance

## Important Files

### iOS

- `Sources/Pasture/App/PastureApp.swift`
- `Sources/Pasture/App/PastureLoomRuntimeConfiguration.swift`
- `Sources/Pasture/Networking/ConnectionManager.swift`
- `Sources/Pasture/Discovery/RootView.swift`
- `Sources/Pasture/Chat/ChatView.swift`
- `Sources/Pasture/Chat/ChatViewModel.swift`
- `Sources/Pasture/Design/ModelEnvironment.swift`
- `Sources/Pasture/Design/EnvironmentBackground.swift`
- `Sources/Pasture/Persistence/ConversationHistoryRecord.swift`

### macOS

- `Sources/PastureHelper/App/PastureHelperApp.swift`
- `Sources/PastureHelper/App/PastureLoomRuntimeConfiguration.swift`
- `Sources/PastureHelper/Networking/LoomAdvertiser.swift`
- `Sources/PastureHelper/Networking/OllamaProxy.swift`
- `Sources/PastureHelper/Ollama/OllamaAPIClient.swift`
- `Sources/PastureHelper/MenuBar/MenuBarPopoverView.swift`

### Project / CI / docs

- `project.yml`
- `.github/workflows/ci.yml`
- `scripts/test_all.sh`
- `scripts/check_loom_consistency.sh`
- `docs/loom-integration.md`
- `docs/runtime-validation-checklist.md`
- `docs/test-automation.md`

## Design Direction

The current direction is intentionally restrained.

### Desired feeling

Pasture should feel:

- pastoral
- premium
- minimalist
- closer to Alto's Odyssey than Alto's Adventure
- Apple-native in behavior
- indie/artful in atmosphere

### Current design rules

- environment carries mood
- chrome carries function
- content stays quiet
- llama presence only in onboarding / empty states
- chat should be less decorative than onboarding
- motion should be very subtle

### Current visual system

- time-of-day driven environment palettes
- softer late-night mode after midnight to 5 AM
- abstract horizon rather than literal decorative scenery
- Liquid Glass only for selected chrome, not everywhere

### Design work still needed

- more contrast tuning on real devices
- typography spacing refinement
- more disciplined settings and diagnostics styling
- macOS parity pass
- better polish around onboarding hierarchy
- final iconography / brand system

## Persistence Status

Current persistence is intentionally minimal:

- one active conversation record is restored and updated
- messages are saved in SwiftData
- selected model and intent are persisted

But the UX is incomplete:

- there is no conversation index/home
- there is no proper multi-thread chat list
- there is no thread switching UI

This is one of the biggest product gaps remaining.

## Recommended Next Work Blocks

### 1. Build conversation home and multi-thread support

High priority.

Goal:

- Pasture opens into a calm conversation home, not directly into a single thread
- show saved conversations sorted by recency
- create / rename / delete threads
- keep one-tap jump back into chat

Recommended approach:

- extend `ConversationHistoryRecord` with fields like:
  - `title`
  - `previewText`
  - `selectedModelName`
  - `updatedAt`
- stop treating a single record as the only active thread
- introduce:
  - home screen
  - active thread selection
  - “new chat” creating a new record instead of clearing one global record

### 2. Final iOS polish pass

- readability tuning on physical devices
- better state transitions
- final onboarding polish
- chat composer polish
- consistent Markdown rendering theme

### 3. macOS polish pass

- make helper feel less provisional
- better menu bar popover hierarchy
- model management polish
- production-level copy and status treatment

### 4. CloudKit trust setup

Complete same-account auto-trust properly:

- create CloudKit container in Apple Developer
- add container identifier to both targets
- enable iCloud + CloudKit capabilities
- validate first-run same-account pairing end-to-end

### 5. Distribution readiness

- App Store Connect records
- signing and bundle hygiene
- versioning strategy
- privacy policy
- support URL
- screenshots
- TestFlight internal distribution

## Known Sharp Edges

- `MarkdownUI` requires explicit theming; inherited foreground color is not reliable enough
- fresh CI runners do not necessarily have `Package.resolved` before package resolution
- physical-device validation still matters for Loom behavior; simulator is not a substitute for transport validation
- the UI is improved but not yet at final craft level

## CI Status

CI workflow:

- `.github/workflows/ci.yml`

Current fix:

- `scripts/check_loom_consistency.sh` now resolves package dependencies if `Package.resolved` is missing on a clean runner

Known warning:

- GitHub currently warns about Node 20 deprecation on `actions/checkout@v4`
- this is not the current cause of failure
- safe follow-up is to monitor/upgrade the action version when GitHub ships Node 24-compatible defaults

## Local Validation Commands

```bash
./scripts/check_loom_consistency.sh
./scripts/test_all.sh
```

Manual device validation still needed for:

- discovery/reconnect after sleep or Wi-Fi changes
- chat streaming on long responses
- model pull/cancel/delete flows
- readability across different times of day

## Apple / Signing Notes

For local device runs:

- both `Pasture` and `PastureHelper` need a valid Apple Team selected in Xcode
- Loom identity storage relies on signed builds and Keychain access

For production:

- set up proper iCloud + CloudKit capability
- replace placeholder distribution values like `PastureMacDownloadURL`
- verify all bundle identifiers and entitlements

## Recommended Claude Code Brief

If Claude takes over, the right brief is:

1. Do not rewrite the transport stack from scratch.
2. Keep Loom/LoomKit architecture intact.
3. Preserve the zero-config normie-first product goal.
4. Prioritize:
   - conversation home
   - multi-thread persistence
   - final iOS polish
   - macOS parity
   - TestFlight/App Store readiness
5. Use the existing code as the base, not as a throwaway prototype.

## Bottom Line

Pasture is now a real product foundation, not just a concept:

- discovery works
- chat works
- the helper works
- CI is in place
- the design direction is established

The remaining work is productization and polish:

- conversation UX
- final craft
- distribution
- production readiness
