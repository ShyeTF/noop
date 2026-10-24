import XCTest
@testable import WhoopProtocol

final class MuscyHeartBandsTests: XCTestCase {
    private let sessionStart: TimeInterval = 1_000
    private let sessionEnd: TimeInterval = 2_000

    func testWorkSpanUsesOnlySamplesInsideTheInterval() {
        let previous = makeSet(
            id: "p", order: 0, number: 1, completed: 1_050, restStart: 1_050, restEnd: 1_100)
        let set = makeSet(id: "a", order: 0, number: 2, completed: 1_200, reps: 8, load: 60)
        let samples = [
            MuscyHeartSample(at: 1_099, bpm: 200),
            MuscyHeartSample(at: 1_100, bpm: 100),
            MuscyHeartSample(at: 1_150, bpm: 140),
            MuscyHeartSample(at: 1_200, bpm: 120),
            MuscyHeartSample(at: 1_201, bpm: 180),
            MuscyHeartSample(at: 1_160, bpm: .nan),
            MuscyHeartSample(at: 1_170, bpm: 0),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: [previous, set], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertFalse(overlay.degraded)
        let work = overlay.spans.first { $0.id == "work-a" }
        XCTAssertEqual(work?.kind, .work)
        XCTAssertEqual(work?.start, 1_100)
        XCTAssertEqual(work?.end, 1_200)
        XCTAssertEqual(work?.reps, 8)
        XCTAssertEqual(work?.load, 60)
        XCTAssertEqual(overlay.exercises[0].sets[1].average, 120)
        XCTAssertEqual(overlay.exercises[0].sets[1].maximum, 140)
        XCTAssertEqual(overlay.exercises[0].sets[1].timed, true)
        XCTAssertEqual(overlay.exercises[0].average, 120)
        XCTAssertEqual(overlay.exercises[0].maximum, 140)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.markers.map(\.id), ["mark-p"])
    }

    func testEmptyIntervalShowsNoAverage() {
        let previous = makeSet(id: "p", order: 0, number: 1, completed: 1_050, restStart: 1_050, restEnd: 1_100)
        let set = makeSet(id: "a", order: 0, number: 2, completed: 1_200)
        let samples = [MuscyHeartSample(at: 1_300, bpm: 90)]
        let overlay = MuscyHeartBands.overlay(
            sets: [previous, set], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlay.exercises[0].sets[1].timed, true)
        XCTAssertNil(overlay.exercises[0].sets[1].average)
        XCTAssertNil(overlay.exercises[0].sets[1].maximum)
        XCTAssertNil(overlay.exercises[0].average)
    }

    func testOldSessionDoesNotInventIntervals() {
        let first = makeSet(id: "a", order: 0, number: 1, completed: 1_900)
        let second = makeSet(
            id: "b", order: 1, number: 1, name: "Squat", completed: 1_900, reps: 5, load: 100)
        let samples = [
            MuscyHeartSample(at: 1_100, bpm: 80),
            MuscyHeartSample(at: 1_500, bpm: 120),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: [first, second], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(overlay.degraded)
        XCTAssertTrue(overlay.spans.isEmpty)
        XCTAssertTrue(overlay.markers.isEmpty)
        XCTAssertEqual(overlay.exercises.map(\.name), ["Développé couché", "Squat"])
        XCTAssertNil(overlay.exercises[0].average)
        XCTAssertNil(overlay.exercises[1].average)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.sessionAverage, 100)
        XCTAssertEqual(overlay.sessionMaximum, 120)
    }

