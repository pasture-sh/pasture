# Pasture Runtime Validation Checklist

Last updated: March 11, 2026

This checklist is for validating the production runtime behavior of:
- `Pasture` (iOS)
- `PastureHelper` (macOS)
- Loom/LoomKit transport and Ollama proxying under failure conditions

## Prerequisites

- Mac and iPhone are on the same Wi-Fi network.
- Ollama is installed on Mac and reachable at `http://localhost:11434`.
- `PastureHelper` is running in menu bar.
- `Pasture` is installed on iPhone.
- At least one model is available in Ollama (for chat tests), or model download is available (for pull tests).

## Observe Diagnostics During Tests

- iOS: `Settings` -> `Advanced Diagnostics` (inside app settings sheet).
- macOS: menu bar popover -> `Advanced diagnostics`.

Use these to confirm counters and event logs move as expected.

## Baseline Success Path

1. Open `PastureHelper` on Mac.
2. Open `Pasture` on iPhone.
3. Verify auto-discovery and auto-connect for single-Mac flow.
4. Send `hello` in chat and confirm streamed response.
5. Open iOS settings and refresh models.

Expected:
- iOS state transitions: discovering -> connecting -> connected.
- Chat stream finishes without timeout.
- `connectSuccesses` and `responsesReceived` counters increase.

## Failure Matrix

### 1. Helper restart during active chat

1. Start a long chat response from iPhone.
2. Quit `PastureHelper` while stream is active.
3. Re-open `PastureHelper`.

Expected:
- iOS stream ends with user-facing interruption message.
- iOS enters reconnecting state, then reconnects automatically.
- New chats succeed after reconnect.

Diagnostics to check:
- iOS: `disconnects`, `reconnectSchedules`, `connectSuccesses` increase.
- Mac: incoming/disconnection counters update.

### 2. Ollama down while helper remains running

1. With both apps connected, stop Ollama on Mac.
2. Attempt `fetch models`, `chat`, and `download` from iPhone.

Expected:
- User-facing error appears quickly (no silent hang).
- App remains connected at Loom layer but operations fail gracefully.
- Restarting Ollama restores operations without relaunching apps.

Diagnostics to check:
- Mac: `unreachableChecks` increases.
- iOS/macOS: remote/handler error counters increase.

### 3. Wi-Fi interruption on iPhone

1. With active connection, disable Wi-Fi on iPhone for ~10-20 seconds.
2. Re-enable Wi-Fi.

Expected:
- iOS shows reconnecting/recovery messaging.
- Connection recovers automatically without manual peer selection.
- Chat resumes on next request.

Diagnostics to check:
- iOS reconnect counters increase.
- No crash, no frozen UI.

### 4. Cancel model pull from iOS first-model setup

1. Start model download from first-model onboarding/setup UI.
2. Tap `Cancel` during active download.

Expected:
- Download stops.
- UI resets cleanly and allows restart.
- Cancellation message appears (not generic failure).

Diagnostics to check:
- iOS `pullStreamCancellations` increases.
- Mac proxy `cancelRequests` and/or `streamCancellations` increase.

### 5. Cancel model pull from iOS settings

1. Start model download in settings.
2. Tap `Cancel`.

Expected:
- Same behavior as test #4.
- No stale active download state.

### 6. Cancel model pull from macOS model manager

1. Open `Manage Models` on Mac.
2. Start download and cancel from Mac UI.

Expected:
- Download stops immediately.
- Error state is cancellation-specific.
- New download can start right away.

### 7. Reconnect after helper discovery pause toggle

1. In macOS popover, enable `Pause discovery`.
2. Confirm iOS disconnects/fails to find helper.
3. Disable `Pause discovery`.

Expected:
- iOS rediscovers and reconnects automatically.
- No app restart needed.

### 8. Timeout behavior when helper stops responding

1. Force an operation that will not receive response (temporary code-level simulation if needed).
2. Wait for timeout.

Expected:
- iOS surfaces timeout error.
- Pending request does not remain stuck forever.

Diagnostics to check:
- iOS `requestTimeouts` increments.

## Pass Criteria (Release Gate)

Ship runtime as ironclad only when all are true:

- No crashes across all tests above.
- Reconnect works automatically in tests #1, #3, and #7.
- Cancellation is deterministic in tests #4, #5, and #6.
- Timeout/error states are explicit and user-facing.
- Diagnostics counters/events align with observed behavior.

## Regression Smoke (after each major UI/design pass)

Run minimum subset:
- Baseline success path
- Helper restart during chat
- Wi-Fi interruption
- iOS pull cancel
