# Pasture

**Your local AI, wherever you roam.**

Pasture is a calm, private Ollama client for iPhone with a Mac companion. Open the app, find your Mac automatically, and start chatting — no IP addresses, no server URLs, no extra setup.

---

## What It Does

Pasture connects your iPhone to [Ollama](https://ollama.com) running on your Mac over your local network. You get a clean, native chat interface on iOS while Ollama does all the heavy lifting on the Mac. Your conversations never leave your home network.

It's designed to feel approachable for anyone curious about local AI, while being polished enough that developers will appreciate the craft underneath.

---

## The Apps

**Pasture for iOS**
Chat interface, model browser, onboarding, and automatic Mac discovery. Available via [TestFlight](https://pasture.sh).

**Pasture for Mac**
A lightweight menu bar companion that connects to your local Ollama instance and makes it available to the iOS app. Available as a [direct download](https://github.com/pasture-sh/pasture/releases/latest/download/PastureHelper.dmg).

---

## Getting Started

1. **Install Ollama** on your Mac — [ollama.com](https://ollama.com)
2. **Download Pasture for Mac** — [PastureHelper.dmg](https://github.com/pasture-sh/pasture/releases/latest/download/PastureHelper.dmg) — open it and move it to your Applications folder
3. **Install Pasture for iOS** via [TestFlight](https://pasture.sh) on your iPhone
4. Make sure both devices are on the same Wi-Fi network, then open Pasture on your iPhone — it will find your Mac automatically

---

## Requirements

- iPhone running iOS 17.4 or later
- Mac running macOS 14 (Sonoma) or later
- [Ollama](https://ollama.com) installed and running on the Mac
- An iCloud account (used for secure pairing between devices)

---

## How It Works

For those who want to look under the hood:

**Discovery**
Pasture uses Apple's [MultipeerConnectivity](https://developer.apple.com/documentation/multipeerconnectivity) framework alongside Bonjour service browsing (`_pasture._tcp`) to find the Mac app on the local network without any manual configuration. When Tailscale is running, it extends this to work over VPN as well.

**Sync & Pairing**
Device pairing state is stored in iCloud via [CloudKit](https://developer.apple.com/icloud/cloudkit/), using [Loom](https://github.com/EthanLipnik/Loom) — a CloudKit persistence library — to manage sync cleanly across the iOS and macOS targets.

**Security**
The Mac app runs in a full [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) with hardened runtime enabled. It's signed with a Developer ID certificate and notarized by Apple, so macOS Gatekeeper will accept it without warnings on first launch.

**Project structure**
Both apps live in a single Xcode project generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). Shared networking and model code lives in `PastureShared` / `PastureSharedMac` static library targets. The entire codebase is written in Swift 6.0 with strict concurrency enabled.

**Dependencies**
- [Loom](https://github.com/EthanLipnik/Loom) — CloudKit persistence and sync
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — Markdown rendering in chat

---

## Development

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen). After cloning, regenerate the Xcode project:

```bash
brew install xcodegen
xcodegen generate
```

Run the automated checks (builds, lints, and runs the iOS test suite on a simulator):

```bash
./scripts/test_all.sh
```

---

## Status

Pasture is in active development and open beta. Core functionality is stable:

- Automatic iPhone-to-Mac discovery and pairing
- Ollama chat from iOS
- Model listing and basic management
- Time-of-day-aware environments
- Tailscale support for remote access

Contributions, bug reports, and feedback are welcome.
