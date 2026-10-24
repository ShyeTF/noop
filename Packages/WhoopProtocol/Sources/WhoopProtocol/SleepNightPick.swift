import Foundation

/// Une nuit déjà enregistrée. L’index 0 est la plus récente.
public struct SleepNightStamp: Equatable, Sendable {
    public var index: Int
    public var dayKey: String

    public init(index: Int, dayKey: String) {
        self.index = index
        self.dayKey = dayKey
    }
}

public enum SleepNightPick {
    public static let latestOffset = 0

    /// Première nuit (la plus récente) dont la fin tombe ce jour. Nil s’il n’y en a pas.
    public static func index(dayKey: String, nights: [SleepNightStamp]) -> Int? {
        nights.first { $0.dayKey == dayKey }?.index
    }

    /// Une nuit déjà enregistrée s’ouvre, même entre 00:00 et 04:00.
    /// `todayKey` reste pour les appelants : seul le jour qui a une nuit compte.
    public static func isSelectable(dayKey: String, todayKey: String, nightKeys: Set<String>) -> Bool {
        nightKeys.contains(dayKey)
    }
}
