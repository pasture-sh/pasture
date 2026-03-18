# Pasture

Pasture is a calm, modern Ollama client for iPhone with a Mac companion.

The goal is simple: make local AI feel welcoming, private, and easy to use.
Open the app, find your Mac automatically, and start chatting without fiddling
with IP addresses, server URLs, or extra setup.

## What It Is

- `Pasture` for iOS: chat, onboarding, discovery, and model setup
- `Pasture for Mac`: menu bar companion that connects to your local Ollama instance

Pasture is designed for people who want things to just work, while still being
good enough that more technical users can appreciate the craft.

## Design Direction

Pasture is intentionally quiet:

- soft, time-of-day-aware environments
- minimal, native-feeling UI
- private, local-first interaction model
- normie-friendly onboarding with power-user depth kept out of the way

## Status

The core product is working:

- iPhone to Mac discovery
- pairing and connection
- Ollama chat from iOS
- model listing and basic model management

Pasture is still being polished toward production readiness.

## Development

This project uses XcodeGen.

Regenerate the Xcode project after editing `project.yml`:

```bash
xcodegen generate
```

Run the automated checks:

```bash
./scripts/test_all.sh
```

## Notes

- Pasture is built around local/private AI workflows
- the Mac app expects Ollama to be installed and available locally
- this repo contains both the iOS app and the macOS companion
