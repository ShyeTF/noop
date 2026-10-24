import Foundation

/// Le message « Commentaire non publié » ne sort que d’un envoi vraiment raté.
public enum CommunityErrorRouting {
    public static let commentMessage = "Le commentaire n’a pas pu être publié."
    public static let searchMessage = "La recherche n’a pas abouti."

    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    public static func commentAlert(cancelled: Bool, failed: Bool) -> String? {
        guard cancelled == false, failed else { return nil }
        return commentMessage
    }

    public static func searchNotice(cancelled: Bool, failed: Bool) -> String? {
        guard cancelled == false, failed else { return nil }
        return searchMessage
    }
}
