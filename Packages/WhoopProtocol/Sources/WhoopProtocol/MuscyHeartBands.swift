import Foundation

/// Places a Muscy strength session’s heart-rate samples on the sets that were actually timed.
/// A work band runs from the end of the previous set’s rest to this check, and only when that
/// rest end sits strictly between the two checks. Any other check is a point, with no duration.
/// Nothing is inferred from exercise order, session length, or the moment a load was typed.
public struct MuscyHeartSample: Equatable, Sendable {
    public var at: TimeInterval
    public var bpm: Double

    public init(at: TimeInterval, bpm: Double) {
        self.at = at
        self.bpm = bpm
    }
}

public struct MuscyHeartSet: Equatable, Sendable {
    public var exerciseId: String
    public var exerciseName: String
    public var exerciseOrder: Int
    public var setId: String
    public var setNumber: Int
    public var reps: Int
    public var load: Double
    public var completedAt: TimeInterval?
    public var restStartedAt: TimeInterval?
    public var restEndedAt: TimeInterval?

    public init(
        exerciseId: String,
        exerciseName: String,
        exerciseOrder: Int,
        setId: String,
        setNumber: Int,
        reps: Int,
        load: Double,
        completedAt: TimeInterval? = nil,
        restStartedAt: TimeInterval? = nil,
        restEndedAt: TimeInterval? = nil
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.exerciseOrder = exerciseOrder
        self.setId = setId
        self.setNumber = setNumber
        self.reps = reps
        self.load = load
        self.completedAt = completedAt
        self.restStartedAt = restStartedAt
        self.restEndedAt = restEndedAt
    }
}

public struct MuscyHeartSpan: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case work
        case rest
    }

    public var id: String
    public var setId: String
    public var kind: Kind
    public var exerciseId: String
    public var exerciseName: String
    public var setNumber: Int
    public var reps: Int
    public var load: Double
    public var colorIndex: Int
    public var start: TimeInterval
    public var end: TimeInterval

    public init(
        id: String,
        setId: String,
        kind: Kind,
        exerciseId: String,
        exerciseName: String,
        setNumber: Int,
        reps: Int,
        load: Double,
        colorIndex: Int,
        start: TimeInterval,
        end: TimeInterval
    ) {
        self.id = id
        self.setId = setId
        self.kind = kind
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.load = load
        self.colorIndex = colorIndex
        self.start = start
        self.end = end
    }
}

public struct MuscyHeartMarker: Equatable, Sendable, Identifiable {
    public var id: String
    public var exerciseId: String
    public var exerciseName: String
    public var setNumber: Int
    public var reps: Int
    public var load: Double
    public var colorIndex: Int
    public var at: TimeInterval

    public init(
        id: String,
        exerciseId: String,
        exerciseName: String,
        setNumber: Int,
        reps: Int,
        load: Double,
        colorIndex: Int,
        at: TimeInterval
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.load = load
        self.colorIndex = colorIndex
        self.at = at
    }
}

public struct MuscyHeartSetStat: Equatable, Sendable, Identifiable {
    public var id: String
    public var setNumber: Int
    public var reps: Int
    public var load: Double
    /// True only when a real work interval was stored. A lone completion stamp is not an interval.
    public var timed: Bool
    public var average: Double?
    public var maximum: Double?

    public init(
        id: String,
        setNumber: Int,
        reps: Int,
        load: Double,
        timed: Bool,
        average: Double?,
        maximum: Double?
    ) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.load = load
        self.timed = timed
        self.average = average
        self.maximum = maximum
    }
}

public struct MuscyHeartExerciseStat: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var colorIndex: Int
    public var average: Double?
    public var maximum: Double?
    public var sets: [MuscyHeartSetStat]

    public init(
        id: String,
        name: String,
        colorIndex: Int,
        average: Double?,
        maximum: Double?,
        sets: [MuscyHeartSetStat]
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.average = average
        self.maximum = maximum
        self.sets = sets
    }
}

public struct MuscyHeartOverlay: Equatable, Sendable {
    public var spans: [MuscyHeartSpan]
    public var markers: [MuscyHeartMarker]
    public var exercises: [MuscyHeartExerciseStat]
    /// No stored work interval, rest interval, or trusted completion point.
    public var degraded: Bool
    public var sessionAverage: Double?
    public var sessionMaximum: Double?

    public init(
        spans: [MuscyHeartSpan],
        markers: [MuscyHeartMarker],
        exercises: [MuscyHeartExerciseStat],
        degraded: Bool,
        sessionAverage: Double?,
        sessionMaximum: Double?
    ) {
        self.spans = spans
        self.markers = markers
        self.exercises = exercises
        self.degraded = degraded
        self.sessionAverage = sessionAverage
        self.sessionMaximum = sessionMaximum
    }
}

public enum MuscyHeartBands {
    public static func heartSegments(at times: [TimeInterval]) -> [Int] {
        let gap = WhoopChartGaps.gap(at: times, base: WhoopChartGaps.heartSeconds)
        return WhoopChartGaps.segments(at: times, maxGap: gap)
    }

