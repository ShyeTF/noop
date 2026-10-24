import XCTest

@testable import WhoopProtocol

/// Jumeau des tests Node `tests/workout-totals-233.test.mjs` : les deux côtés
/// doivent tomber sur le même chiffre pour la séance du 11 octobre.
final class MuscyWorkoutTotalsTests: XCTestCase {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)!
    }

    func testVolumeAppliesDumbbellFactorOnCompletedSetsOnly() {
        let sets = [
            // Poulie : pas de facteur. 41 × 10 × 4 = 1640 kg.
            MuscyWorkoutTotals.SetEntry(weight: 41, reps: 10, completed: true, equipment: "Poulie"),
            MuscyWorkoutTotals.SetEntry(weight: 41, reps: 10, completed: true, equipment: "Poulie"),
            MuscyWorkoutTotals.SetEntry(weight: 41, reps: 10, completed: true, equipment: "Poulie"),
            MuscyWorkoutTotals.SetEntry(weight: 41, reps: 10, completed: true, equipment: "Poulie"),
            // Haltères : le poids saisi est celui d’un côté. 24 × 10 × 4 × 2 = 1920 kg.
            MuscyWorkoutTotals.SetEntry(weight: 24, reps: 10, completed: true, equipment: "Haltères"),
            MuscyWorkoutTotals.SetEntry(weight: 24, reps: 10, completed: true, equipment: "Haltères"),
            MuscyWorkoutTotals.SetEntry(weight: 24, reps: 10, completed: true, equipment: "Haltères"),
            MuscyWorkoutTotals.SetEntry(weight: 24, reps: 10, completed: true, equipment: "Haltères"),
            // Non validée : elle ne compte nulle part.
            MuscyWorkoutTotals.SetEntry(weight: 100, reps: 10, completed: false, equipment: "Poulie"),
        ]
        XCTAssertEqual(MuscyWorkoutTotals.volumeKilograms(sets: sets), 3560)
        XCTAssertEqual(MuscyWorkoutTotals.completedSetCount(sets: sets), 8)
    }

    func testPlausibleDurationIsKeptAsIs() {
        // La séance du 11 octobre : 1 h 39 min 05 s, pauses comprises.
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: date("2026-10-11T14:10:20.541Z"),
                endedAt: date("2026-10-11T15:49:26.039Z"),
                storedSeconds: 5945,
                lastSetCompletedAt: date("2026-10-11T15:46:48.673Z")),
            5945)
        // Sans durée enregistrée, c’est fin − début.
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: date("2026-10-11T14:10:20.541Z"),
                endedAt: date("2026-10-11T15:49:26.039Z"),
                storedSeconds: 0,
                lastSetCompletedAt: nil),
            5945)
    }

    func testOpenSessionFallsBackToLastCompletedSet() {
        // « Legs » laissée ouverte toute la nuit : 1078 min affichées en prod.
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: date("2026-10-10T20:06:11.209Z"),
                endedAt: date("2026-10-11T14:04:52.351Z"),
                storedSeconds: 64721,
                lastSetCompletedAt: date("2026-10-10T20:56:23.814Z")),
            3013 + MuscyWorkoutTotals.trailingMarginSeconds)
    }

    func testAbsurdDurationWithoutUsableSetIsCapped() {
        // Import rétroactif : toutes les séries portent l’horodatage de fin.
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: date("2026-08-24T19:17:02.039Z"),
                endedAt: date("2026-08-26T19:59:42.283Z"),
                storedSeconds: 175_360,
                lastSetCompletedAt: date("2026-08-26T19:59:42.283Z")),
            MuscyWorkoutTotals.durationCapSeconds)
        // Aucune série du tout : même plafond, jamais la valeur absurde.
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: date("2026-08-24T19:17:02.039Z"),
                endedAt: nil,
                storedSeconds: 175_360,
                lastSetCompletedAt: nil),
            MuscyWorkoutTotals.durationCapSeconds)
    }

    func testMissingDatesGiveZeroRatherThanGarbage() {
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: nil, endedAt: nil, storedSeconds: nil, lastSetCompletedAt: nil),
            0)
        XCTAssertEqual(
            MuscyWorkoutTotals.durationSeconds(
                startedAt: date("2026-10-11T14:10:20Z"), endedAt: nil,
                storedSeconds: 1800, lastSetCompletedAt: nil),
            1800,
            "une séance encore ouverte garde sa durée courante")
    }

    func testLastCompletedAtIgnoresUnfinishedSets() {
        let sets = [
            MuscyWorkoutTotals.SetEntry(
                weight: 60, reps: 10, completed: true, equipment: "Barre",
                completedAt: date("2026-10-11T14:20:00Z")),
            MuscyWorkoutTotals.SetEntry(
                weight: 60, reps: 10, completed: false, equipment: "Barre",
                completedAt: date("2026-10-11T18:00:00Z")),
        ]
        XCTAssertEqual(
            MuscyWorkoutTotals.lastCompletedAt(sets: sets), date("2026-10-11T14:20:00Z"))
    }
}
