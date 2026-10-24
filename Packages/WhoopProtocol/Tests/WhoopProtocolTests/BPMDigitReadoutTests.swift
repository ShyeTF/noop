import XCTest
@testable import WhoopProtocol

final class BPMDigitReadoutTests: XCTestCase {
    func testNilAndNonFiniteStayOnThePlaceholder() {
        XCTAssertEqual(BPMDigitReadout.shown(Optional<Int>.none), "—")
        XCTAssertEqual(BPMDigitReadout.shown(Optional<Double>.none), "—")
        XCTAssertEqual(BPMDigitReadout.shown(Double.nan), "—")
        XCTAssertEqual(BPMDigitReadout.shown(Double.infinity), "—")
        XCTAssertEqual(BPMDigitReadout.line(nil, suffix: " bpm"), "—")
    }

    func testRoundsAndKeepsTheSuffixOnlyWhenANumberExists() {
        XCTAssertEqual(BPMDigitReadout.shown(72), "72")
        XCTAssertEqual(BPMDigitReadout.shown(72.4), "72")
        XCTAssertEqual(BPMDigitReadout.shown(72.5), "73")
        XCTAssertEqual(BPMDigitReadout.line(64, suffix: " bpm"), "64 bpm")
    }

    func testNilTransitionsDoNotAnimate() {
        XCTAssertFalse(BPMDigitReadout.animates(from: nil, to: 80))
        XCTAssertFalse(BPMDigitReadout.animates(from: 80, to: nil))
        XCTAssertFalse(BPMDigitReadout.animates(from: nil, to: nil))
        XCTAssertFalse(BPMDigitReadout.animates(from: 80, to: 80))
        XCTAssertTrue(BPMDigitReadout.animates(from: 80, to: 81))
        XCTAssertEqual(BPMDigitReadout.easeOutSeconds, 0.25)
    }
}