    public static func overlay(
        sets: [MuscyHeartSet],
        samples: [MuscyHeartSample],
        sessionStart: TimeInterval,
        sessionEnd: TimeInterval
    ) -> MuscyHeartOverlay {
        let ordered = sets.sorted { lhs, rhs in
            if lhs.exerciseOrder != rhs.exerciseOrder { return lhs.exerciseOrder < rhs.exerciseOrder }
            if lhs.setNumber != rhs.setNumber { return lhs.setNumber < rhs.setNumber }
            return lhs.setId < rhs.setId
        }
        let checks = trustedChecks(sets)
        var spans: [MuscyHeartSpan] = []
        var markers: [MuscyHeartMarker] = []
        var workBySet: [String: MuscyHeartSpan] = [:]
        for set in ordered {
            if let work = workSpan(set, checks: checks, sessionStart: sessionStart, sessionEnd: sessionEnd) {
                spans.append(work)
                workBySet[set.setId] = work
            } else if let point = marker(set, checks: checks, sessionStart: sessionStart, sessionEnd: sessionEnd) {
                markers.append(point)
            }
            if let rest = restSpan(set, checks: checks, sessionStart: sessionStart, sessionEnd: sessionEnd) {
                spans.append(rest)
            }
        }
        let session = summarize(bpmValues(samples, from: sessionStart, to: sessionEnd))
        let exercises = exerciseStats(ordered, samples: samples, workBySet: workBySet)
        let degraded = spans.isEmpty && markers.isEmpty
        return MuscyHeartOverlay(
            spans: spans,
            markers: markers,
            exercises: exercises,
            degraded: degraded,
            sessionAverage: session.average,
            sessionMaximum: session.maximum)
    }

    private struct CheckedSet {
        var set: MuscyHeartSet
        var at: TimeInterval
    }

    /// Old saves stamped each set in a loop, so two clocks from one save can differ by a few milliseconds.
    private static let bareCheckProximity: TimeInterval = 2

    /// A session with no rest timestamps has no trusted check, including a single set.
    /// Where a rest exists, a completion with no rest that sits within 2 s of another check is the same save.
    private static func trustedChecks(_ sets: [MuscyHeartSet]) -> [CheckedSet] {
        let anyRest = sets.contains { $0.restStartedAt != nil || $0.restEndedAt != nil }
        guard anyRest else { return [] }
        let completions = sets.compactMap { set -> (id: String, at: TimeInterval)? in
            guard let completed = set.completedAt else { return nil }
            return (set.setId, completed)
        }
        return sets.compactMap { set in
            guard let completed = set.completedAt else { return nil }
            let hasRest = set.restStartedAt != nil || set.restEndedAt != nil
            if hasRest == false {
                let nearAnother = completions.contains { other in
                    other.id != set.setId && abs(other.at - completed) <= bareCheckProximity
                }
                if nearAnother { return nil }
            }
            return CheckedSet(set: set, at: completed)
        }.sorted { lhs, rhs in
            if lhs.at != rhs.at { return lhs.at < rhs.at }
            return lhs.set.setId < rhs.set.setId
        }
    }

    /// Work is only the gap after a rest that really ended before this check.
    private static func workSpan(
        _ set: MuscyHeartSet,
        checks: [CheckedSet],
        sessionStart: TimeInterval,
        sessionEnd: TimeInterval
    ) -> MuscyHeartSpan? {
        guard let completed = set.completedAt else { return nil }
        guard checks.contains(where: { $0.set.setId == set.setId }) else { return nil }
        guard let previous = checks.last(where: { $0.at < completed }) else { return nil }
        guard let restEnd = previous.set.restEndedAt else { return nil }
        let previousCheck = previous.at
        guard previousCheck < restEnd, restEnd < completed else { return nil }
        guard let window = clipped(restEnd, completed, sessionStart: sessionStart, sessionEnd: sessionEnd) else {
            return nil
        }
        return MuscyHeartSpan(
            id: "work-\(set.setId)",
            setId: set.setId,
            kind: .work,
            exerciseId: set.exerciseId,
            exerciseName: displayName(set.exerciseName),
            setNumber: set.setNumber,
            reps: set.reps,
            load: set.load,
            colorIndex: set.exerciseOrder,
            start: window.lower,
            end: window.upper)
    }

    /// Rests are capped at the next check in time, not in array order, so a planned end cannot cover the next set.
    private static func restSpan(
        _ set: MuscyHeartSet,
        checks: [CheckedSet],
        sessionStart: TimeInterval,
        sessionEnd: TimeInterval
    ) -> MuscyHeartSpan? {
        guard let started = set.restStartedAt, var ended = set.restEndedAt else { return nil }
        let anchor = set.completedAt ?? started
        if let nextCheck = checks.first(where: { $0.at > anchor }) {
            ended = min(ended, nextCheck.at)
        }
        guard let window = clipped(started, ended, sessionStart: sessionStart, sessionEnd: sessionEnd) else {
            return nil
        }
        return MuscyHeartSpan(
            id: "rest-\(set.setId)",
            setId: set.setId,
            kind: .rest,
            exerciseId: set.exerciseId,
            exerciseName: displayName(set.exerciseName),
            setNumber: set.setNumber,
            reps: set.reps,
            load: set.load,
            colorIndex: set.exerciseOrder,
            start: window.lower,
            end: window.upper)
    }

