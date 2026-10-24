import Foundation

public struct LiveBeatSample: Equatable, Sendable {
    public var t: TimeInterval
    public var bpm: Double

    public init(t: TimeInterval, bpm: Double) {
        self.t = t
        self.bpm = bpm
    }
}

public struct LiveBeatPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One monotone-cubic segment. Control points stay inside the segment's y range when the
/// samples themselves are monotone, so the stroke does not ring past a peak.
public struct LiveBeatCubic: Equatable, Sendable {
    public var x0: Double
    public var y0: Double
    public var c1x: Double
    public var c1y: Double
    public var c2x: Double
    public var c2y: Double
    public var x1: Double
    public var y1: Double

    public init(x0: Double, y0: Double, c1x: Double, c1y: Double, c2x: Double, c2y: Double, x1: Double, y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.c1x = c1x
        self.c1y = c1y
        self.c2x = c2x
        self.c2y = c2y
        self.x1 = x1
        self.y1 = y1
    }
}

/// Time-based layout for the 90-sample live heart curve. Arrival order is kept: nothing is
/// sorted or downsampled on the draw path.
public enum LiveBeatScroll {
    public static let capacity = 90
    public static let window: TimeInterval = 90

    /// Ring buffer shared by the live number and the curve. Unlinked or unusable samples clear it.
    public static func feed(
        _ samples: [LiveBeatSample],
        bpm: Double,
        at time: TimeInterval,
        linked: Bool
    ) -> [LiveBeatSample] {
        guard linked, bpm > 0, bpm.isFinite, time.isFinite else { return [] }
        var next = samples
        if let last = next.last, abs(time - last.t) < 0.5 {
            next[next.count - 1] = LiveBeatSample(t: max(last.t, time), bpm: bpm)
        } else {
            next.append(LiveBeatSample(t: time, bpm: bpm))
        }
        if next.count > capacity {
            next.removeFirst(next.count - capacity)
        }
        return next
    }

    public static func unitX(sampleTime: TimeInterval, now: TimeInterval, window: TimeInterval = LiveBeatScroll.window) -> Double {
        guard window > 0 else { return 0 }
        return (sampleTime - (now - window)) / window
    }

