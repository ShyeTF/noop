import Foundation

/// Pure helpers for the strap firmware alarm: next fire instant and honest UI status.
/// Shared by Nutry's Alarme screen and the Linux encoding tests — no BLE, no UIKit.
public enum SmartAlarmSchedule {
    /// Next strictly-future fire for `minutes` (local minutes since midnight) on the selected
    /// Calendar weekdays (1 = Sun … 7 = Sat). Empty `weekdays` = every day. Nil when no valid day
    /// falls in the next week (only a corrupted out-of-range set).
    public static func nextFireDate(
        minutes: Int,
        weekdays: Set<Int>,
        from now: Date = Date(),
        calendar cal: Calendar = .current
    ) -> Date? {
        let valid = weekdays.filter { (1...7).contains($0) }
        if !weekdays.isEmpty && valid.isEmpty { return nil }
        let wakeMin = min(max(minutes, 0), (24 * 60) - 1)
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let dow = cal.component(.weekday, from: day)
            if !weekdays.isEmpty && !valid.contains(dow) { continue }
            let hour = wakeMin / 60
            let minute = wakeMin % 60
            guard let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if fire <= now { continue }
            return fire
        }
        return nil
    }

    /// French status line for the Nutry Alarme screen (vouvoiement). Nil when the alarm is off.
    public static func statusNote(
        enabled: Bool,
        bonded: Bool,
        lastArmReachedStrap: Bool?,
        whoop5: Bool,
        rejectStreak: Int
    ) -> String? {
        guard enabled else { return nil }
        if rejectStreak >= 2 {
            return "Le WHOOP n’a pas confirmé l’heure enregistrée. Réessayez en le gardant à proximité, et gardez une alarme de secours."
        }
        if !bonded {
            return "Alarme enregistrée. Elle sera envoyée au WHOOP dès qu’il sera relié."
        }
        if lastArmReachedStrap == false {
            return "Alarme non encore confirmée sur le WHOOP. Rapprochez le bracelet et laissez Nutry ouvert un instant."
        }
        if whoop5 {
            return "Alarme envoyée au WHOOP. Sur un modèle récent, le réveil haptique reste expérimental. Une notification de secours est aussi prévue sur l’iPhone."
        }
        return "Alarme active sur le WHOOP relié. Une notification de secours est aussi prévue sur l’iPhone."
    }
}
