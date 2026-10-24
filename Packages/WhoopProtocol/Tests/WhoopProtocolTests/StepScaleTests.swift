import XCTest
@testable import WhoopProtocol

final class StepScaleTests: XCTestCase {
    func testDailyReferenceIsTenThousand() {
        XCTAssertEqual(StepScale.dailyReference, 10_000)
    }

    func testRatioUsesTheReferenceWithoutChangingTheCount() {
        XCTAssertEqual(StepScale.ratio(steps: 0), 0)
        XCTAssertEqual(StepScale.ratio(steps: 10_000), 1)
        XCTAssertEqual(StepScale.ratio(steps: 15_000), 1.5)
    }
}
