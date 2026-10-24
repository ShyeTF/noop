import Foundation

public enum CommunityPostKind: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
    case meal
    case barcode
    case muscy
    case coursy
    case vely
}

/// Ensemble vide = tout afficher. Inconnu ou illisible = tout afficher.
public struct CommunityFeedSelection: Equatable, Sendable {
    public var kinds: Set<CommunityPostKind>

    public init(kinds: Set<CommunityPostKind> = []) {
        self.kinds = kinds
    }

    public var showsEverything: Bool {
        kinds.isEmpty || kinds.count == CommunityPostKind.allCases.count
    }

    public func includes(_ kind: CommunityPostKind) -> Bool {
        showsEverything || kinds.contains(kind)
    }

    public func toggling(_ kind: CommunityPostKind) -> CommunityFeedSelection {
        if showsEverything {
            return CommunityFeedSelection(kinds: [kind])
        }
        var next = kinds
        if next.contains(kind) {
            next.remove(kind)
        } else {
            next.insert(kind)
        }
        if next.isEmpty || next.count == CommunityPostKind.allCases.count {
            return CommunityFeedSelection()
        }
        return CommunityFeedSelection(kinds: next)
    }

    public var stored: String {
        if showsEverything { return "" }
        return CommunityPostKind.allCases.filter { kinds.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// Nil pour rester compatible avec un serveur qui ne connaît pas le paramètre.
    public var typesQuery: String? {
        let value = stored
        return value.isEmpty ? nil : value
    }

    public static func decode(_ raw: String?) -> CommunityFeedSelection {
        guard let raw else { return CommunityFeedSelection() }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return CommunityFeedSelection() }
        let tokens: [String]
        if trimmed.hasPrefix("[") {
            guard let data = trimmed.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return CommunityFeedSelection()
            }
            tokens = decoded
        } else {
            tokens = trimmed.split(separator: ",").map { String($0) }
        }
        var kinds = Set<CommunityPostKind>()
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let kind = CommunityPostKind(rawValue: cleaned) else {
                return CommunityFeedSelection()
            }
            kinds.insert(kind)
        }
        if kinds.isEmpty || kinds.count == CommunityPostKind.allCases.count {
            return CommunityFeedSelection()
        }
        return CommunityFeedSelection(kinds: kinds)
    }
}

public enum CommunityFeedRequest {
    public static func socialPath(types: String?) -> String {
        guard let types = CommunityPostsRoute.typesParameter(types) else { return "/api/v1/social" }
        let encoded = types.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? types
        return "/api/v1/social?types=\(encoded)"
    }
}
