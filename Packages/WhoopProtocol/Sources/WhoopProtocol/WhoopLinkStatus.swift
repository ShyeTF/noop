import Foundation

/// CoreBluetooth central state, raw values of `CBManagerState`.
public enum WhoopRadioState: Int, Equatable, Sendable {
    case unknown = 0
    case resetting = 1
    case unsupported = 2
    case unauthorized = 3
    case poweredOff = 4
    case poweredOn = 5

    public init(raw: Int) {
        self = WhoopRadioState(rawValue: raw) ?? .unknown
    }
}

public struct WhoopLinkFacts: Equatable, Sendable {
    public var radio: WhoopRadioState
    public var paired: Bool
    public var connected: Bool
    public var connecting: Bool
    public var syncing: Bool
    public var foreground: Bool
    public var livePacketAtMs: Double?
    public var nowMs: Double

    public init(
        radio: WhoopRadioState,
        paired: Bool,
        connected: Bool,
        connecting: Bool,
        syncing: Bool,
        foreground: Bool,
        livePacketAtMs: Double?,
        nowMs: Double
    ) {
        self.radio = radio
        self.paired = paired
        self.connected = connected
        self.connecting = connecting
        self.syncing = syncing
        self.foreground = foreground
        self.livePacketAtMs = livePacketAtMs
        self.nowMs = nowMs
    }
}

public enum WhoopLinkStatus: Equatable, Sendable {
    case bluetoothOff
    case bluetoothUnauthorized
    case noWatch
    case offline
    case connecting
    case syncing
    case live
}

public enum WhoopLinkStatusEngine {
    /// A live frame older than this is no longer « En direct ».
    public static let liveFreshMs: Double = 15_000

    /// First match wins:
    /// 1. Bluetooth off, unsupported, or unauthorized.
    /// 2. No paired strap (and no connection in progress).
    /// 3. Settled disconnect.
    /// 4. Connection in progress, even if a stale frame is still around.
    /// 5. History sync actually running. A foreground backfill shows syncing,
    ///    not live, even when packets are fresh.
    /// 6. Foreground, connected, and a live frame no older than `liveFreshMs`.
    /// 7. Offline: stale packets, or the app is not in the foreground.
    public static func resolve(_ facts: WhoopLinkFacts) -> WhoopLinkStatus {
        switch facts.radio {
        case .poweredOff, .unsupported:
            return .bluetoothOff
        case .unauthorized:
            return .bluetoothUnauthorized
        case .unknown, .resetting, .poweredOn:
            break
        }
        let up = facts.connected
        let linking = facts.connecting
        if !facts.paired && !linking && !up {
            return .noWatch
        }
        if !up && !linking {
            return .offline
        }
        if linking {
            return .connecting
        }
        if facts.syncing && up {
            return .syncing
        }
        if facts.foreground && up && fresh(facts) {
            return .live
        }
        return .offline
    }

    private static func fresh(_ facts: WhoopLinkFacts) -> Bool {
        guard let at = facts.livePacketAtMs, at.isFinite, facts.nowMs.isFinite else { return false }
        let age = facts.nowMs - at
        return age >= 0 && age <= liveFreshMs
    }
}

/// Newest live stamp, in milliseconds. Custom frames, readable heart-rate samples and any
/// standard heart-rate notification (readable or not) are one clock.
public enum WhoopLinkClock {
    public static func latestMs(frameUnix: Int?, heartUnix: Int?, linkUnix: Int? = nil) -> Double? {
        var best: Int?
        for stamp in [frameUnix, heartUnix, linkUnix] {
            guard let stamp, stamp > 0 else { continue }
            if let current = best {
                if stamp > current { best = stamp }
            } else {
                best = stamp
            }
        }
        guard let best else { return nil }
        return Double(best) * 1000
    }
}
