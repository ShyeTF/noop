import Foundation

/// Totaux d’une séance Muscu : volume, séries, durée.
///
/// Jumeau Swift de `lib/workout-totals.ts`. Le fil Communauté, la fiche détail,
/// le profil et les statistiques affichaient trois totaux différents pour la
/// même séance parce que chacun recalculait à sa façon. Tout passe désormais
/// par ce type, et seulement par lui.
public enum MuscyWorkoutTotals {
    /// Au-delà, la séance est forcément restée ouverte : on ne montre jamais plus.
    public static let durationCapSeconds: Int = 4 * 3600

    /// Récupération comptée après la dernière série validée d’une séance oubliée.
    public static let trailingMarginSeconds: Int = 180

    /// Une série telle que la voit l’app, quel que soit l’écran d’origine.
    public struct SetEntry: Sendable {
        public let weight: Double
        public let reps: Int
        public let completed: Bool
        /// Équipement du mouvement, pour le facteur haltères.
        public let equipment: String?
        /// `completed_at`, quand le serveur l’a renvoyé.
        public let completedAt: Date?

        public init(
            weight: Double, reps: Int, completed: Bool,
            equipment: String?, completedAt: Date? = nil
        ) {
            self.weight = weight
            self.reps = reps
            self.completed = completed
            self.equipment = equipment
            self.completedAt = completedAt
        }
    }

    /// Volume d’une série validée, facteur haltères compris. Zéro sinon.
    public static func volume(of set: SetEntry) -> Double {
        CommunitySetLoad.volume(
            weight: set.weight, reps: set.reps,
            equipment: set.equipment, completed: set.completed)
    }

    /// Volume total des séries validées, en kilogrammes.
    public static func volumeKilograms(sets: [SetEntry]) -> Double {
        sets.reduce(0) { $0 + volume(of: $1) }
    }

    /// Nombre de séries validées.
    public static func completedSetCount(sets: [SetEntry]) -> Int {
        sets.reduce(0) { $0 + ($1.completed ? 1 : 0) }
    }

    /// Dernière série validée, pour le repli de durée.
    public static func lastCompletedAt(sets: [SetEntry]) -> Date? {
        sets.compactMap { $0.completed ? $0.completedAt : nil }.max()
    }

    /// Durée affichée d’une séance, en secondes.
    ///
    /// La durée réelle (fin − début, ou celle enregistrée) est gardée telle
    /// quelle tant qu’elle reste plausible : une séance de 1 h 39 reste
    /// 1 h 39, pauses comprises. Au-delà du plafond, la séance est restée
    /// ouverte : on repart de la dernière série validée plus une marge de
    /// récupération, puis on replafonne. Sans série exploitable, on affiche
    /// le plafond plutôt qu’une valeur absurde.
    public static func durationSeconds(
        startedAt: Date?,
        endedAt: Date?,
        storedSeconds: Int?,
        lastSetCompletedAt: Date?
    ) -> Int {
        let stored = max(0, storedSeconds ?? 0)
        let wall: Int
        if stored > 0 {
            wall = stored
        } else if let startedAt, let endedAt {
            wall = max(0, Int(endedAt.timeIntervalSince(startedAt).rounded()))
        } else {
            wall = 0
        }
        if wall <= durationCapSeconds { return wall }

        // Une dernière série qui tombe pile à la fin ne dit rien de l’activité
        // réelle (import rétroactif) : seul un horodatage antérieur est un signal.
        guard let startedAt, let lastSetCompletedAt, lastSetCompletedAt > startedAt else {
            return durationCapSeconds
        }
        if let endedAt, lastSetCompletedAt >= endedAt { return durationCapSeconds }
        let active = Int(lastSetCompletedAt.timeIntervalSince(startedAt).rounded())
            + trailingMarginSeconds
        return min(max(active, 0), durationCapSeconds)
    }

    /// Durée affichée à partir des séries déjà chargées.
    public static func durationSeconds(
        startedAt: Date?, endedAt: Date?, storedSeconds: Int?, sets: [SetEntry]
    ) -> Int {
        durationSeconds(
            startedAt: startedAt, endedAt: endedAt, storedSeconds: storedSeconds,
            lastSetCompletedAt: lastCompletedAt(sets: sets))
    }
}