    func testExerciseOrderAndSessionLengthDoNotPlaceBands() {
        let sets = [
            makeSet(id: "a", order: 0, number: 1),
            makeSet(id: "b", order: 0, number: 2),
            makeSet(id: "c", order: 1, number: 1, name: "Row"),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: sets, samples: [MuscyHeartSample(at: 1_400, bpm: 110)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(overlay.degraded)
        XCTAssertTrue(overlay.spans.isEmpty)
        XCTAssertTrue(overlay.markers.isEmpty)
        XCTAssertEqual(overlay.sessionAverage, 110)
    }

    func testEqualOrReversedTimesAreNotIntervals() {
        let sharedA = makeSet(id: "a", order: 0, number: 1, completed: 1_200)
        let sharedB = makeSet(id: "b", order: 0, number: 2, completed: 1_200)
        let shared = MuscyHeartBands.overlay(
            sets: [sharedA, sharedB], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(shared.spans.isEmpty)
        XCTAssertTrue(shared.markers.isEmpty)
        XCTAssertTrue(shared.degraded)

        let previous = makeSet(id: "p", order: 0, number: 1, completed: 1_100, restStart: 1_100, restEnd: 1_400)
        let current = makeSet(id: "c", order: 0, number: 2, completed: 1_300)
        let overlay = MuscyHeartBands.overlay(
            sets: [previous, current], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertFalse(overlay.spans.contains { $0.kind == .work })
        XCTAssertEqual(overlay.spans.map(\.id), ["rest-p"])
        XCTAssertEqual(overlay.spans[0].end, 1_300)
        XCTAssertEqual(overlay.markers.map(\.id), ["mark-p", "mark-c"])
    }

    func testSpanOutsideTheSessionIsDroppedAndAPartialSpanIsClipped() {
        let outside = makeSet(id: "out", order: 0, number: 1, completed: 150)
        let previous = makeSet(id: "prev", order: 0, number: 2, completed: 800, restStart: 800, restEnd: 900)
        let partial = makeSet(id: "in", order: 0, number: 3, completed: 1_100)
        let samples = [
            MuscyHeartSample(at: 950, bpm: 200),
            MuscyHeartSample(at: 1_000, bpm: 100),
            MuscyHeartSample(at: 1_100, bpm: 130),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: [outside, previous, partial], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlay.spans.map(\.id), ["work-in"])
        XCTAssertEqual(overlay.spans[0].start, 1_000)
        XCTAssertEqual(overlay.spans[0].end, 1_100)
        XCTAssertEqual(overlay.exercises[0].sets[2].average, 115)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.exercises[0].sets[1].timed, false)
    }

    func testUniqueCheckIsAMarkerAndASharedStampIsNot() {
        let checked = makeSet(id: "a", order: 0, number: 1, completed: 1_300, restStart: 1_302, restEnd: 1_390)
        let stale = makeSet(id: "b", order: 0, number: 2, completed: 1_900)
        let alsoStale = makeSet(id: "c", order: 0, number: 3, completed: 1_900)
        let overlay = MuscyHeartBands.overlay(
            sets: [checked, stale, alsoStale], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlay.markers.map(\.id), ["mark-a"])
        XCTAssertEqual(overlay.markers[0].at, 1_300)
        XCTAssertEqual(overlay.spans.map(\.id), ["rest-a"])
        XCTAssertEqual(overlay.spans[0].kind, .rest)
        XCTAssertFalse(overlay.degraded)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
        XCTAssertEqual(overlay.exercises[0].sets[1].timed, false)
        XCTAssertEqual(overlay.exercises[0].sets[2].timed, false)
    }

    func testRestIsNotCountedAsTheSet() {
        let previous = makeSet(id: "p", order: 0, number: 1, completed: 1_040, restStart: 1_040, restEnd: 1_100)
        let set = makeSet(id: "a", order: 0, number: 2, completed: 1_160, restStart: 1_160, restEnd: 1_220)
        let samples = [
            MuscyHeartSample(at: 1_120, bpm: 150),
            MuscyHeartSample(at: 1_180, bpm: 90),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: [previous, set], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlay.spans.map(\.kind), [.rest, .work, .rest])
        XCTAssertEqual(overlay.exercises[0].sets[1].average, 150)
        XCTAssertEqual(overlay.exercises[0].sets[1].maximum, 150)
        XCTAssertEqual(overlay.exercises[0].average, 150)
    }

    func testConsecutiveWorkBandsPoolEachSampleOnce() {
        let first = makeSet(id: "a", order: 0, number: 1, completed: 1_040, restStart: 1_040, restEnd: 1_100)
        let second = makeSet(id: "b", order: 0, number: 2, completed: 1_150, restStart: 1_150, restEnd: 1_160)
        let third = makeSet(id: "c", order: 0, number: 3, completed: 1_200)
        let samples = [
            MuscyHeartSample(at: 1_100, bpm: 100),
            MuscyHeartSample(at: 1_150, bpm: 130),
            MuscyHeartSample(at: 1_160, bpm: 140),
            MuscyHeartSample(at: 1_180, bpm: 160),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: [first, second, third], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlay.exercises[0].sets[1].average, 115)
        XCTAssertEqual(overlay.exercises[0].sets[2].average, 150)
        XCTAssertEqual(overlay.exercises[0].average, 132.5)
        XCTAssertEqual(overlay.exercises[0].maximum, 160)
    }

    func testPrefilledSetWithoutARestStaysDegraded() {
        let set = makeSet(id: "a", order: 0, number: 1, completed: 1_300, reps: 10, load: 80)
        let overlay = MuscyHeartBands.overlay(
            sets: [set], samples: [MuscyHeartSample(at: 1_250, bpm: 140)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(overlay.degraded)
        XCTAssertTrue(overlay.spans.isEmpty)
        XCTAssertTrue(overlay.markers.isEmpty)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.sessionAverage, 140)
    }

    func testRepsTypedAfterTheFactDoNotInventABand() {
        let set = makeSet(id: "a", order: 0, number: 1, completed: 1_305, reps: 8, load: 60)
        let overlay = MuscyHeartBands.overlay(
            sets: [set], samples: [MuscyHeartSample(at: 1_302, bpm: 150)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(overlay.degraded)
        XCTAssertTrue(overlay.spans.isEmpty)
        XCTAssertTrue(overlay.markers.isEmpty)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
    }

    func testUncheckRemovesTheMarkAndABareRecheckDoesNotInventOne() {
        let unchecked = makeSet(id: "a", order: 0, number: 1)
        let hidden = MuscyHeartBands.overlay(
            sets: [unchecked], samples: [MuscyHeartSample(at: 1_400, bpm: 100)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(hidden.markers.isEmpty)
        XCTAssertTrue(hidden.spans.isEmpty)
        XCTAssertTrue(hidden.degraded)

        let rechecked = makeSet(id: "a", order: 0, number: 1, completed: 1_500, reps: 8, load: 40)
        let shown = MuscyHeartBands.overlay(
            sets: [rechecked], samples: [MuscyHeartSample(at: 1_200, bpm: 100)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(shown.spans.isEmpty)
        XCTAssertTrue(shown.markers.isEmpty)
        XCTAssertTrue(shown.degraded)
        XCTAssertNil(shown.exercises[0].sets[0].average)
    }

    func testOldSessionWithASingleCheckedSetStaysDegraded() {
        let set = makeSet(id: "a", order: 0, number: 1, completed: 1_400, reps: 8, load: 40)
        let overlay = MuscyHeartBands.overlay(
            sets: [set], samples: [MuscyHeartSample(at: 1_200, bpm: 90)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(overlay.degraded)
        XCTAssertTrue(overlay.spans.isEmpty)
        XCTAssertTrue(overlay.markers.isEmpty)
        XCTAssertEqual(overlay.exercises[0].sets[0].timed, false)
        XCTAssertNil(overlay.exercises[0].sets[0].average)
        XCTAssertEqual(overlay.sessionAverage, 90)
    }

    func testOldSessionMillisecondsApartStaysDegraded() {
        let first = makeSet(id: "a", order: 0, number: 1, completed: 1_900)
        let second = makeSet(id: "b", order: 0, number: 2, completed: 1_900.001)
        let third = makeSet(id: "c", order: 0, number: 3, completed: 1_900.003)
        let overlay = MuscyHeartBands.overlay(
            sets: [first, second, third], samples: [MuscyHeartSample(at: 1_400, bpm: 110)],
            sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertTrue(overlay.degraded)
        XCTAssertTrue(overlay.spans.isEmpty)
        XCTAssertTrue(overlay.markers.isEmpty)
        XCTAssertTrue(overlay.exercises[0].sets.allSatisfy { $0.timed == false && $0.average == nil })
    }

    func testBareChecksWithinTwoSecondsAreIgnoredWhenARestExists() {
        let timed = makeSet(id: "a", order: 0, number: 1, completed: 1_100, restStart: 1_100, restEnd: 1_180)
        let close = makeSet(id: "b", order: 0, number: 2, completed: 1_500)
        let closer = makeSet(id: "c", order: 0, number: 3, completed: 1_500.002)
        let overlay = MuscyHeartBands.overlay(
            sets: [timed, close, closer], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlay.markers.map(\.id), ["mark-a"])
        XCTAssertFalse(overlay.spans.contains { $0.kind == .work })
        XCTAssertEqual(overlay.exercises[0].sets[1].timed, false)
        XCTAssertEqual(overlay.exercises[0].sets[2].timed, false)
    }

    func testResumedDraftCountsOnlyFromTheRestEnd() {
        let previous = makeSet(id: "p", order: 0, number: 1, completed: 1_100, restStart: 1_100, restEnd: 1_700)
        let current = makeSet(id: "a", order: 0, number: 2, completed: 1_800)
        let samples = [
            MuscyHeartSample(at: 1_200, bpm: 200),
            MuscyHeartSample(at: 1_750, bpm: 100),
            MuscyHeartSample(at: 1_800, bpm: 120),
        ]
        let overlay = MuscyHeartBands.overlay(
            sets: [previous, current], samples: samples, sessionStart: sessionStart, sessionEnd: sessionEnd)
        let work = overlay.spans.first { $0.kind == .work }
        XCTAssertEqual(work?.start, 1_700)
        XCTAssertEqual(work?.end, 1_800)
        XCTAssertEqual(overlay.exercises[0].sets[1].average, 110)
        XCTAssertEqual(overlay.exercises[0].sets[1].maximum, 120)
        XCTAssertEqual(overlay.exercises[0].average, 110)
    }

    func testRestOverlapIsCappedAtTheNextCheck() {
        let first = makeSet(id: "a", order: 0, number: 1, completed: 1_100, restStart: 1_100, restEnd: 1_900)
        let second = makeSet(id: "b", order: 0, number: 2, completed: 1_400)
        let overlay = MuscyHeartBands.overlay(
            sets: [first, second], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertFalse(overlay.spans.contains { $0.kind == .work })
        XCTAssertEqual(overlay.spans.map(\.id), ["rest-a"])
        XCTAssertEqual(overlay.spans[0].start, 1_100)
        XCTAssertEqual(overlay.spans[0].end, 1_400)
        XCTAssertEqual(overlay.markers.map(\.id), ["mark-a", "mark-b"])
    }

    func testUnsortedSetsCapRestByCheckTime() {
        let later = makeSet(id: "b", order: 0, number: 2, completed: 1_500)
        let earlier = makeSet(id: "a", order: 0, number: 1, completed: 1_100, restStart: 1_100, restEnd: 1_900)
        let overlap = MuscyHeartBands.overlay(
            sets: [later, earlier], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(overlap.spans.map(\.id), ["rest-a"])
        XCTAssertEqual(overlap.spans[0].end, 1_500)
        XCTAssertFalse(overlap.spans.contains { $0.kind == .work })

        let current = makeSet(id: "c", order: 0, number: 2, completed: 1_800)
        let previous = makeSet(id: "p", order: 0, number: 1, completed: 1_100, restStart: 1_100, restEnd: 1_700)
        let band = MuscyHeartBands.overlay(
            sets: [current, previous], samples: [], sessionStart: sessionStart, sessionEnd: sessionEnd)
        XCTAssertEqual(band.spans.first { $0.kind == .work }?.start, 1_700)
        XCTAssertEqual(band.spans.first { $0.kind == .work }?.end, 1_800)
    }

    func testHeartLineBreaksOnALongHoleAndKeepsAShortOne() {
        let start: TimeInterval = 10_000
        let steady = [start, start + 60, start + 120, start + 120 + 6 * 60]
        XCTAssertEqual(MuscyHeartBands.heartSegments(at: steady), [0, 0, 0, 0])
        let hole = [start, start + 60, start + 120, start + 120 + 11 * 60]
        XCTAssertEqual(MuscyHeartBands.heartSegments(at: hole), [0, 0, 0, 1])
    }

    func testClosedSessionWindowDropsEverySpan() {
        let previous = makeSet(id: "p", order: 0, number: 1, completed: 1_040, restStart: 1_040, restEnd: 1_100)
        let set = makeSet(id: "a", order: 0, number: 2, completed: 1_200)
        let overlay = MuscyHeartBands.overlay(
            sets: [previous, set], samples: [MuscyHeartSample(at: 1_150, bpm: 100)],
            sessionStart: 1_500, sessionEnd: 1_500)
        XCTAssertTrue(overlay.degraded)
        XCTAssertNil(overlay.sessionAverage)
    }

    private func makeSet(
        id: String,
        order: Int,
        number: Int,
        name: String = "Développé couché",
        completed: TimeInterval? = nil,
        restStart: TimeInterval? = nil,
        restEnd: TimeInterval? = nil,
        reps: Int = 8,
        load: Double = 40
    ) -> MuscyHeartSet {
        MuscyHeartSet(
            exerciseId: "ex-\(order)",
            exerciseName: name,
            exerciseOrder: order,
            setId: id,
            setNumber: number,
            reps: reps,
            load: load,
            completedAt: completed,
            restStartedAt: restStart,
            restEndedAt: restEnd)
    }
}
