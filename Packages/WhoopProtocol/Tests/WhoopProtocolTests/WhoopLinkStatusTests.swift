import XCTest
@testable import WhoopProtocol

final class WhoopLinkStatusTests: XCTestCase {
    private let now: Double = 1_700_000_000_000

    func testConnectionBecomesLiveWhenPacketsAreFreshInForeground() {
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(connecting: true)), .connecting)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, liveAgeMs: 1_000)),
            .live)
    }

    func testLiveBecomesSyncThenLiveAgain() {
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, syncing: true, liveAgeMs: 1_000)),
            .syncing)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, syncing: false, liveAgeMs: 1_000)),
            .live)
    }

    func testStalePacketsAndDisconnectAreOffline() {
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, liveAgeMs: 15_001)),
            .offline)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, liveAgeMs: 15_000)),
            .live)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(connected: false)), .offline)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, liveAgeMs: nil)),
            .offline)
    }

    func testBluetoothOffAndUnauthorizedBeatEveryOtherSignal() {
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(
                radio: .poweredOff, connected: true, syncing: true, liveAgeMs: 0)),
            .bluetoothOff)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(radio: .unauthorized, paired: false)),
            .bluetoothUnauthorized)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(radio: .unsupported)),
            .bluetoothOff)
    }

    func testNoWatchWhenNothingIsPaired() {
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(paired: false, connected: false)),
            .noWatch)
    }

    func testBackgroundDropsLiveAndReturnRestoresIt() {
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, foreground: false, liveAgeMs: 500)),
            .offline)
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(connected: true, foreground: true, liveAgeMs: 500)),
            .live)
    }

    func testHeartStampBeatsAStaleCustomFrameAndEveryTransitionIsCovered() {
        let frame = now - 60_000
        let heart = now - 1_000
        let packet = WhoopLinkClock.latestMs(frameUnix: Int(frame / 1000), heartUnix: Int(heart / 1000))
        XCTAssertEqual(packet ?? .nan, heart, accuracy: 0.5)
        XCTAssertNil(WhoopLinkClock.latestMs(frameUnix: nil, heartUnix: nil))
        XCTAssertNil(WhoopLinkClock.latestMs(frameUnix: 0, heartUnix: 0))
        XCTAssertEqual(
            WhoopLinkClock.latestMs(frameUnix: nil, heartUnix: Int(heart / 1000)) ?? .nan,
            heart,
            accuracy: 0.5)

        let streaming = facts(connected: true, liveAgeMs: nil)
        var withHeart = streaming
        withHeart.livePacketAtMs = packet
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(withHeart), .live)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(streaming), .offline)

        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(radio: .unknown, paired: false)), .noWatch)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(radio: .resetting, connected: true, liveAgeMs: 100)), .live)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(radio: .poweredOn, paired: true, connected: false, connecting: true)), .connecting)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(connected: true, connecting: true, liveAgeMs: 100)), .connecting)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(connected: true, syncing: true, foreground: false, liveAgeMs: 100)), .syncing)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(connected: true, foreground: false, liveAgeMs: 100)), .offline)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(paired: false, connected: true, liveAgeMs: 100)), .live)
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(facts(paired: false, connecting: true)), .connecting)
    }

    func testOffWristLinkStampBeatsAnOlderReadableHeart() {
        let heart = now - 20_000
        let link = now - 1_000
        let packet = WhoopLinkClock.latestMs(
            frameUnix: nil,
            heartUnix: Int(heart / 1000),
            linkUnix: Int(link / 1000))
        XCTAssertEqual(packet ?? .nan, link, accuracy: 0.5)
        var streaming = facts(connected: true, liveAgeMs: nil)
        streaming.livePacketAtMs = packet
        XCTAssertEqual(WhoopLinkStatusEngine.resolve(streaming), .live)
    }

    func testForegroundBackfillStaysOnSyncWhileLivePacketsContinue() {
        XCTAssertEqual(
            WhoopLinkStatusEngine.resolve(facts(
                connected: true, syncing: true, foreground: true, liveAgeMs: 200)),
            .syncing)
    }

    private func facts(
        radio: WhoopRadioState = .poweredOn,
        paired: Bool = true,
        connected: Bool = false,
        connecting: Bool = false,
        syncing: Bool = false,
        foreground: Bool = true,
        liveAgeMs: Double? = nil
    ) -> WhoopLinkFacts {
        WhoopLinkFacts(
            radio: radio,
            paired: paired,
            connected: connected,
            connecting: connecting,
            syncing: syncing,
            foreground: foreground,
            livePacketAtMs: liveAgeMs.map { now - $0 },
            nowMs: now)
    }
}
