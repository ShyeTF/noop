import Foundation

public enum LiveChargeKind: Equatable, Sendable {
    case on
    case off
    /// Raw charging byte before the decoder masks it. Nil when the frame has no such byte.
    /// Values above 1 are kept here and are not turned into a charging flag.
    case battery(rawByte: Int?)
}

public struct LiveChargeEffect: Equatable, Sendable {
    public var apply: Bool
    public var charging: Bool?
    /// Cursor after this event. Moves forward only.
    public var cursor: Int

    public init(apply: Bool, charging: Bool?, cursor: Int) {
        self.apply = apply
        self.charging = charging
        self.cursor = cursor
    }
}

public struct LiveEventNote: Equatable, Sendable {
    public var event: Int
    public var chargeRaw: Int?

    public init(event: Int, chargeRaw: Int?) {
        self.event = event
        self.chargeRaw = chargeRaw
    }
}

/// Pure charging dispatch shared by the live EVENT path and the fresh-offload rescue.
/// The 45 s window and the older-than-last rejection apply only while an offload is running.
/// A live edge always applies, so a strap with a stale RTC cannot block the wrist.
public enum LiveChargeDispatch {
    public static let freshWindowSeconds = 45
    public static let loggedEvents: Set<Int> = [3, 7, 8, 21, 22, 109]

    public static func effect(
        kind: LiveChargeKind,
        eventTimestamp: Int?,
        now: Int,
        duringOffload: Bool,
        lastAppliedTimestamp: Int
    ) -> LiveChargeEffect {
        let ts = eventTimestamp ?? 0
        if duringOffload {
            if ts <= 0 || abs(now - ts) > freshWindowSeconds || ts < lastAppliedTimestamp {
                return LiveChargeEffect(apply: false, charging: nil, cursor: lastAppliedTimestamp)
            }
        }
        let cursor = ts > lastAppliedTimestamp ? ts : lastAppliedTimestamp
        return LiveChargeEffect(apply: true, charging: charging(kind), cursor: cursor)
    }

    public static func charging(_ kind: LiveChargeKind) -> Bool? {
        switch kind {
        case .on:
            return true
        case .off:
            return false
        case .battery(let raw):
            guard let raw, raw <= 1 else { return nil }
            return (raw & 1) != 0
        }
    }

    /// Event number from `"BATTERY_LEVEL(3)"` or `"0x6D(109)"`.
    public static func eventNumber(in name: String) -> Int? {
        guard let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else {
            return nil
        }
        return Int(name[name.index(after: open)..<close])
    }

    /// Raw event byte, and for `BATTERY_LEVEL` the charging byte before `ch <= 1` drops it.
    /// 5.0/MG: event @10, charge @30. 4.0: event @6, charge @26.
    public static func note(frame: [UInt8], whoop5: Bool) -> LiveEventNote? {
        let eventOff = whoop5 ? 10 : 6
        guard frame.count > eventOff else { return nil }
        let event = Int(frame[eventOff])
        guard loggedEvents.contains(event) else { return nil }
        let chargeOff = whoop5 ? 30 : 26
        let chargeRaw: Int? = event == 3 && frame.count > chargeOff ? Int(frame[chargeOff]) : nil
        return LiveEventNote(event: event, chargeRaw: chargeRaw)
    }
}

public struct ChargeLogSlot: Equatable, Sendable {
    public var lastAt: TimeInterval
    public var lastValue: Int?

    public init(lastAt: TimeInterval, lastValue: Int?) {
        self.lastAt = lastAt
        self.lastValue = lastValue
    }
}

/// Strap-log gate for events 3, 7, 8, 21, 22 and 109. One line per event at most every 10 s,
/// and a new line as soon as the logged value changes. No capture switch.
public enum ChargeLogGate {
    public static let minimumInterval: TimeInterval = 10

    public static func shouldWrite(value: Int?, now: TimeInterval, slot: ChargeLogSlot?) -> Bool {
        guard let slot else { return true }
        if slot.lastValue != value { return true }
        return now - slot.lastAt >= minimumInterval
    }
}

public enum LiveEventRoute: Equatable, Sendable {
    case doubleTap
    case wristOn
    case wristOff
    case chargingOn
    case chargingOff
    case batteryLevel
    case packInfo
    case other
}

/// Pure EVENT name → action. `FrameRouter` calls this for the live path and the offload rescue.
public enum LiveEventDispatch {
    public static func route(_ eventName: String) -> LiveEventRoute {
        if eventName.hasPrefix("DOUBLE_TAP") { return .doubleTap }
        if eventName.hasPrefix("WRIST_ON") { return .wristOn }
        if eventName.hasPrefix("WRIST_OFF") { return .wristOff }
        if eventName.hasPrefix("CHARGING_ON") || eventName.hasPrefix("BATTERY_PACK_CONNECTED") {
            return .chargingOn
        }
        if eventName.hasPrefix("CHARGING_OFF") || eventName.hasPrefix("BATTERY_PACK_REMOVED") {
            return .chargingOff
        }
        if eventName.hasPrefix("BATTERY_LEVEL") { return .batteryLevel }
        if LiveChargeDispatch.eventNumber(in: eventName) == BatteryPackInfo.packInfoEvent {
            return .packInfo
        }
        return .other
    }
}
