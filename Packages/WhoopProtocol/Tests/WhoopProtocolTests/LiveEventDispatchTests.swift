import XCTest
@testable import WhoopProtocol

final class LiveEventDispatchTests: XCTestCase {
    func testRouteMatchesTheLiveAndOffloadActions() {
        XCTAssertEqual(LiveEventDispatch.route("DOUBLE_TAP(2)"), .doubleTap)
        XCTAssertEqual(LiveEventDispatch.route("WRIST_ON(1)"), .wristOn)
        XCTAssertEqual(LiveEventDispatch.route("WRIST_OFF(0)"), .wristOff)
        XCTAssertEqual(LiveEventDispatch.route("CHARGING_ON(7)"), .chargingOn)
        XCTAssertEqual(LiveEventDispatch.route("BATTERY_PACK_CONNECTED(21)"), .chargingOn)
        XCTAssertEqual(LiveEventDispatch.route("CHARGING_OFF(8)"), .chargingOff)
        XCTAssertEqual(LiveEventDispatch.route("BATTERY_PACK_REMOVED(22)"), .chargingOff)
        XCTAssertEqual(LiveEventDispatch.route("BATTERY_LEVEL(3)"), .batteryLevel)
        XCTAssertEqual(LiveEventDispatch.route("0x6D(109)"), .packInfo)
        XCTAssertEqual(LiveEventDispatch.route("STRAP_DRIVEN_ALARM_EXECUTED(57)"), .other)
    }

    func testChargeLogWritesOnFirstValueChangeAndThenEveryTenSeconds() {
        XCTAssertTrue(ChargeLogGate.shouldWrite(value: nil, now: 100, slot: nil))
        let first = ChargeLogSlot(lastAt: 100, lastValue: 0)
        XCTAssertFalse(ChargeLogGate.shouldWrite(value: 0, now: 109.9, slot: first))
        XCTAssertTrue(ChargeLogGate.shouldWrite(value: 0, now: 110, slot: first))
        XCTAssertTrue(ChargeLogGate.shouldWrite(value: 1, now: 101, slot: first))
        XCTAssertTrue(ChargeLogGate.shouldWrite(value: nil, now: 101, slot: first))
    }
}

final class LiveBeatCurveTests: XCTestCase {
    func testRingKeepsNinetySamplesAndCubicsStayPutWhileTimeShifts() {
        let times = (0..<91).map { TimeInterval($0) }
        let bpms = (0..<91).map { _ in 70.0 }
        let curve = LiveBeatCurve.make(times: times, bpms: bpms, anchor: 90)
        XCTAssertEqual(curve.times.count, LiveBeatScroll.capacity)
        XCTAssertEqual(curve.bpms.count, LiveBeatScroll.capacity)
        XCTAssertEqual(curve.count, 90)
        XCTAssertEqual(curve.times[0], 1, accuracy: 0.000_1)
        XCTAssertEqual(curve.body.count, 88)
        let atAnchor = LiveBeatScroll.headPoint(curve: curve, now: 90, blend: 1)
        let later = LiveBeatScroll.headPoint(curve: curve, now: 91, blend: 1)
        XCTAssertEqual(LiveBeatScroll.timeShift(anchor: 90, now: 91), -1.0 / 90.0, accuracy: 0.000_1)
        XCTAssertEqual((atAnchor?.x ?? 0) - (later?.x ?? 0), 1.0 / 90.0, accuracy: 0.000_1)
        XCTAssertEqual(curve.body[0].x0, LiveBeatCurve.make(times: times, bpms: bpms, anchor: 90).body[0].x0, accuracy: 0.000_1)
    }

