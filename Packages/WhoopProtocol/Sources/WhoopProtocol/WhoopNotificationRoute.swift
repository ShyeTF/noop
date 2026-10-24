import Foundation

/// Where a local notification tap should land. Missing keys never trap.
public enum WhoopNotificationDestination: Equatable, Sendable {
    /// Bracelet home, once the account stack exists.
    case whoopHome
    /// Existing iOS update sheet. Not a WHOOP screen.
    case iosUpdate
    /// Bring the app forward and do nothing else.
    case appOnly
}

/// One activation of the scene. A cold start fires launch and then `.active`.
public struct WhoopForegroundAdmission: Equatable, Sendable {
    public var open: Bool
    public var startsForegroundWork: Bool
    public var generation: Int

    public init(open: Bool, startsForegroundWork: Bool, generation: Int) {
        self.open = open
        self.startsForegroundWork = startsForegroundWork
        self.generation = generation
    }
}

/// In memory only. A second open in the same visit does not start another rescore.
public struct WhoopForegroundActivation: Equatable, Sendable {
    public private(set) var generation: Int
    private var armed: Bool

    public init() {
        generation = 0
        armed = false
    }

    public mutating func admit(open: Bool) -> WhoopForegroundAdmission {
        if open == false {
            armed = false
            return WhoopForegroundAdmission(open: false, startsForegroundWork: false, generation: generation)
        }
        if armed {
            return WhoopForegroundAdmission(open: true, startsForegroundWork: false, generation: generation)
        }
        armed = true
        generation += 1
        return WhoopForegroundAdmission(open: true, startsForegroundWork: true, generation: generation)
    }

    public mutating func noteLeftForeground() {
        armed = false
    }
}

/// Heavy scoring waits until a frame has been committed and no pass is already in flight.
public enum WhoopRescoreSchedule {
    public static func shouldStart(afterFirstFrame: Bool, alreadyRunning: Bool) -> Bool {
        afterFirstFrame && alreadyRunning == false
    }
}

public enum WhoopNotificationRoute {
    public static let whoopHomeRoute = "whoop"
    public static let iosUpdateAction = "open-ios-update"

    /// Identifiers posted by the strap battery alerts. A build that already
    /// delivered one has no `userInfo`; the identifier is enough.
    public static let batteryIdentifiers: Set<String> = [
        "battery-full",
        "battery-low",
        "battery-runtime",
        "battery-critical",
        "battery-bedtime",
        "battery-stale",
    ]

    public static func destination(
        identifier: String,
        categoryIdentifier: String,
        action: String?,
        route: String?
    ) -> WhoopNotificationDestination {
        let actionText = nonempty(action)
        let routeText = nonempty(route)
        if actionText == iosUpdateAction {
            return .iosUpdate
        }
        if routeText == whoopHomeRoute || batteryIdentifiers.contains(identifier) {
            return .whoopHome
        }
        _ = categoryIdentifier
        return .appOnly
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Holds at most one tap until the tab shell exists, then returns it once.
public struct WhoopPendingRouteQueue: Equatable, Sendable {
    private var pending: WhoopNotificationDestination?
    private var ready: Bool

    public init() {
        pending = nil
        ready = false
    }

    /// Nil while the router is not up yet. `.appOnly` is never stored.
    public mutating func receive(_ destination: WhoopNotificationDestination) -> WhoopNotificationDestination? {
        switch destination {
        case .appOnly:
            return nil
        case .whoopHome, .iosUpdate:
            break
        }
        if ready {
            return destination
        }
        pending = destination
        return nil
    }

    public mutating func routerDidBecomeReady() -> WhoopNotificationDestination? {
        ready = true
        let next = pending
        pending = nil
        return next
    }
}
