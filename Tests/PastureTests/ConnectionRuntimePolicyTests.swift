import XCTest
@testable import Pasture
import PastureShared

final class ConnectionRuntimePolicyTests: XCTestCase {
    func testShouldNotScheduleReconnectBeforeFirstConnection() {
        XCTAssertFalse(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: false,
                reconnectAttempt: 0
            )
        )
    }

    func testShouldScheduleReconnectUpToMaxAttempts() {
        let max = ConnectionRuntimePolicy.maxReconnectAttempts
        XCTAssertTrue(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: true,
                reconnectAttempt: 0,
                maxReconnectAttempts: max
            )
        )
        XCTAssertTrue(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: true,
                reconnectAttempt: max - 1,
                maxReconnectAttempts: max
            )
        )
        XCTAssertFalse(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: true,
                reconnectAttempt: max,
                maxReconnectAttempts: max
            )
        )
    }

    func testReconnectDelayBackoffCapsAtEightSeconds() {
        // attempt 0 is a special case that returns 1.0 without the exponential formula
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 1), 1.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 2), 2.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 3), 4.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 4), 8.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 7), 8.0, accuracy: 0.001)
    }

    func testProxyErrorDescriptions() {
        XCTAssertEqual(ProxyError.notConnected.errorDescription, "Not connected to your Mac.")
        XCTAssertEqual(ProxyError.timeout.errorDescription, "Request timed out while waiting for your Mac.")
        XCTAssertEqual(ProxyError.remote("Ollama not found").errorDescription, "Ollama not found")
    }

    func testCancelRequestRoundTripPreservesTargetRequestID() throws {
        let cancel = ProxyRequest.cancelRequest(targetRequestID: "abc-123")

        XCTAssertEqual(cancel.type, .cancel)
        XCTAssertEqual(cancel.targetRequestID, "abc-123")
        XCTAssertNil(cancel.model)
        XCTAssertNil(cancel.messages)

        let encoded = try JSONEncoder().encode(cancel)
        let decoded = try JSONDecoder().decode(ProxyRequest.self, from: encoded)

        XCTAssertEqual(decoded.type, .cancel)
        XCTAssertEqual(decoded.targetRequestID, "abc-123")
    }

    func testPullProgressFractionUsesCompletedOverTotal() {
        let progress = PullProgress(status: "downloading", total: 100, completed: 25)
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
    }

    func testPullProgressFractionFallsBackToZeroWhenMissingData() {
        XCTAssertEqual(PullProgress(status: "downloading", total: nil, completed: nil).fraction, 0)
        XCTAssertEqual(PullProgress(status: "downloading", total: 0, completed: 10).fraction, 0)
        XCTAssertEqual(PullProgress(status: "downloading", total: 100, completed: nil).fraction, 0)
    }

    func testPullProgressIsComplete() {
        XCTAssertTrue(PullProgress(status: "success", total: 100, completed: 100).isComplete)
        XCTAssertFalse(PullProgress(status: "downloading", total: 100, completed: 50).isComplete)
        XCTAssertFalse(PullProgress(status: "pulling manifest", total: nil, completed: nil).isComplete)
    }

    func testModelDownloadStateUpdating() throws {
        let state = ModelDownloadState(
            modelID: "llama3",
            displayName: "Llama 3",
            status: "Starting download…",
            fraction: nil
        )

        // Normal progress: status is capitalized, fraction is computed from completed/total
        let updated = state.updating(with: PullProgress(status: "downloading", total: 100, completed: 50))
        XCTAssertEqual(updated.status, "Downloading")
        XCTAssertEqual(try XCTUnwrap(updated.fraction), 0.5, accuracy: 0.0001)
        XCTAssertEqual(updated.modelID, state.modelID)
        XCTAssertEqual(updated.displayName, state.displayName)

        // When total is nil, fraction must be nil (indeterminate progress bar, not 0%)
        let indeterminate = state.updating(with: PullProgress(status: "pulling manifest", total: nil, completed: nil))
        XCTAssertEqual(indeterminate.status, "Pulling Manifest")
        XCTAssertNil(indeterminate.fraction)
    }
}
