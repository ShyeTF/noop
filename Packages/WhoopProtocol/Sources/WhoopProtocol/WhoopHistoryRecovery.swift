import Foundation

/// Splits a time series so a chart does not draw across a hole.
/// The hole follows that series: `max(base, 3 × median interval)`.
public enum WhoopChartGaps {
    /// Heart-rate base. One missing five-minute bucket stays on the same curve.
    public static let heartSeconds: TimeInterval = 10 * 60
    /// The strap reports its charge about every eight minutes. A longer hole is a gap.
    public static let batterySeconds: TimeInterval = 20 * 60
    /// A missing calendar day. Consecutive days stay one curve.
    public static let daySeconds: TimeInterval = 36 * 60 * 60

    /// Wider of the base and three times the median positive step.
    /// A sparse series (weight, a slow HealthKit sample) stays one curve.
    /// A hole wider than both still splits.
    public static func gap(at times: [TimeInterval], base: TimeInterval) -> TimeInterval {
        max(base, 3 * medianInterval(times))
    }

    /// Median of the positive steps. `times` are chronological. Fewer than two steps returns 0.
    public static func medianInterval(_ times: [TimeInterval]) -> TimeInterval {
        guard times.count >= 2 else { return 0 }
        var steps: [TimeInterval] = []
        steps.reserveCapacity(times.count - 1)
        for index in 1..<times.count {
            let step = times[index] - times[index - 1]
            if step > 0 { steps.append(step) }
        }
        guard steps.isEmpty == false else { return 0 }
        steps.sort()
        let mid = steps.count / 2
        if steps.count % 2 == 1 { return steps[mid] }
        return (steps[mid - 1] + steps[mid]) / 2
    }

    /// Segment ids, same order as `times`. The first sample is segment 0.
    public static func segments(at times: [TimeInterval], maxGap: TimeInterval) -> [Int] {
        var ids: [Int] = []
        ids.reserveCapacity(times.count)
        var segment = 0
        var previous: TimeInterval?
        for time in times {
            if let previous, time - previous > maxGap {
                segment += 1
            }
            ids.append(segment)
            previous = time
        }
        return ids
    }
}

/// A pass that stored sensor rows asks for a rescore, including an idle timeout.
/// An empty pass does not. The caller publishes an in-memory instant; nothing is stored in UserDefaults.
public enum WhoopBankedPass {
    public static func schedulesRescore(persistedRows: Bool) -> Bool {
        persistedRows
    }
}
