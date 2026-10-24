import Foundation

/// What Nutry may do while a strap is linked. Pure: no Bluetooth and no clock.
public enum NutryBackgroundActivity: String, CaseIterable, Sendable {
    case keepAliveTimer
    case standardHeartNotify
    case realtimeStream
    case silenceWatchdog
    case liveRelay
    case runTogetherPoll
    case muscyPoll
    case followedLivePoll
    case presencePoll
    case musicPoll
    case rescore
    case refreshV5
    case accountSync
    case autoContinue
    case historyOffload
}

public enum NutryEnergyScene: String, CaseIterable, Sendable {
    case active
    case inactive
    case background
    case locked
}

/// Why the process is running. Entering the background is not a reason to start work.
public enum NutryWakeTrigger: String, CaseIterable, Sendable {
    case none
    case foreground
    case sceneBackground
    case backgroundRefresh
    case backgroundProcessing
    case strapEvent
    case reconnection
    case stateRestoration
    case manual
}

public enum WhoopEnergyBudget {
    public enum Thermal: String, Sendable, Equatable {
        case nominal
        case fair
        case serious
        case critical
    }

    public static let orphanSessionMaxAge: TimeInterval = 4 * 60 * 60
    /// One history wake, then the process must be allowed to suspend.
    /// The strap pushes a battery event about every eight minutes and the sync
    /// floor is fifteen minutes. Each wake stops at this budget. Continuation
    /// stays foreground-only, so these sessions cannot hold Nutry awake for hours.
    public static let backgroundSyncMaxDuration: TimeInterval = 30
    public static let analysisMinInterval: TimeInterval = 15 * 60
    public static let reconnectBase: TimeInterval = 4
    public static let reconnectCap: TimeInterval = 120
    public static let maxFastReconnectAttempts = 5
    public static let foregroundLiveActivityInterval: TimeInterval = 2.5
    public static let backgroundLiveActivityInterval: TimeInterval = 15

    public struct PresenceLocation: Equatable, Sendable {
        public var accuracyMeters: Double
        public var distanceFilterMeters: Double
        public var allowsBackground: Bool

        public init(accuracyMeters: Double, distanceFilterMeters: Double, allowsBackground: Bool) {
            self.accuracyMeters = accuracyMeters
            self.distanceFilterMeters = distanceFilterMeters
            self.allowsBackground = allowsBackground
        }
    }

    /// `continuousHrvExplicit` does not keep a stream alive once the scene has left the foreground.
    /// The option only arms the flux while Nutry is open.
    public static func allows(
        _ activity: NutryBackgroundActivity,
        scene: NutryEnergyScene,
        trigger: NutryWakeTrigger = .none,
        heavyWorkPaused: Bool = false,
        continuousHrvExplicit: Bool = false,
        thermal: Thermal = .nominal
    ) -> Bool {
        _ = continuousHrvExplicit
        let foreground = scene == .active
        if activity == .historyOffload, thermal == .serious || thermal == .critical {
            return false
        }
        if heavyWorkPaused {
            switch activity {
            case .rescore, .refreshV5, .accountSync, .autoContinue:
                return false
            case .historyOffload:
                break
            default:
                break
            }
        }
        switch activity {
        case .historyOffload:
            return historyOffloadAllowed(foreground: foreground, trigger: trigger)
        case .rescore, .refreshV5, .accountSync, .autoContinue:
            return foreground
        case .keepAliveTimer, .standardHeartNotify, .realtimeStream, .silenceWatchdog, .liveRelay,
             .runTogetherPoll, .muscyPoll, .followedLivePoll, .presencePoll, .musicPoll:
            return foreground
        }
    }

    private static func historyOffloadAllowed(foreground: Bool, trigger: NutryWakeTrigger) -> Bool {
        switch trigger {
        case .manual, .foreground:
            return foreground
        case .backgroundRefresh, .backgroundProcessing, .strapEvent, .reconnection, .stateRestoration:
            return foreground == false
        case .none, .sceneBackground:
            return false
        }
    }

    /// Serious heat stops heavy work even with the app open. Low Power Mode
    /// restricts rescore and live streams once the scene has left the foreground.
    /// A short history offload stays allowed under Low Power: it is one bounded wake.
    public static func heavyWorkPaused(thermal: Thermal, lowPower: Bool, inForeground: Bool) -> Bool {
        if thermal == .serious || thermal == .critical { return true }
        return lowPower && inForeground == false
    }

    /// Background presence is a heartbeat for an outdoor recording that already
    /// keeps GPS awake. Muscy and an idle phone send nothing.
    public static let backgroundPresenceInterval: TimeInterval = 60
    public static let foregroundPresenceInterval: TimeInterval = 20

    public static func presenceHeartbeatAllowed(
        activity: String?,
        sceneActive: Bool,
        secondsSinceLast: TimeInterval,
        forced: Bool
    ) -> Bool {
        guard let activity else { return false }
        switch activity {
        case "coursy", "vely":
            if sceneActive { return forced || secondsSinceLast >= foregroundPresenceInterval }
            return secondsSinceLast >= backgroundPresenceInterval
        case "muscy":
            return sceneActive && (forced || secondsSinceLast >= foregroundPresenceInterval)
        default:
            return false
        }
    }

