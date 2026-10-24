import XCTest
@testable import WhoopProtocol

final class WhoopHistoryRecoveryTests: XCTestCase {
    func testOneMissingHeartBucketStaysOneCurveAndALongHoleSplits() {
        let start: TimeInterval = 1_700_000_000
        let five = 5 * 60.0
        let steady = [start, start + five, start + 2 * five, start + 4 * five, start + 5 * five]
        let steadyGap = WhoopChartGaps.gap(at: steady, base: WhoopChartGaps.heartSeconds)
        XCTAssertEqual(WhoopChartGaps.segments(at: steady, maxGap: steadyGap), [0, 0, 0, 0, 0])
        XCTAssertEqual(WhoopChartGaps.heartSeconds, 10 * 60)
        let hole = [start, start + five, start + 2 * five, start + 2 * five + 3 * 60 * 60]
        let holeGap = WhoopChartGaps.gap(at: hole, base: WhoopChartGaps.heartSeconds)
        XCTAssertEqual(WhoopChartGaps.segments(at: hole, maxGap: holeGap), [0, 0, 0, 1])
    }

    func testSparseDailySeriesStaysOneCurveUntilTheHoleExceedsThreeMedianSteps() {
        let start: TimeInterval = 1_700_000_000
        let day: TimeInterval = 24 * 60 * 60
        let sparse = [start, start + 3 * day, start + 6 * day, start + 9 * day]
        let sparseGap = WhoopChartGaps.gap(at: sparse, base: WhoopChartGaps.daySeconds)
        XCTAssertEqual(WhoopChartGaps.segments(at: sparse, maxGap: sparseGap), [0, 0, 0, 0])
        var daily: [TimeInterval] = (0..<7).map { start + TimeInterval($0) * day }
        daily.append(start + 7 * day + 40 * day)
        let dailyGap = WhoopChartGaps.gap(at: daily, base: WhoopChartGaps.daySeconds)
        let segments = WhoopChartGaps.segments(at: daily, maxGap: dailyGap)
        XCTAssertEqual(segments.dropLast(), Array(repeating: 0, count: 7))
        XCTAssertEqual(segments.last, 1)
    }

    func testTimeoutWithBankedRowsSchedulesRescore() {
        XCTAssertTrue(WhoopBankedPass.schedulesRescore(persistedRows: true))
        XCTAssertFalse(WhoopBankedPass.schedulesRescore(persistedRows: false))
    }

    func testBackgroundOffloadStaysBoundedAndDoesNotRearmLiveWork() {
        XCTAssertEqual(WhoopEnergyBudget.backgroundSyncMaxDuration, 30)
        XCTAssertEqual(WhoopSyncDecision.backgroundInterval, 15 * 60)
        let now: TimeInterval = 1_700_000_000
        let cooled = now - WhoopSyncDecision.backgroundInterval
        XCTAssertTrue(WhoopSyncDecision.allows(.strapEvent, inForeground: false, now: now, lastSyncAt: cooled))
        XCTAssertTrue(WhoopSyncDecision.allows(.backgroundWake, inForeground: false, now: now, lastSyncAt: cooled))
        XCTAssertFalse(WhoopEnergyBudget.allows(.autoContinue, scene: .background, trigger: .strapEvent))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldSubscribeLiveHR(liveWorkSuspended: true, characteristic: "2A37"))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldArmKeepalive(liveWorkSuspended: true))
        XCTAssertFalse(WhoopLiveLinkPolicy.shouldRunRealtime(liveWorkSuspended: true))
    }
}
