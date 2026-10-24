import XCTest
@testable import WhoopProtocol

final class WhoopPackLiveTests: XCTestCase {
    private let payload569 = "f5481c000100005e005301574242354150303030303030310000003902010c00"

    func testSynthetic109OnWhoop5PublishesPackWithoutCharging() {
        let frame = eventFrame(payload569)
        let info = BatteryPackInfo.decodeEventFrame(frame)
        XCTAssertEqual(info?.socPct ?? -1, 56.9, accuracy: 1e-9)
        XCTAssertEqual(info?.displayable, true)
        let charging = true
        let next = WhoopPackLive.reduce(
            WhoopPackState(),
            signal: .info(info!, eventTimestamp: 1_000),
            now: 1_000,
            duringOffload: false,
            wallNow: 5_000)
        XCTAssertEqual(next.socPct ?? -1, 56.9, accuracy: 1e-9)
        XCTAssertTrue(next.present)
        XCTAssertEqual(charging, true)
        XCTAssertEqual(WhoopPackDisplay.resolve(present: next.present, socPct: next.socPct), .percent(56.9))
        let hex = BatteryPackInfo.redactedHex(frame)
        XCTAssertFalse(hex.contains("574242354150"))
        let redacted = bytes(hex)
        XCTAssertEqual(redacted[10], UInt8(BatteryPackInfo.packInfoEvent))
        let serial = BatteryPackInfo.whoop5EventPayloadStart + BatteryPackInfo.eventRecordBase + 7
        let soc = serial + 16
        XCTAssertGreaterThanOrEqual(redacted.count, soc + 2)
        XCTAssertEqual(Array(redacted[serial..<soc]), [UInt8](repeating: 0, count: 16))
        XCTAssertEqual(redacted[soc], frame[soc])
        XCTAssertEqual(redacted[soc + 1], frame[soc + 1])
    }

    func testShort109ZerosFromTheBluetoothAddressThroughTheEnd() {
        var frame = [UInt8](repeating: 0xAB, count: 40)
        frame[1] = 40
        frame[10] = UInt8(BatteryPackInfo.packInfoEvent)
        frame[12] = 0x10
        frame[13] = 0x20
        frame[14] = 0x30
        frame[15] = 0x40
        let address = BatteryPackInfo.whoop5EventPayloadStart + BatteryPackInfo.eventRecordBase + 1
        XCTAssertLessThan(frame.count, address + 6 + 16)
        let redacted = bytes(BatteryPackInfo.redactedHex(frame))
        XCTAssertEqual(redacted[1], 40)
        XCTAssertEqual(redacted[10], UInt8(BatteryPackInfo.packInfoEvent))
        XCTAssertEqual(redacted[12], 0x10)
        XCTAssertEqual(redacted[address - 1], 0xAB)
        for index in address..<frame.count {
            XCTAssertEqual(redacted[index], 0, "index \(index)")
        }
    }

