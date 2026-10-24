import Foundation

/// Référence d’affichage des pas d’une journée. Ce n’est pas un objectif enregistré.
public enum StepScale {
    public static let dailyReference: Int = 10_000

    /// Anneau : 1 correspond à la référence. Au-delà, l’appelant peut rester à 1,
    /// comme les autres jauges déjà plafonnées, sans changer le nombre affiché.
    public static func ratio(steps: Int) -> Double {
        guard dailyReference > 0 else { return 0 }
        return Double(steps) / Double(dailyReference)
    }
}
