import XCTest
@testable import WhoopProtocol

final class LiveBeatScrollTests: XCTestCase {
    func testUnitXPlacesNowAtTheRightEdge() {
        let now: TimeInterval = 10_000
        XCTAssertEqual(LiveBeatScroll.unitX(sampleTime: now, now: now), 1, accuracy: 0.000_1)
        XCTAssertEqual(LiveBeatScroll.unitX(sampleTime: now - 90, now: now), 0, accuracy: 0.000_1)
        XCTAssertLessThan(LiveBeatScroll.unitX(sampleTime: now - 120, now: now), 0)
    }

    func testHeadEasesAcrossTheInterSampleGap() {
        let halfway = LiveBeatScroll.headBPM(previous: 60, latest: 80, elapsed: 0.5, gap: 1)
        XCTAssertEqual(halfway, 70, accuracy: 0.000_1)
        XCTAssertEqual(LiveBeatScroll.headBPM(previous: 60, latest: 80, elapsed: 0, gap: 1), 60, accuracy: 0.000_1)
        XCTAssertEqual(LiveBeatScroll.headBPM(previous: 60, latest: 80, elapsed: 2, gap: 1), 80, accuracy: 0.000_1)
    }

    func testLayoutSlidesOlderSamplesLeftWithoutSorting() {
        let samples = [
            LiveBeatSample(t: 1_000, bpm: 70),
            LiveBeatSample(t: 1_001, bpm: 80),
        ]
        let points = LiveBeatScroll.layout(samples: samples, now: 1_001.5)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].y, 70, accuracy: 0.000_1)
        XCTAssertLessThan(points[0].x, points[1].x)
        XCTAssertEqual(points[1].y, 75, accuracy: 0.000_1)
        XCTAssertFalse(points.contains { abs($0.y - 80) < 0.01 })
    }

    func testConstantHeartRateHasNoHook() {
        let samples = [
            LiveBeatSample(t: 1_000, bpm: 60),
            LiveBeatSample(t: 1_001, bpm: 60),
        ]
        let points = LiveBeatScroll.layout(samples: samples, now: 1_001.5)
        XCTAssertEqual(points.count, 2)
        XCTAssertTrue(points.allSatisfy { abs($0.y - 60) < 0.000_1 })
    }

    func testPointsReuseStoredColumns() {
        let drawn = LiveBeatScroll.points(times: [1_000, 1_001], bpms: [70, 80], now: 1_001.5, blend: 0)
        XCTAssertEqual(drawn.count, 2)
        XCTAssertEqual(drawn[0].y, 70, accuracy: 0.000_1)
        XCTAssertEqual(drawn[1].y, 70, accuracy: 0.000_1)
        XCTAssertEqual(drawn[0].x, drawn[1].x, accuracy: 0.000_1)
    }

    func testTrimKeepsTheNewestNinety() {
        let samples = (0..<100).map { LiveBeatSample(t: TimeInterval($0), bpm: Double($0)) }
        let kept = LiveBeatScroll.trim(samples)
        XCTAssertEqual(kept.count, 90)
        XCTAssertEqual(kept.first?.t, 10)
        XCTAssertEqual(kept.last?.t, 99)
    }

    func testMonotoneCubicStaysOnALine() {
        let points = [
            LiveBeatPoint(x: 0, y: 0),
            LiveBeatPoint(x: 1, y: 2),
            LiveBeatPoint(x: 2, y: 4),
        ]
        let cubics = LiveBeatScroll.monotoneCubics(points)
        XCTAssertEqual(cubics.count, 2)
        for cubic in cubics {
            let low = min(cubic.y0, cubic.y1)
            let high = max(cubic.y0, cubic.y1)
            XCTAssertGreaterThanOrEqual(cubic.c1y, low - 0.000_1)
            XCTAssertLessThanOrEqual(cubic.c1y, high + 0.000_1)
            XCTAssertGreaterThanOrEqual(cubic.c2y, low - 0.000_1)
            XCTAssertLessThanOrEqual(cubic.c2y, high + 0.000_1)
        }
    }

    func testBoundsEaseTowardTheTarget() {
        let stepped = LiveBeatScroll.easedBound(current: 40, target: 80, dt: 0)
        XCTAssertEqual(stepped, 80, accuracy: 0.000_1)
        let partial = LiveBeatScroll.easedBound(current: 40, target: 80, dt: 0.45)
        XCTAssertGreaterThan(partial, 40)
        XCTAssertLessThan(partial, 80)
    }
}
