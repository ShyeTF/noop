import Foundation

public enum WhoopSyncTriggerKind: String, Sendable, Equatable {
    /// Opening the app, or the scene becoming active. Never starts a history sync.
    case foregroundOpen
    /// A strap EVENT while the process is awake. History only when the app is not in front.
    case strapEvent
    /// Scene background, phone lock, or the periodic timer. One sync per `backgroundInterval`.
    case backgroundWake
    /// Foreground return. The caller waits until the live link has settled, then
    /// asks for the history the strap has not yet acked.
    case deferredCatchUp
    /// Pull to refresh, or the explicit sync control.
    case manual
    /// A Muscy, Coursy or Vely session just ended with a WHOOP paired. Foreground only: the
    /// strap sends the history it has not acked yet, so the session chart can fill its gaps.
    case sessionEnded
}

/// Pure rules for when a WHOOP history offload may start. No BLE and no clock of its own.
public enum WhoopSyncDecision {
    /// Fifteen minutes. A WHOOP pushes `BATTERY_LEVEL` about every eight minutes; this floor
    /// (the same one `BackfillPolicy` already uses for a periodic offload) stops those wakes
    /// from starting a sync every time, and still brings a night in before morning.
    public static let backgroundInterval: TimeInterval = 15 * 60
    /// Describes a long hole. Opening Nutry does not wait for it: the strap still
    /// holds every chunk that was not acked, and a foreground return asks for that remainder.
    public static let largeGap: TimeInterval = 2 * 60 * 60
    public static let liveSettleDelay: TimeInterval = 5
    /// Same floor as a reconnect offload. Inside it, a foreground return waits
    /// instead of spending one of the three catch-up attempts.
    public static let foregroundRetryFloor: TimeInterval = 90

    /// Scene active, not merely "the process was launched". A Bluetooth restore can
    /// run the launch task while `applicationState` is still `.background`.
    public static func isInForeground(applicationIsActive: Bool) -> Bool {
        applicationIsActive
    }

    public static func allows(
        _ trigger: WhoopSyncTriggerKind,
        inForeground: Bool,
        now: TimeInterval,
        lastSyncAt: TimeInterval?
    ) -> Bool {
        switch trigger {
        case .foregroundOpen:
            return false
        case .manual:
            return true
        case .strapEvent, .backgroundWake:
            guard inForeground == false else { return false }
            return cooledDown(now: now, lastSyncAt: lastSyncAt)
        case .deferredCatchUp:
            // Any return to the foreground, including a cold start that is actually
            // active. The strap cursor is unchanged: only unacked history is sent.
            return inForeground
        case .sessionEnded:
            // Same offload as a catch-up, never in the background: no live link is kept awake for it.
            return inForeground
        }
    }

    private static func cooledDown(now: TimeInterval, lastSyncAt: TimeInterval?) -> Bool {
        guard let last = lastSyncAt else { return true }
        return now - last >= backgroundInterval
    }
}

public enum WhoopCatchUpStep: Equatable, Sendable {
    case wait(TimeInterval)
    case start
    case giveUp
}

/// Morning catch-up. Waits until the strap is connected, bonded and stable, then retries.
/// A missing link does not burn an attempt. An offload already running is not stacked.
public enum WhoopCatchUp {
    public static let maxAttempts = 3

    public static func backoff(afterFailedAttempts failed: Int) -> TimeInterval {
        WhoopSyncDecision.liveSettleDelay * pow(2, Double(max(0, failed)))
    }

    public static func next(
        inForeground: Bool,
        connected: Bool,
        bonded: Bool,
        backfilling: Bool,
        gapIsLarge: Bool,
        stableSeconds: TimeInterval,
        failedAttempts: Int
    ) -> WhoopCatchUpStep {
        if inForeground == false || gapIsLarge == false || failedAttempts >= maxAttempts {
            return .giveUp
        }
        if connected == false || bonded == false {
            return .wait(WhoopSyncDecision.liveSettleDelay)
        }
        if stableSeconds < WhoopSyncDecision.liveSettleDelay {
            return .wait(WhoopSyncDecision.liveSettleDelay - stableSeconds)
        }
        if backfilling {
            return .wait(backoff(afterFailedAttempts: failedAttempts))
        }
        return .start
    }
}