    public static func smoothstep(_ unit: Double) -> Double {
        let clamped = min(1, max(0, unit))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// The head eases from the previous bpm to the new one across the gap between them.
    public static func headBPM(previous: Double, latest: Double, elapsed: TimeInterval, gap: TimeInterval) -> Double {
        let span = max(gap, 0.05)
        return previous + (latest - previous) * smoothstep(elapsed / span)
    }

    public static func easedBound(current: Double, target: Double, dt: TimeInterval, tau: TimeInterval = 0.45) -> Double {
        guard dt > 0, tau > 0, current.isFinite, target.isFinite else {
            return target.isFinite ? target : current
        }
        let blend = 1 - exp(-dt / tau)
        return current + (target - current) * blend
    }

    /// How long the y-axis spends blending from the previous min/max to the new ones.
    public static let boundsEase: TimeInterval = 0.45

    /// Y bounds at `now`. Smoothstep from the bounds stored on the curve. No allocation.
    /// `+infinity` (Reduce Motion, scrub) snaps to the target. The result stays finite.
    public static func easedAxis(curve: LiveBeatCurve, now: TimeInterval) -> LiveBeatAxis {
        let unit = axisUnit(now: now, started: curve.boundsAt)
        let low = curve.previousLow + (curve.low - curve.previousLow) * unit
        let high = curve.previousHigh + (curve.high - curve.previousHigh) * unit
        return LiveBeatAxis(low: finite(low, fallback: curve.low), high: finite(high, fallback: curve.high))
    }

    private static func axisUnit(now: TimeInterval, started: TimeInterval) -> Double {
        if now == .infinity { return 1 }
        guard now.isFinite, started.isFinite, boundsEase > 0 else { return 1 }
        let elapsed = now - started
        guard elapsed.isFinite else { return 1 }
        if elapsed >= boundsEase { return 1 }
        if elapsed <= 0 { return 0 }
        return smoothstep(elapsed / boundsEase)
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        if value.isFinite { return value }
        if fallback.isFinite { return fallback }
        return 0
    }

    /// Unit x and bpm. Older samples stay at their true value. The newest sample is not
    /// drawn twice: the head IS that sample, eased in x and y from the previous one.
    /// `blend` overrides the time ease (Reduce Motion). Nil uses the gap since the sample.
    public static func layout(
        samples: [LiveBeatSample],
        now: TimeInterval,
        window: TimeInterval = LiveBeatScroll.window,
        blend: Double? = nil
    ) -> [LiveBeatPoint] {
        let count = samples.count
        guard count > 0, window > 0 else { return [] }
        var times = [TimeInterval]()
        var bpms = [Double]()
        times.reserveCapacity(count)
        bpms.reserveCapacity(count)
        for sample in samples {
            times.append(sample.t)
            bpms.append(sample.bpm)
        }
        return points(times: times, bpms: bpms, now: now, window: window, blend: blend)
    }

    /// One points array per frame. The caller keeps `times` and `bpms` across frames.
    public static func points(
        times: [TimeInterval],
        bpms: [Double],
        now: TimeInterval,
        window: TimeInterval = LiveBeatScroll.window,
        blend: Double? = nil
    ) -> [LiveBeatPoint] {
        let count = min(times.count, bpms.count)
        guard count > 0, window > 0 else { return [] }
        var lastIndex = count - 1
        while lastIndex >= 0, bpms[lastIndex].isFinite == false { lastIndex -= 1 }
        guard lastIndex >= 0 else { return [] }
        let start = now - window
        func unit(_ t: TimeInterval) -> Double { (t - start) / window }
        var points: [LiveBeatPoint] = []
        points.reserveCapacity(lastIndex + 1)
        var previousIndex: Int?
        if lastIndex > 0 {
            for index in 0..<lastIndex {
                guard bpms[index].isFinite else { continue }
                previousIndex = index
                let x = unit(times[index])
                if x < -0.02 || x > 1.05 { continue }
                points.append(LiveBeatPoint(x: x, y: bpms[index]))
            }
        }
        let latestT = times[lastIndex]
        let latestB = bpms[lastIndex]
        if let previous = previousIndex {
            let gap = max(0.05, latestT - times[previous])
            let elapsed = now - latestT
            let unitBlend = blend ?? smoothstep(elapsed / gap)
            let originX = unit(times[previous])
            let headX = originX + (unit(latestT) - originX) * unitBlend
            let headY = bpms[previous] + (latestB - bpms[previous]) * unitBlend
            points.append(LiveBeatPoint(x: headX, y: headY))
        } else {
            let x = unit(latestT)
            if x >= -0.02, x <= 1.05 {
                points.append(LiveBeatPoint(x: x, y: latestB))
            }
        }
        return points
    }

    public static func trim(_ samples: [LiveBeatSample], capacity: Int = LiveBeatScroll.capacity) -> [LiveBeatSample] {
        guard capacity > 0, samples.count > capacity else { return samples }
        return Array(samples.suffix(capacity))
    }

    /// Fritsch–Carlson monotone cubic. A linear run stays on the line.
    public static func monotoneCubics(_ points: [LiveBeatPoint]) -> [LiveBeatCubic] {
        let count = points.count
        guard count >= 2 else { return [] }
        if count == 2 {
            let start = points[0]
            let end = points[1]
            return [LiveBeatCubic(
                x0: start.x, y0: start.y,
                c1x: start.x, c1y: start.y,
                c2x: end.x, c2y: end.y,
                x1: end.x, y1: end.y)]
        }
        var dx = [Double](repeating: 0, count: count - 1)
        var slope = [Double](repeating: 0, count: count - 1)
        for index in 0..<(count - 1) {
            let span = points[index + 1].x - points[index].x
            dx[index] = span == 0 ? 0.000_1 : span
            slope[index] = (points[index + 1].y - points[index].y) / dx[index]
        }
        var tangent = [Double](repeating: 0, count: count)
        tangent[0] = slope[0]
        tangent[count - 1] = slope[count - 2]
        if count > 2 {
            for index in 1..<(count - 1) {
                if slope[index - 1] * slope[index] <= 0 {
                    tangent[index] = 0
                } else {
                    tangent[index] = (slope[index - 1] + slope[index]) / 2
                }
            }
        }
        for index in 0..<(count - 1) {
            if slope[index] == 0 {
                tangent[index] = 0
                tangent[index + 1] = 0
                continue
            }
            let alpha = tangent[index] / slope[index]
            let beta = tangent[index + 1] / slope[index]
            let magnitude = hypot(alpha, beta)
            if magnitude > 3 {
                let scale = 3 / magnitude
                tangent[index] = scale * alpha * slope[index]
                tangent[index + 1] = scale * beta * slope[index]
            }
        }
        var cubics: [LiveBeatCubic] = []
        cubics.reserveCapacity(count - 1)
        for index in 0..<(count - 1) {
            let span = dx[index]
            cubics.append(LiveBeatCubic(
                x0: points[index].x,
                y0: points[index].y,
                c1x: points[index].x + span / 3,
                c1y: points[index].y + tangent[index] * span / 3,
                c2x: points[index + 1].x - span / 3,
                c2y: points[index + 1].y - tangent[index + 1] * span / 3,
                x1: points[index + 1].x,
                y1: points[index + 1].y))
        }
        return cubics
    }

    /// Unit-x slide from the layout anchor to `now`. Negative as time moves forward.
    public static func timeShift(anchor: TimeInterval, now: TimeInterval, window: TimeInterval = LiveBeatScroll.window) -> Double {
        guard window > 0 else { return 0 }
        return (anchor - now) / window
    }

    /// Head only. Body cubics stay as stored at the last sample.
    public static func headPoint(curve: LiveBeatCurve, now: TimeInterval, blend: Double?) -> LiveBeatPoint? {
        guard curve.hasHead else { return nil }
        let elapsed = now - curve.latestT
        let unit = blend ?? smoothstep(elapsed / max(curve.gap, 0.05))
        let shift = timeShift(anchor: curve.anchor, now: now)
        let x = curve.prevX + (curve.latestX - curve.prevX) * unit + shift
        let y = curve.prevY + (curve.latestY - curve.prevY) * unit
        return LiveBeatPoint(x: x, y: y)
    }
}

/// Fixed 90-sample ring plus the cubics of every sample except the moving head.
/// Cubics are rebuilt only when `make` runs. A frame translates them and eases the head.
public struct LiveBeatCurve: Equatable, Sendable {
    public var count: Int
    public var times: [TimeInterval]
    public var bpms: [Double]
    public var anchor: TimeInterval
    public var body: [LiveBeatCubic]
    public var prevX: Double
    public var prevY: Double
    public var latestX: Double
    public var latestY: Double
    public var latestT: TimeInterval
    public var gap: TimeInterval
    public var hasHead: Bool
    public var low: Double
    public var high: Double
    /// Bounds in force before this sample. Equal to `low`/`high` when the curve has nothing to ease from.
    public var previousLow: Double
    public var previousHigh: Double
    /// Wall time of the sample that stored `previousLow`/`previousHigh`.
    public var boundsAt: TimeInterval

