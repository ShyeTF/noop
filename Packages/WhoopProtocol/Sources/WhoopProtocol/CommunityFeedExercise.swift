import Foundation

/// Volume et nom d’un exercice, alignés sur le fil (`SQL_DUMBBELL_LOAD_FACTOR` et le CASE du chronomètre).
public enum CommunitySetLoad {
    /// 2 si l’équipement contient « Haltère », « haltère » ou « dumbbell », sinon 1.
    public static func multiplier(equipment: String?) -> Double {
        let value = equipment ?? ""
        if value.contains("Haltère") || value.contains("haltère") { return 2 }
        if value.lowercased().contains("dumbbell") { return 2 }
        return 1
    }

    /// Séries terminées seulement. Le poids stocké d’une haltère est celui d’un côté.
    public static func volume(weight: Double, reps: Int, equipment: String?, completed: Bool) -> Double {
        guard completed else { return 0 }
        return weight * Double(reps) * multiplier(equipment: equipment)
    }
}

public enum CommunityFeedExercise {
    public static let stopwatchID = "nutry-free-stopwatch"

    /// Chronomètre libre : le nom affiché est la note, dès qu’elle n’est pas vide.
    public static func displayName(exerciseID: String, catalogName: String, notes: String?) -> String {
        if exerciseID == stopwatchID, let notes, notes.isEmpty == false { return notes }
        return catalogName
    }

    /// Durée d’une série terminée. Une durée absente compte 0, une série non faite aussi.
    public static func durationSeconds(completed: Bool, duration: Int?) -> Int {
        guard completed else { return 0 }
        return duration ?? 0
    }
}

public enum CommunityPersonPagePlan {
    /// « Voir plus » seulement quand la route a renvoyé un curseur non vide.
    public static func showsMore(nextCursor: String?) -> Bool {
        guard let nextCursor, nextCursor.isEmpty == false else { return false }
        return true
    }

    /// Le mapping `?userId=` ne remplace la première page que si la route posts répond en HTML 404.
    public static func keepsMappedPosts(fault: CommunityPostsFault) -> Bool {
        fault == .routeNotDeployed
    }

    /// Ce repli a déjà toute la liste locale : pas de page suivante.
    public static let fallbackShowsMore = false
}

public enum CommunityPersonReload {
    public static func reloadsPerson(pickedUserId: String?) -> Bool {
        guard let pickedUserId else { return false }
        return pickedUserId.isEmpty == false
    }

    /// Changer le filtre pendant qu’une personne est ouverte repart de la page 1.
    public static func cursorAfterFilterChange(personOpen: Bool, previousCursor: String?) -> String? {
        personOpen ? nil : previousCursor
    }
}
