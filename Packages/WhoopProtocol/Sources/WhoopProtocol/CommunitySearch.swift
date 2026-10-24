import Foundation

public struct CommunitySearchHit: Equatable, Sendable {
    public var id: String
    public var name: String
    public var username: String?

    public init(id: String, name: String, username: String?) {
        self.id = id
        self.name = name
        self.username = username
    }
}

public enum CommunitySearchOpen: Equatable, Sendable {
    case feed
    case list
    case person(String)

    /// Un seul résultat, ou un seul nom exactement égal à la recherche, ouvre la personne.
    /// Plusieurs résultats restent une liste. Une recherche vide revient au fil.
    public static func resolve(query: String, hits: [CommunitySearchHit]) -> CommunitySearchOpen {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .feed }
        if hits.isEmpty { return .list }
        if hits.count == 1, let only = hits.first { return .person(only.id) }
        let needle = folded(trimmed)
        let exact = hits.filter { hit in
            folded(hit.name) == needle || folded(hit.username ?? "") == needle
                || folded("@" + (hit.username ?? "")) == needle
        }
        if exact.count == 1, let match = exact.first { return .person(match.id) }
        return .list
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

public enum CommunityPersonPostsGate {
    /// Le serveur a déjà marqué le profil comme invisible. Le client n’affiche pas de publications.
    public static func hidesPosts(restricted: Bool) -> Bool {
        restricted
    }
}

extension CommunityFeedRequest {
    /// Route absente tant que le serveur ne l’expose pas : un 404 ne doit pas retomber sur le fil global.
    public static func profilePath(userId: String, types: String?) -> String {
        let base = "/api/v1/social?userId=\(encode(userId))"
        guard let types = CommunityPostsRoute.typesParameter(types) else { return base }
        return "\(base)&types=\(encode(types))"
    }

    public static func userPostsPath(userId: String, types: String?, cursor: String?, limit: Int) -> String {
        var items = ["limit=\(CommunityPostsRoute.clampedLimit(limit))"]
        if let types = CommunityPostsRoute.typesParameter(types) {
            items.append("types=\(encode(types))")
        }
        if let cursor, cursor.isEmpty == false {
            items.append("cursor=\(encodeCursor(cursor))")
        }
        let query = items.joined(separator: "&")
        return "/api/v1/community/users/\(encode(userId))/posts?\(query)"
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    /// Curseur : uniquement alphanumériques et `-._~`. `.urlQueryAllowed` laisse passer `/`, `?`, `&`.
    private static func encodeCursor(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum CommunityPersonOutcome: Equatable, Sendable {
    case loaded
    case missingProfile
    case unavailable
    case cancelled
}

public enum CommunityPersonLoad {
    public static let missingMessage = "Profil introuvable"
    public static let unavailableMessage = "Le profil n’a pas pu être chargé."

    /// Un 404 JSON du profil (`profileNotFound`) n’est pas une route HTML absente.
    public static func outcome(cancelled: Bool, profileNotFound: Bool) -> CommunityPersonOutcome {
        if cancelled { return .cancelled }
        if profileNotFound { return .missingProfile }
        return .unavailable
    }

    public static func message(for outcome: CommunityPersonOutcome) -> String? {
        switch outcome {
        case .loaded, .cancelled:
            return nil
        case .missingProfile:
            return missingMessage
        case .unavailable:
            return unavailableMessage
        }
    }
}

public enum CommunityPersonPage {
    /// Un 404 HTML sur « Voir plus » cache le bouton et garde les publications déjà affichées.
    public static func keepPostsAfterMissingRoute(appending: Bool, undeployed: Bool) -> Bool {
        appending && undeployed
    }

    public static func mergeIDs(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set(existing)
        var result = existing
        for id in incoming where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}

public enum CommunitySearchApply {
    /// Le choix (fil, liste, personne) ne s’applique qu’après une recherche réussie.
    public static func shouldApply(searchSucceeded: Bool) -> Bool {
        searchSucceeded
    }
}

public enum CommunitySearchSessionReset {
    public struct State: Equatable, Sendable {
        public var query: String
        public var pickedUserId: String?
        public var users: [String]
        public var sessions: [String]
        public var personCleared: Bool

        public init(query: String, pickedUserId: String?, users: [String], sessions: [String], personCleared: Bool) {
            self.query = query
            self.pickedUserId = pickedUserId
            self.users = users
            self.sessions = sessions
            self.personCleared = personCleared
        }
    }

    /// Fermer la loupe revient au fil : texte vide, personne oubliée, listes vides.
    public static func closed() -> State {
        State(query: "", pickedUserId: nil, users: [], sessions: [], personCleared: true)
    }
}
