import XCTest
@testable import WhoopProtocol

final class SleepNightPickTests: XCTestCase {
    private let nights = [
        SleepNightStamp(index: 0, dayKey: "2026-10-04"),
        SleepNightStamp(index: 1, dayKey: "2026-10-02"),
        SleepNightStamp(index: 2, dayKey: "2026-10-02"),
    ]

    func testLatestNightIsOffsetZero() {
        XCTAssertEqual(SleepNightPick.latestOffset, 0)
        XCTAssertEqual(SleepNightPick.index(dayKey: "2026-10-04", nights: nights), 0)
    }

    func testSameDayKeepsTheNewestNight() {
        XCTAssertEqual(SleepNightPick.index(dayKey: "2026-10-02", nights: nights), 1)
    }

    func testMissingDayDoesNotInventANight() {
        XCTAssertNil(SleepNightPick.index(dayKey: "2026-10-03", nights: []))
        XCTAssertNil(SleepNightPick.index(dayKey: "2026-10-01", nights: nights))
    }

    func testFutureAndEmptyDaysStayClosed() {
        let keys: Set<String> = ["2026-10-04", "2026-10-02"]
        XCTAssertFalse(SleepNightPick.isSelectable(dayKey: "2026-10-05", todayKey: "2026-10-04", nightKeys: keys))
        XCTAssertFalse(SleepNightPick.isSelectable(dayKey: "2026-10-03", todayKey: "2026-10-04", nightKeys: keys))
        XCTAssertTrue(SleepNightPick.isSelectable(dayKey: "2026-10-02", todayKey: "2026-10-04", nightKeys: keys))
        XCTAssertTrue(SleepNightPick.isSelectable(dayKey: "2026-10-04", todayKey: "2026-10-04", nightKeys: keys))
    }

    /// 00:30 : le jour logique est encore la veille, la clé de réveil est déjà le jour calendaire.
    func testStoredNightStaysOpenAt0030() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 30))!
        let logical = now.addingTimeInterval(-4 * 3_600)
        let logicalKey = key(logical, calendar: calendar)
        let wake = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 20))!
        let nightKey = key(wake, calendar: calendar)
        XCTAssertEqual(logicalKey, "2026-10-04")
        XCTAssertEqual(nightKey, "2026-10-05")
        XCTAssertTrue(SleepNightPick.isSelectable(dayKey: nightKey, todayKey: logicalKey, nightKeys: [nightKey]))
        XCTAssertFalse(SleepNightPick.isSelectable(dayKey: "2026-10-06", todayKey: logicalKey, nightKeys: [nightKey]))
    }

    private func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
