import XCTest
@testable import WhoopProtocol

final class LiveChargeDispatchTests: XCTestCase {
    func testEdges() {
        let on7 = LiveChargeDispatch.effect(kind: .on, eventTimestamp: 100, now: 100, duringOffload: false, lastAppliedTimestamp: 0)
        let on21 = LiveChargeDispatch.effect(kind: .on, eventTimestamp: 100, now: 100, duringOffload: false, lastAppliedTimestamp: 0)
        let off8 = LiveChargeDispatch.effect(kind: .off, eventTimestamp: 100, now: 100, duringOffload: false, lastAppliedTimestamp: 0)
        let off22 = LiveChargeDispatch.effect(kind: .off, eventTimestamp: 100, now: 100, duringOffload: false, lastAppliedTimestamp: 0)
        XCTAssertEqual(on7.charging, true)
        XCTAssertEqual(on21.charging, true)
        XCTAssertEqual(off8.charging, false)
        XCTAssertEqual(off22.charging, false)
    }

    func testSyntheticWhoop5BatteryByteAt30IsCharging() {
        let hex = "aa01240001002eb130350300a589266a5118140002f3010000f90e00000000340806003500000000358eb56f"
        var frame = bytes(hex)
        frame[30] = 1
        let end = frame.count - 4
        let crc = crc32(frame, 8, end)
        frame[end] = UInt8(truncatingIfNeeded: crc)
        frame[end + 1] = UInt8(truncatingIfNeeded: crc >> 8)
        frame[end + 2] = UInt8(truncatingIfNeeded: crc >> 16)
        frame[end + 3] = UInt8(truncatingIfNeeded: crc >> 24)
        let parsed = parseFrame(frame, family: .whoop5)
        XCTAssertEqual(parsed.parsed["battery_charging"]?.intValue, 1)
        let note = LiveChargeDispatch.note(frame: frame, whoop5: true)
        XCTAssertEqual(note?.event, 3)
        XCTAssertEqual(note?.chargeRaw, 1)
        let effect = LiveChargeDispatch.effect(
            kind: .battery(rawByte: note?.chargeRaw),
            eventTimestamp: parsed.parsed["event_timestamp"]?.intValue,
            now: 100,
            duringOffload: false,
            lastAppliedTimestamp: 0)
        XCTAssertEqual(effect.charging, true)
        XCTAssertTrue(effect.apply)
    }

    func testRawChargeAboveOneDoesNotInventAFlag() {
        let effect = LiveChargeDispatch.effect(
            kind: .battery(rawByte: 4),
            eventTimestamp: 50,
            now: 50,
            duringOffload: false,
            lastAppliedTimestamp: 0)
        XCTAssertTrue(effect.apply)
        XCTAssertNil(effect.charging)
    }

    func testOffloadReplayOlderThan45SecondsIsIgnored() {
        let effect = LiveChargeDispatch.effect(
            kind: .on,
            eventTimestamp: 100,
            now: 160,
            duringOffload: true,
            lastAppliedTimestamp: 0)
        XCTAssertFalse(effect.apply)
        XCTAssertNil(effect.charging)
    }

    func testOffloadInsideTheWindowApplies() {
        let effect = LiveChargeDispatch.effect(
            kind: .on,
            eventTimestamp: 100,
            now: 120,
            duringOffload: true,
            lastAppliedTimestamp: 90)
        XCTAssertTrue(effect.apply)
        XCTAssertEqual(effect.charging, true)
        XCTAssertEqual(effect.cursor, 100)
    }

    func testLiveAppliesEvenWhenTheStrapClockIsOlder() {
        let effect = LiveChargeDispatch.effect(
            kind: .off,
            eventTimestamp: 40,
            now: 500,
            duringOffload: false,
            lastAppliedTimestamp: 400)
        XCTAssertTrue(effect.apply)
        XCTAssertEqual(effect.charging, false)
        XCTAssertEqual(effect.cursor, 400)
    }

    private func bytes(_ s: String) -> [UInt8] {
        var out = [UInt8]()
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            out.append(UInt8(s[index..<next], radix: 16)!)
            index = next
        }
        return out
    }
}