    func testEvents21And22KeepLengthEventTimestampAndCrc() {
        var frame = [UInt8](repeating: 0x5A, count: 28)
        frame[1] = 0x1C
        frame[10] = UInt8(BatteryPackInfo.packChargeOnEvent)
        frame[12] = 0x11
        frame[13] = 0x22
        frame[14] = 0x33
        frame[15] = 0x44
        frame[24] = 0xA1
        frame[25] = 0xA2
        frame[26] = 0xA3
        frame[27] = 0xA4
        let on = bytes(BatteryPackInfo.redactedHex(frame))
        XCTAssertEqual(on[1], 0x1C)
        XCTAssertEqual(on[10], 21)
        XCTAssertEqual(Array(on[12..<16]), [0x11, 0x22, 0x33, 0x44])
        XCTAssertEqual(Array(on[16..<24]), [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(Array(on[24..<28]), [0xA1, 0xA2, 0xA3, 0xA4])

        var off = frame
        off[10] = UInt8(BatteryPackInfo.packChargeOffEvent)
        let removed = bytes(BatteryPackInfo.redactedHex(off))
        XCTAssertEqual(removed[10], 22)
        XCTAssertEqual(Array(removed[16..<24]), [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(removed[27], 0xA4)

        var short = [UInt8](repeating: 0x5A, count: 18)
        short[1] = 18
        short[10] = 22
        let clipped = bytes(BatteryPackInfo.redactedHex(short))
        XCTAssertEqual(clipped[1], 18)
        XCTAssertEqual(clipped[10], 22)
        XCTAssertEqual(clipped[15], 0x5A)
        XCTAssertEqual(clipped[16], 0)
        XCTAssertEqual(clipped[17], 0)
    }

    func testReplayOlderThan45SecondsIsIgnored() {
        let info = BatteryPackInfo.Info(present: true, socPct: 56.9, serial: nil, btAddr: nil)
        let next = WhoopPackLive.reduce(
            WhoopPackState(),
            signal: .info(info, eventTimestamp: 100),
            now: 200,
            duringOffload: true,
            wallNow: 9_000)
        XCTAssertNil(next.socPct)
        XCTAssertFalse(next.present)
    }

    func testFreshOffload109Applies() {
        let info = BatteryPackInfo.Info(present: true, socPct: 56.9, serial: nil, btAddr: nil)
        let next = WhoopPackLive.reduce(
            WhoopPackState(),
            signal: .info(info, eventTimestamp: 100),
            now: 120,
            duringOffload: true,
            wallNow: 9_000)
        XCTAssertEqual(next.socPct ?? -1, 56.9, accuracy: 1e-9)
    }

    func testRemovedClearsThePack() {
        var state = WhoopPackState(socPct: 56.9, present: true, lastInfoWall: 10, lastEventTimestamp: 50)
        state = WhoopPackLive.reduce(
            state,
            signal: .removed(eventTimestamp: 80),
            now: 80,
            duringOffload: false,
            wallNow: 90)
        XCTAssertNil(state.socPct)
        XCTAssertFalse(state.present)
        XCTAssertEqual(WhoopPackDisplay.resolve(present: state.present, socPct: state.socPct), .hidden)
    }

    func testTenMinutesWithoutEvent109ClearsPackPresent() {
        let state = WhoopPackState(socPct: 56.9, present: true, lastInfoWall: 1_000, lastEventTimestamp: 1)
        let expired = WhoopPackLive.expire(state, wallNow: 1_000 + WhoopPackLive.staleAfter)
        XCTAssertNil(expired.socPct)
        XCTAssertFalse(expired.present)
        XCTAssertNil(expired.lastInfoWall)
        XCTAssertEqual(WhoopPackDisplay.resolve(present: expired.present, socPct: expired.socPct), .hidden)
    }

    func testPresenceWithoutA109IsNotClearedByTheTimeout() {
        let state = WhoopPackState(socPct: nil, present: true, lastInfoWall: nil, lastEventTimestamp: 4)
        let expired = WhoopPackLive.expire(state, wallNow: 10_000)
        XCTAssertTrue(expired.present)
        XCTAssertEqual(WhoopPackDisplay.resolve(present: expired.present, socPct: expired.socPct), .connected)
    }

    func testAttachedWithoutAGaugeSaysConnected() {
        let next = WhoopPackLive.reduce(
            WhoopPackState(),
            signal: .attached(eventTimestamp: 10),
            now: 10,
            duringOffload: false,
            wallNow: 10)
        XCTAssertTrue(next.present)
        XCTAssertNil(next.socPct)
        XCTAssertEqual(WhoopPackDisplay.resolve(present: next.present, socPct: next.socPct), .connected)
    }

    func testPresentFalseClears() {
        let info = BatteryPackInfo.Info(present: false, socPct: nil, serial: nil, btAddr: nil)
        let start = WhoopPackState(socPct: 40, present: true, lastInfoWall: 5, lastEventTimestamp: 1)
        let next = WhoopPackLive.reduce(
            start,
            signal: .info(info, eventTimestamp: 20),
            now: 20,
            duringOffload: false,
            wallNow: 30)
        XCTAssertNil(next.socPct)
        XCTAssertFalse(next.present)
    }

    private func eventFrame(_ payloadHex: String) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: 16)
        frame.append(contentsOf: bytes(payloadHex))
        frame[10] = UInt8(BatteryPackInfo.packInfoEvent)
        return frame
    }

    private func bytes(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map { offset in
            let start = s.index(s.startIndex, offsetBy: offset)
            return UInt8(s[start...s.index(start, offsetBy: 1)], radix: 16)!
        }
    }
}