    /// A point at the check. Duration and averages stay empty.
    private static func marker(
        _ set: MuscyHeartSet,
        checks: [CheckedSet],
        sessionStart: TimeInterval,
        sessionEnd: TimeInterval
    ) -> MuscyHeartMarker? {
        guard let completed = set.completedAt else { return nil }
        guard checks.contains(where: { $0.set.setId == set.setId }) else { return nil }
        guard completed >= sessionStart, completed <= sessionEnd else { return nil }
        return MuscyHeartMarker(
            id: "mark-\(set.setId)",
            exerciseId: set.exerciseId,
            exerciseName: displayName(set.exerciseName),
            setNumber: set.setNumber,
            reps: set.reps,
            load: set.load,
            colorIndex: set.exerciseOrder,
            at: completed)
    }

    private struct Window {
        var lower: TimeInterval
        var upper: TimeInterval
    }

    /// Intersection with the session. The interval is never widened.
    private static func clipped(
        _ start: TimeInterval,
        _ end: TimeInterval,
        sessionStart: TimeInterval,
        sessionEnd: TimeInterval
    ) -> Window? {
        guard start < end, sessionStart < sessionEnd else { return nil }
        let lower = max(start, sessionStart)
        let upper = min(end, sessionEnd)
        guard lower < upper else { return nil }
        return Window(lower: lower, upper: upper)
    }

    private static func exerciseStats(
        _ sets: [MuscyHeartSet],
        samples: [MuscyHeartSample],
        workBySet: [String: MuscyHeartSpan]
    ) -> [MuscyHeartExerciseStat] {
        var order: [String] = []
        var grouped: [String: [MuscyHeartSet]] = [:]
        for set in sets {
            if grouped[set.exerciseId] == nil {
                order.append(set.exerciseId)
                grouped[set.exerciseId] = []
            }
            grouped[set.exerciseId, default: []].append(set)
        }
        return order.map { exerciseId in
            let rows = grouped[exerciseId] ?? []
            let name = displayName(rows.first?.exerciseName ?? "")
            let colorIndex = rows.first?.exerciseOrder ?? 0
            var seen: Set<Int> = []
            var pooled: [Double] = []
            let setStats: [MuscyHeartSetStat] = rows.map { set in
                let span = workBySet[set.setId]
                let inside = span.map { bpmValues(samples, from: $0.start, to: $0.end) } ?? []
                if let span {
                    pooled.append(contentsOf: bpmValues(samples, from: span.start, to: span.end, skipping: &seen))
                }
                let summary = summarize(inside)
                return MuscyHeartSetStat(
                    id: set.setId,
                    setNumber: set.setNumber,
                    reps: set.reps,
                    load: set.load,
                    timed: span != nil,
                    average: summary.average,
                    maximum: summary.maximum)
            }
            let exercise = summarize(pooled)
            return MuscyHeartExerciseStat(
                id: exerciseId,
                name: name,
                colorIndex: colorIndex,
                average: exercise.average,
                maximum: exercise.maximum,
                sets: setStats)
        }
    }

    private static func bpmValues(
        _ samples: [MuscyHeartSample],
        from start: TimeInterval,
        to end: TimeInterval
    ) -> [Double] {
        guard start < end else { return [] }
        return samples.compactMap { sample in
            guard sample.at >= start, sample.at <= end, sample.bpm.isFinite, sample.bpm > 0 else { return nil }
            return sample.bpm
        }
    }

    /// Same window, each sample once, so two touching sets do not double an exercise average.
    private static func bpmValues(
        _ samples: [MuscyHeartSample],
        from start: TimeInterval,
        to end: TimeInterval,
        skipping seen: inout Set<Int>
    ) -> [Double] {
        guard start < end else { return [] }
        var kept: [Double] = []
        for (index, sample) in samples.enumerated() {
            guard seen.contains(index) == false else { continue }
            guard sample.at >= start, sample.at <= end, sample.bpm.isFinite, sample.bpm > 0 else { continue }
            seen.insert(index)
            kept.append(sample.bpm)
        }
        return kept
    }

    private struct Summary {
        var average: Double?
        var maximum: Double?
    }

    private static func summarize(_ values: [Double]) -> Summary {
        guard let maximum = values.max() else { return Summary(average: nil, maximum: nil) }
        let total = values.reduce(0, +)
        return Summary(average: total / Double(values.count), maximum: maximum)
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Exercice" : trimmed
    }
}
