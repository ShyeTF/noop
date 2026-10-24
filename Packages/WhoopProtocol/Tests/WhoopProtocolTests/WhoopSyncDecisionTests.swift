import XCTest
@testable import WhoopProtocol

final class WhoopSyncDecisionTests: XCTestCase {
    private let now: TimeInterval = 1_700_000_000

    func testForegroundOpenNeverSyncs() {
        XCTAssertFalse(WhoopSyncDecision.allows(.foregroundOpen, inForeground: true, now: now, lastSyncAt: nil))
        XCTAssertFalse(WhoopSyncDecision.allows(.foregroundOpen, inForeground: false, now: now, lastSyncAt: nil))
    }

    func testStrapEventIsLiveOnlyInForeground() {
        XCTAssertFalse(WhoopSyncDecision.allows(.strapEvent, inForeground: true, now: now, lastSyncAt: nil))
        XCTAssertTrue(WhoopSyncDecision.allows(.strapEvent, inForeground: false, now: now, lastSyncAt: nil))
    }

    func testBackgroundWakeIsThrottledToFifteenMinutes() {
        let recent = now - (WhoopSyncDecision.backgroundInterval - 1)
        XCTAssertFalse(WhoopSyncDecision.allows(.backgroundWake, inForeground: false, now: now, lastSyncAt: recent))
        XCTAssertFalse(WhoopSyncDecision.allows(.strapEvent, inForeground: false, now: now, lastSyncAt: recent))
        let cooled = now - WhoopSyncDecision.backgroundInterval
        XCTAssertTrue(WhoopSyncDecision.allows(.backgroundWake, inForeground: false, now: now, lastSyncAt: cooled))
        XCTAssertFalse(WhoopSyncDecision.allows(.backgroundWake, inForeground: true, now: now, lastSyncAt: cooled))
    }

    func testForegroundReturnCatchesUpEvenAfterAShortGap() {
        let recent = now - 30 * 60
        XCTAssertTrue(WhoopSyncDecision.allows(.deferredCatchUp, inForeground: true, now: now, lastSyncAt: recent))
        let small = now - (2 * 60 * 60 - 1)
        XCTAssertTrue(WhoopSyncDecision.allows(.deferredCatchUp, inForeground: true, now: now, lastSyncAt: small))
        let large = now - WhoopSyncDecision.largeGap
        XCTAssertTrue(WhoopSyncDecision.allows(.deferredCatchUp, inForeground: true, now: now, lastSyncAt: large))
        XCTAssertFalse(WhoopSyncDecision.allows(.deferredCatchUp, inForeground: false, now: now, lastSyncAt: large))
        XCTAssertTrue(WhoopSyncDecision.allows(.deferredCatchUp, inForeground: true, now: now, lastSyncAt: nil))
        XCTAssertEqual(WhoopSyncDecision.foregroundRetryFloor, 90)
    }

    func testBackgroundRelaunchLeavesHistoryOpen() {
        XCTAssertFalse(WhoopSyncDecision.isInForeground(applicationIsActive: false))
        XCTAssertTrue(WhoopSyncDecision.isInForeground(applicationIsActive: true))
        let now: TimeInterval = 1_700_000_000
        XCTAssertTrue(WhoopSyncDecision.allows(.strapEvent, inForeground: false, now: now, lastSyncAt: nil))
        XCTAssertTrue(WhoopSyncDecision.allows(.backgroundWake, inForeground: false, now: now, lastSyncAt: nil))
        XCTAssertFalse(WhoopSyncDecision.allows(.strapEvent, inForeground: true, now: now, lastSyncAt: nil))
    }

    func testCatchUpWaitsForAStableLinkThenRetries() {
        XCTAssertEqual(
            WhoopCatchUp.next(
                inForeground: true, connected: false, bonded: false, backfilling: false,
                gapIsLarge: true, stableSeconds: 0, failedAttempts: 0),
            .wait(WhoopSyncDecision.liveSettleDelay))
        XCTAssertEqual(
            WhoopCatchUp.next(
                inForeground: true, connected: true, bonded: true, backfilling: false,
                gapIsLarge: true, stableSeconds: 1, failedAttempts: 0),
            .wait(4))
        XCTAssertEqual(
            WhoopCatchUp.next(
                inForeground: true, connected: true, bonded: true, backfilling: true,
                gapIsLarge: true, stableSeconds: 6, failedAttempts: 0),
            .wait(WhoopCatchUp.backoff(afterFailedAttempts: 0)))
        XCTAssertEqual(
            WhoopCatchUp.next(
                inForeground: true, connected: true, bonded: true, backfilling: false,
                gapIsLarge: true, stableSeconds: 5, failedAttempts: 0),
            .start)
        XCTAssertEqual(
            WhoopCatchUp.next(
                inForeground: false, connected: true, bonded: true, backfilling: false,
                gapIsLarge: true, stableSeconds: 5, failedAttempts: 0),
            .giveUp)
        XCTAssertEqual(
            WhoopCatchUp.next(
                inForeground: true, connected: true, bonded: true, backfilling: false,
                gapIsLarge: true, stableSeconds: 5, failedAttempts: 3),
            .giveUp)
        XCTAssertEqual(WhoopCatchUp.backoff(afterFailedAttempts: 1), 10, accuracy: 0.001)
    }

    func testManualAlwaysRuns() {
        XCTAssertTrue(WhoopSyncDecision.allows(.manual, inForeground: true, now: now, lastSyncAt: now))
        XCTAssertTrue(WhoopSyncDecision.allows(.manual, inForeground: false, now: now, lastSyncAt: now))
    }
}
