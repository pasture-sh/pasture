# Test Automation

## What is automated

The following checks are automated and can run locally or in CI:

1. iOS simulator unit tests for runtime policy + cancel/timeout behavior.
2. macOS `PastureHelper` build sanity check.

## Run locally

From the project root:

```bash
./scripts/test_all.sh
```

You can also run each part directly:

```bash
./scripts/test_ios_sim.sh
./scripts/build_macos_helper.sh
```

Optional: force a specific simulator id:

```bash
IOS_SIMULATOR_ID=<SIMULATOR-UUID> ./scripts/test_ios_sim.sh
```

## CI

GitHub Actions workflow file:

- `.github/workflows/ci.yml`

It runs on every push to `main` and every pull request.

## What is still manual

Physical-device failure drills are still manual because they depend on real network/device conditions:

- helper restart mid-chat
- Wi-Fi interruptions
- Ollama process stop/start behavior
- first-model and settings download cancellation behavior on real devices

Use:

- `docs/runtime-validation-checklist.md`

for the manual production-readiness sweep.
