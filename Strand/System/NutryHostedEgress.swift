import Foundation

/// Hard egress policy for the NOOP engine when it is hosted inside Nutry.
///
/// Allowed destinations for the Nutry app as a whole:
/// 1. the Nutry backend (`nutry-api.leoponthieux.fr`, the legacy
///    `nutry.nas-nebulon.synology.me`, or a relative `/api/…`);
/// 2. Bluetooth to the wearer's WHOOP strap (not HTTP);
/// 3. Apple system services used by Nutry product features (MapKit for Coursy/Vely).
///
/// Spotify, Deezer and Apple Music artwork are not allowed through this engine.
/// The Nutry app polls those hosts from LiveMusic.swift only after the user links a service.
///
/// Everything else that NOOP upstream might phone home to (GitHub releases, WHOOP cloud,
/// Oura cloud when compiled in, OpenAI/Anthropic/Gemini, arbitrary custom HTTP export URLs)
/// is refused here.
enum NutryHostedEgress {
    /// Always true in this repository: Vendor/NOOP is compiled only as NutryWhoopFeature.
    static let isEmbeddedInNutry = true

    /// Both public names of the same install: the Cloudflare Tunnel used by this
    /// build, and the legacy reverse proxy still served for older builds.
    static let nutryAPIHosts: Set<String> = [
        "nutry-api.leoponthieux.fr",
        "nutry.nas-nebulon.synology.me",
    ]

    /// True when `url` is an allowed Nutry API destination (scheme https, known host).
    static func allowsNutryAPI(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }
        guard let host = url.host?.lowercased() else { return false }
        if nutryAPIHosts.contains(host) { return true }
        // Local/dev overrides sometimes use localhost while developing the same API.
        if host == "localhost" || host == "127.0.0.1" { return true }
        return false
    }

    /// Call at every NOOP URLSession entry point. Always throws when embedded in Nutry.
    static func denyNOOPOutbound(feature: String) -> Error {
        NSError(
            domain: "fr.leoponthieux.nutry.egress",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Nutry bloque « \(feature) » : aucun appel réseau NOOP vers un tiers. "
                    + "Seuls le serveur Nutry et le Bluetooth WHOOP sont autorisés.",
            ])
    }

    /// Force the NOOP AI Coach master switch off so no background brief can fire.
    @MainActor
    static func disableNOOPCloudFeatures() {
        UserDefaults.standard.set(false, forKey: "noop.coachEnabled")
        UserDefaults.standard.set(false, forKey: "updates.autoCheck")
        UserDefaults.standard.set(false, forKey: "coachBrief.enabled")
        CoachBriefScheduler.applyMasterSwitch(false)
    }
}