    public static let empty = LiveBeatCurve(
        count: 0,
        times: [TimeInterval](repeating: 0, count: LiveBeatScroll.capacity),
        bpms: [Double](repeating: .nan, count: LiveBeatScroll.capacity),
        anchor: 0,
        body: [],
        prevX: 0,
        prevY: 0,
        latestX: 0,
        latestY: 0,
        latestT: 0,
        gap: 1,
        hasHead: false,
        low: 50,
        high: 120,
        previousLow: 50,
        previousHigh: 120,
        boundsAt: 0)

    public static func make(
        times sourceTimes: [TimeInterval],
        bpms sourceBpms: [Double],
        anchor: TimeInterval,
        previousLow carriedLow: Double? = nil,
        previousHigh carriedHigh: Double? = nil,
        boundsAt carriedAt: TimeInterval? = nil
    ) -> LiveBeatCurve {
        let total = min(sourceTimes.count, sourceBpms.count)
        let count = min(LiveBeatScroll.capacity, max(0, total))
        let start = total - count
        var times = [TimeInterval](repeating: 0, count: LiveBeatScroll.capacity)
        var bpms = [Double](repeating: .nan, count: LiveBeatScroll.capacity)
        var low = 50.0
        var high = 120.0
        var seen = false
        for index in 0..<count {
            let bpm = sourceBpms[start + index]
            times[index] = sourceTimes[start + index]
            bpms[index] = bpm
            guard bpm.isFinite else { continue }
            if seen == false {
                low = bpm
                high = bpm
                seen = true
            } else {
                low = min(low, bpm)
                high = max(high, bpm)
            }
        }
        if seen, high - low < 10 {
            let mid = (high + low) / 2
            low = mid - 5
            high = mid + 5
        }
        var latestIndex: Int?
        var previousIndex: Int?
        for index in 0..<count where bpms[index].isFinite {
            previousIndex = latestIndex
            latestIndex = index
        }
        guard let latest = latestIndex else {
            var blank = LiveBeatCurve.empty
            blank.anchor = anchor
            blank.boundsAt = anchor
            return blank
        }
        let latestT = times[latest]
        let latestX = LiveBeatScroll.unitX(sampleTime: latestT, now: anchor)
        let latestY = bpms[latest]
        var bodyPoints: [LiveBeatPoint] = []
        var prevX = latestX
        var prevY = latestY
        var gap: TimeInterval = 1
        var hasHead = false
        if let previous = previousIndex {
            hasHead = true
            let previousT = times[previous]
            gap = max(0.05, latestT - previousT)
            prevX = LiveBeatScroll.unitX(sampleTime: previousT, now: anchor)
            prevY = bpms[previous]
            bodyPoints.reserveCapacity(previous + 1)
            for index in 0..<latest {
                guard bpms[index].isFinite else { continue }
                let x = LiveBeatScroll.unitX(sampleTime: times[index], now: anchor)
                if x < -0.02 || x > 1.05 { continue }
                bodyPoints.append(LiveBeatPoint(x: x, y: bpms[index]))
            }
        }
        let previousLow: Double
        let previousHigh: Double
        let boundsAt: TimeInterval
        if let carriedLow, let carriedHigh {
            previousLow = carriedLow
            previousHigh = carriedHigh
            boundsAt = carriedAt ?? anchor
        } else {
            previousLow = low
            previousHigh = high
            boundsAt = anchor
        }
        return LiveBeatCurve(
            count: count,
            times: times,
            bpms: bpms,
            anchor: anchor,
            body: LiveBeatScroll.monotoneCubics(bodyPoints),
            prevX: prevX,
            prevY: prevY,
            latestX: latestX,
            latestY: latestY,
            latestT: latestT,
            gap: gap,
            hasHead: hasHead,
            low: low,
            high: high,
            previousLow: previousLow,
            previousHigh: previousHigh,
            boundsAt: boundsAt)
    }
}

public struct LiveBeatAxis: Equatable, Sendable {
    public var low: Double
    public var high: Double

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }
}