    public static func shouldResumeOpenSession(startedAt: Date?, now: Date, alreadyLive: Bool) -> Bool {
        if alreadyLive { return true }
        guard let startedAt else { return false }
        let age = now.timeIntervalSince(startedAt)
        return age >= 0 && age <= orphanSessionMaxAge
    }

    public static func presenceLocation(indoor: Bool) -> PresenceLocation {
        if indoor {
            return PresenceLocation(accuracyMeters: 100, distanceFilterMeters: 50, allowsBackground: false)
        }
        return PresenceLocation(accuracyMeters: 10, distanceFilterMeters: 15, allowsBackground: true)
    }

    public static func pausedRouteLocation() -> PresenceLocation {
        PresenceLocation(accuracyMeters: 100, distanceFilterMeters: 50, allowsBackground: true)
    }

    public static func liveActivityInterval(inBackground: Bool) -> TimeInterval {
        inBackground ? backgroundLiveActivityInterval : foregroundLiveActivityInterval
    }

    public static func reconnectDelay(afterFailures failures: Int) -> TimeInterval {
        let spent = max(1, failures)
        if spent > maxFastReconnectAttempts {
            return WhoopSyncDecision.backgroundInterval
        }
        let delay = reconnectBase * pow(2, Double(spent - 1))
        return min(delay, reconnectCap)
    }

    public static func backgroundSyncExpired(startedAt: TimeInterval, now: TimeInterval) -> Bool {
        now >= startedAt && now - startedAt >= backgroundSyncMaxDuration
    }

    public static func backgroundWakeLine(wallSeconds: TimeInterval, cpuSeconds: TimeInterval) -> String {
        let wall = Int(max(0, wallSeconds).rounded())
        let tenths = Int((max(0, cpuSeconds) * 10).rounded())
        let cpu = "\(tenths / 10).\(abs(tenths % 10))"
        return "Temps en arrière-plan : \(wall) s au mur, \(cpu) s de processeur"
    }
}

public enum WhoopBatteryPresentation {
    public static let staleness: TimeInterval = 24 * 60 * 60

    public static func percent(
        raw: Double?,
        readAt: TimeInterval?,
        now: TimeInterval,
        connected: Bool = true
    ) -> Double? {
        guard connected else { return nil }
        guard let raw, raw.isFinite, raw >= 0, raw <= 100 else { return nil }
        if let readAt {
            guard now >= readAt, now - readAt <= staleness else { return nil }
        }
        return raw
    }

    public static func showsBolt(charging: Bool?) -> Bool {
        charging == true
    }
}

/// Whether a live heart stream, its keepalive, or a realtime command may run.
/// Pure and `Sendable`: callers pass the scene flag and the characteristic id.
public enum WhoopLiveLinkPolicy: Sendable {
    /// 16-bit Heart Rate Measurement UUID, and the full Bluetooth base form.
    public static func isHeartRateCharacteristic(_ characteristic: String) -> Bool {
        let token = characteristic.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return token == "2A37" || token.hasPrefix("00002A37")
    }

    /// `false` only for 0x2A37 while live work is suspended. Other characteristics stay.
    public static func shouldSubscribeLiveHR(liveWorkSuspended: Bool, characteristic: String) -> Bool {
        if liveWorkSuspended && isHeartRateCharacteristic(characteristic) { return false }
        return true
    }

    public static func shouldArmKeepalive(liveWorkSuspended: Bool) -> Bool {
        liveWorkSuspended == false
    }

    public static func shouldRunRealtime(liveWorkSuspended: Bool) -> Bool {
        liveWorkSuspended == false
    }

    /// A heart sample arrived while the stream should be off. Record it, then unsubscribe.
    public static func shouldStopHeartNotifyAfterSample(liveWorkSuspended: Bool) -> Bool {
        liveWorkSuspended
    }
}

public enum WhoopBatteryRead {
    public enum Query: String, Sendable, Equatable {
        case getBatteryLevel
        case standardBatteryLevel
    }

    public static func shouldRequest(connected: Bool) -> Bool {
        connected
    }

    public static func query(isWhoop5: Bool) -> Query {
        isWhoop5 ? .standardBatteryLevel : .getBatteryLevel
    }
}

@MainActor
public enum WhoopEnergyRuntime {
    public static var heavyWorkPaused = false
    public static var thermal: WhoopEnergyBudget.Thermal = .nominal
    public static var sceneActive = true
    public static var blockBackgroundAnalysis = false

    /// Serious or critical heat defers a history offload. Low Power Mode does not.
    public static var defersHistoryOffload: Bool {
        thermal == .serious || thermal == .critical
    }

    public static func note(sceneActive: Bool, thermal: WhoopEnergyBudget.Thermal, lowPower: Bool) {
        self.sceneActive = sceneActive
        self.thermal = thermal
        heavyWorkPaused = WhoopEnergyBudget.heavyWorkPaused(
            thermal: thermal, lowPower: lowPower, inForeground: sceneActive)
    }

    public static func skipsHeavyMaintenance(isBackground: Bool) -> Bool {
        if isBackground {
            if heavyWorkPaused { return true }
            return blockBackgroundAnalysis
        }
        // Open app: Low Power Mode does not skip. Only serious or critical heat does.
        return heavyWorkPaused
    }
}
