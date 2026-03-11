import XCTest
@testable import Pasture

final class ConnectionRuntimePolicyTests: XCTestCase {
    func testShouldNotScheduleReconnectBeforeFirstConnection() {
        let shouldSchedule = ConnectionRuntimePolicy.shouldScheduleReconnect(
            hasEverConnected: false,
            reconnectAttempt: 0
        )

        XCTAssertFalse(shouldSchedule)
    }

    func testShouldScheduleReconnectUpToMaxAttempts() {
        XCTAssertTrue(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: true,
                reconnectAttempt: 0,
                maxReconnectAttempts: 6
            )
        )

        XCTAssertTrue(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: true,
                reconnectAttempt: 5,
                maxReconnectAttempts: 6
            )
        )

        XCTAssertFalse(
            ConnectionRuntimePolicy.shouldScheduleReconnect(
                hasEverConnected: true,
                reconnectAttempt: 6,
                maxReconnectAttempts: 6
            )
        )
    }

    func testReconnectDelayBackoffCapsAtEightSeconds() {
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 1), 1.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 2), 2.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 3), 4.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 4), 8.0, accuracy: 0.001)
        XCTAssertEqual(ConnectionRuntimePolicy.delaySeconds(forReconnectAttempt: 7), 8.0, accuracy: 0.001)
    }

    func testProxyErrorTimeoutMessageIsUserFacing() {
        let description = ProxyError.timeout.errorDescription
        XCTAssertEqual(description, "Request timed out while waiting for your Mac.")
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
}