    func testRingBufferFeedSharesTheLiveNumberAndDropsWhenUnlinked() {
        var samples: [LiveBeatSample] = []
        samples = LiveBeatScroll.feed(samples, bpm: 60, at: 10, linked: true)
        samples = LiveBeatScroll.feed(samples, bpm: 62, at: 11, linked: true)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.last?.bpm, 62)
        let unlinked = LiveBeatScroll.feed(samples, bpm: 70, at: 12, linked: false)
        XCTAssertTrue(unlinked.isEmpty)
        let invalid = LiveBeatScroll.feed(samples, bpm: 0, at: 12, linked: true)
        XCTAssertTrue(invalid.isEmpty)
        var full: [LiveBeatSample] = []
        var index = 0
        while index < LiveBeatScroll.capacity + 5 {
            full = LiveBeatScroll.feed(full, bpm: Double(50 + index), at: TimeInterval(index), linked: true)
            index += 1
        }
        XCTAssertEqual(full.count, LiveBeatScroll.capacity)
        XCTAssertEqual(full.first?.t, 5)
        XCTAssertEqual(full.last?.bpm, Double(50 + LiveBeatScroll.capacity + 4))
        var merged: [LiveBeatSample] = []
        merged = LiveBeatScroll.feed(merged, bpm: 60, at: 10, linked: true)
        merged = LiveBeatScroll.feed(merged, bpm: 64, at: 10.2, linked: true)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.last?.bpm, 64)
        merged = LiveBeatScroll.feed(merged, bpm: 70, at: 10.7, linked: true)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.last?.bpm, 70)
    }

    func testAxisSmoothstepBlendsPreviousBoundsAndTheFirstCurveSnaps() {
        let first = LiveBeatCurve.make(times: [0, 1], bpms: [60, 60], anchor: 1)
        XCTAssertEqual(first.low, 55, accuracy: 0.000_1)
        XCTAssertEqual(first.high, 65, accuracy: 0.000_1)
        XCTAssertEqual(first.previousLow, first.low, accuracy: 0.000_1)
        XCTAssertEqual(first.previousHigh, first.high, accuracy: 0.000_1)
        let snapped = LiveBeatScroll.easedAxis(curve: first, now: first.boundsAt)
        XCTAssertEqual(snapped.low, first.low, accuracy: 0.000_1)
        XCTAssertEqual(snapped.high, first.high, accuracy: 0.000_1)

        let next = LiveBeatCurve.make(
            times: [0, 1, 2],
            bpms: [60, 60, 80],
            anchor: 2,
            previousLow: first.low,
            previousHigh: first.high,
            boundsAt: 2)
        XCTAssertEqual(next.low, 60, accuracy: 0.000_1)
        XCTAssertEqual(next.high, 80, accuracy: 0.000_1)
        let atStart = LiveBeatScroll.easedAxis(curve: next, now: 2)
        XCTAssertEqual(atStart.low, first.low, accuracy: 0.000_1)
        XCTAssertEqual(atStart.high, first.high, accuracy: 0.000_1)
        let half = LiveBeatScroll.smoothstep(0.5)
        XCTAssertEqual(half, 0.5, accuracy: 0.000_1)
        let mid = LiveBeatScroll.easedAxis(curve: next, now: 2 + LiveBeatScroll.boundsEase / 2)
        XCTAssertEqual(mid.low, first.low + (next.low - first.low) * half, accuracy: 0.000_1)
        XCTAssertEqual(mid.high, first.high + (next.high - first.high) * half, accuracy: 0.000_1)
        let done = LiveBeatScroll.easedAxis(curve: next, now: 2 + LiveBeatScroll.boundsEase)
        XCTAssertEqual(done.low, next.low, accuracy: 0.000_1)
        XCTAssertEqual(done.high, next.high, accuracy: 0.000_1)

        let empty = LiveBeatCurve.make(times: [], bpms: [], anchor: 5)
        XCTAssertEqual(empty.count, 0)
        XCTAssertEqual(empty.previousLow, empty.low, accuracy: 0.000_1)
        XCTAssertEqual(empty.previousHigh, empty.high, accuracy: 0.000_1)
    }

    func testReduceMotionInfinitySnapsToTargetAndKeepsTheHeadInside() {
        let first = LiveBeatCurve.make(times: [0, 1], bpms: [60, 62], anchor: 1)
        XCTAssertEqual(first.low, 56, accuracy: 0.000_1)
        XCTAssertEqual(first.high, 66, accuracy: 0.000_1)
        let next = LiveBeatCurve.make(
            times: [0, 1, 2],
            bpms: [60, 62, 95],
            anchor: 2,
            previousLow: first.low,
            previousHigh: first.high,
            boundsAt: 2)
        XCTAssertEqual(next.low, 60, accuracy: 0.000_1)
        XCTAssertEqual(next.high, 95, accuracy: 0.000_1)
        let lagged = LiveBeatScroll.easedAxis(curve: next, now: next.boundsAt)
        XCTAssertEqual(lagged.low, 56, accuracy: 0.000_1)
        XCTAssertEqual(lagged.high, 66, accuracy: 0.000_1)
        let snapped = LiveBeatScroll.easedAxis(curve: next, now: .infinity)
        XCTAssertEqual(snapped.low, 60, accuracy: 0.000_1)
        XCTAssertEqual(snapped.high, 95, accuracy: 0.000_1)
        XCTAssertTrue(snapped.low.isFinite)
        XCTAssertTrue(snapped.high.isFinite)
        let nanAxis = LiveBeatScroll.easedAxis(curve: next, now: .nan)
        XCTAssertTrue(nanAxis.low.isFinite)
        XCTAssertTrue(nanAxis.high.isFinite)
        let head = LiveBeatScroll.headPoint(curve: next, now: 2, blend: 1)
        XCTAssertNotNil(head)
        let y = head?.y ?? .nan
        XCTAssertGreaterThanOrEqual(y, snapped.low)
        XCTAssertLessThanOrEqual(y, snapped.high)
        XCTAssertGreaterThan(y, lagged.high)
        let card = plottedY(bpm: y, low: snapped.low, high: snapped.high, height: 92)
        XCTAssertGreaterThanOrEqual(card, 0)
        XCTAssertLessThanOrEqual(card, 92)
        let overflow = plottedY(bpm: y, low: lagged.low, high: lagged.high, height: 92)
        XCTAssertLessThan(overflow, 0)
    }

    private func plottedY(bpm: Double, low: Double, high: Double, height: Double) -> Double {
        let pad = 10.0
        let span = max(10, high - low)
        return height - pad - (bpm - low) / span * (height - 2 * pad)
    }
}
