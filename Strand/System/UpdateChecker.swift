import Foundation
import WhoopProtocol

/// Nutry hosts NOOP inside the TestFlight app. Upstream's GitHub IPA check is disabled so wearers
/// are never sent to ryanbr/noop releases. The type and `State` cases stay so Settings still compiles.
@MainActor
final class UpdateChecker: ObservableObject {

    enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case available(version: String, url: URL, notes: String)
        case failed
    }

    @Published var state: State = .idle

    struct Release: Equatable {
        let version: String
        let url: URL
        let notes: String
    }

    /// Always `nil`: Nutry must not read or advertise foreign NOOP IPA releases.
    static func fetchLatest() async -> Release? {
        nil
    }

    func check(currentVersion: String) {
        state = .upToDate(version: currentVersion)
    }

    static func cleanNotes(_ body: String) -> String {
        var s = body.components(separatedBy: "Downloads").first ?? body
        for marker in ["**", "## ", "# "] { s = s.replacingOccurrences(of: marker, with: "") }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 700 { s = String(s.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" }
        return s
    }
}
