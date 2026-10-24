import Foundation

public enum WhoopPackSignal: Equatable, Sendable {
    case info(BatteryPackInfo.Info, eventTimestamp: Int)
    case attached(eventTimestamp: Int)
    case removed(eventTimestamp: Int)
}

public struct WhoopPackState: Equatable, Sendable {
    public var socPct: Double?
    public var present: Bool
    /// Wall clock of the last accepted event 109. The 10-minute blanking uses this, not the strap clock.
    public var lastInfoWall: TimeInterval?
    public var lastEventTimestamp: Int

    public init(
        socPct: Double? = nil,
        present: Bool = false,
        lastInfoWall: TimeInterval? = nil,
        lastEventTimestamp: Int = 0
    ) {
        self.socPct = socPct
        self.present = present
        self.lastInfoWall = lastInfoWall
        self.lastEventTimestamp = lastEventTimestamp
    }
}

public enum WhoopPackDisplay: Equatable, Sendable {
    case hidden
    case connected
    case percent(Double)

    public static func resolve(present: Bool, socPct: Double?) -> WhoopPackDisplay {
        if let soc = socPct, soc >= 0, soc <= 100 { return .percent(soc) }
        if present { return .connected }
        return .hidden
    }
}

/// Live pack gauge from the strap's own pushes. Event 109 never touches charging.
/// Command 151 is not used: the strap pushes this record, and 151 is not sent.
public enum WhoopPackLive {
    public static let staleAfter: TimeInterval = 10 * 60
    public static let freshWindowSeconds = 45

    public static func reduce(
        _ state: WhoopPackState,
        signal: WhoopPackSignal,
        now: Int,
        duringOffload: Bool,
        wallNow: TimeInterval
    ) -> WhoopPackState {
        let ts = timestamp(signal)
        guard accept(ts: ts, now: now, duringOffload: duringOffload, last: state.lastEventTimestamp) else {
            return state
        }
        var next = state
        if ts > next.lastEventTimestamp { next.lastEventTimestamp = ts }
        switch signal {
        case .info(let info, _):
            if info.present == false {
                next.socPct = nil
                next.present = false
                next.lastInfoWall = nil
            } else if info.displayable, let soc = info.socPct {
                next.socPct = soc
                next.present = true
                next.lastInfoWall = wallNow
            } else {
                next.socPct = nil
                next.present = true
                next.lastInfoWall = wallNow
            }
        case .attached:
            next.present = true
        case .removed:
            next.present = false
            next.socPct = nil
            next.lastInfoWall = nil
        }
        return next
    }

    /// Drops the percentage and the presence after ten minutes without an accepted event 109.
    /// A pack only marked by event 21 has no `lastInfoWall` and is left as it is.
    public static func expire(_ state: WhoopPackState, wallNow: TimeInterval) -> WhoopPackState {
        guard let seen = state.lastInfoWall, wallNow - seen >= staleAfter else { return state }
        var next = state
        next.socPct = nil
        next.present = false
        next.lastInfoWall = nil
        return next
    }

    private static func timestamp(_ signal: WhoopPackSignal) -> Int {
        switch signal {
        case .info(_, let ts), .attached(let ts), .removed(let ts):
            return ts
        }
    }

    private static func accept(ts: Int, now: Int, duringOffload: Bool, last: Int) -> Bool {
        if duringOffload == false { return true }
        if ts <= 0 { return false }
        if abs(now - ts) > freshWindowSeconds { return false }
        if ts < last { return false }
        return true
    }
}
