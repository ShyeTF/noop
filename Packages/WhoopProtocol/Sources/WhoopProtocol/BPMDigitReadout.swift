import Foundation

/// Chiffres d’une fréquence en direct. Le passage vers ou depuis l’absence de mesure ne s’anime pas.
public enum BPMDigitReadout {
    public static let placeholder = "—"
    /// Même durée que le chiffre BPM toujours visible de l’app de référence.
    public static let easeOutSeconds: Double = 0.25

    public static func shown(_ value: Int?) -> String {
        guard let value else { return placeholder }
        return String(value)
    }

    public static func shown(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(Int(value.rounded()))
    }

    public static func line(_ value: Int?, suffix: String) -> String {
        guard let value else { return placeholder }
        return String(value) + suffix
    }

    /// Vrai seulement d’un nombre à un autre nombre. Nil ne doit pas compter depuis zéro.
    public static func animates(from previous: Int?, to next: Int?) -> Bool {
        guard let previous, let next else { return false }
        return previous != next
    }
}
