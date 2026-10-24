import Foundation

public enum CommunityPostsFault: Equatable, Sendable {
    case missingProfile
    case routeNotDeployed
    case invalidCursor
    case unknownType
    case other
}

public enum CommunityPostsRoute {
    public static let defaultLimit = 30
    public static let maxLimit = 50
    /// Sous les publications déjà affichées. Pas une alerte.
    public static let cursorNotice = "Les publications plus anciennes ne sont pas disponibles."

    /// Défaut 30, plafond 50. Une valeur absente ou illisible retombe sur 30.
    public static func clampedLimit(_ value: Int) -> Int {
        guard value >= 1 else { return defaultLimit }
        return min(value, maxLimit)
    }

    /// Jetons connus seulement. Vide, inconnu ou les cinq ensemble : on omet `types` (Tout).
    public static func typesParameter(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let known = Set(CommunityPostKind.allCases.map(\.rawValue))
        var kept: [String] = []
        for token in raw.split(separator: ",") {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard known.contains(cleaned), kept.contains(cleaned) == false else { continue }
            kept.append(cleaned)
        }
        if kept.isEmpty || kept.count == CommunityPostKind.allCases.count { return nil }
        let order = CommunityPostKind.allCases.map(\.rawValue)
        return order.filter { kept.contains($0) }.joined(separator: ",")
    }

    /// `json == false` sur un 404 : HTML ou corps non JSON, la route n’est pas déployée.
    /// Un 404 JSON « Profil introuvable. » n’est pas ce cas.
    public static func fault(httpStatus: Int, json: Bool, message: String) -> CommunityPostsFault {
        let folded = message
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if httpStatus == 404 {
            if json == false { return .routeNotDeployed }
            if folded.contains("profil introuvable") { return .missingProfile }
            return .other
        }
        if httpStatus == 400 {
            if folded.contains("curseur invalide") { return .invalidCursor }
            if folded.contains("type de publication inconnu") { return .unknownType }
        }
        return .other
    }

    /// HTML 404 ou curseur refusé : on cache « Voir plus » et on ne relance pas.
    public static func hidesMore(_ fault: CommunityPostsFault) -> Bool {
        switch fault {
        case .routeNotDeployed, .invalidCursor, .unknownType:
            return true
        case .missingProfile, .other:
            return false
        }
    }
}

/// Les sept clés de `GET /api/v1/community/users/:userId/posts`. `nextCursor` est null en dernière page.
public struct CommunityPostsPage: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable {
        public var id: String
    }

    public var meals: [Item]
    public var barcodes: [Item]
    public var feed: [Item]
    public var runs: [Item]
    public var rides: [Item]
    public var nextCursor: String?
    public var restricted: Bool

    public static func decode(_ data: Data) throws -> CommunityPostsPage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CommunityPostsPage.self, from: data)
    }
}
