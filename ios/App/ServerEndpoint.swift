import Foundation

/// Which server this build talks to, and with what key — decided once at launch.
///
/// Pure so it can be tested without a bundle or defaults: the inputs are the two strings a
/// person may have typed into the Jag tab and the two the build was made with. The override
/// wins when it parses; the built-in server is the default; localhost is what is left for a
/// build made with no server at all, which is the shape a fresh clone has.
struct ServerEndpoint: Equatable {
    let baseURL: URL
    let trialKey: String?
    /// True when nothing was overridden and the build brought its own server and key.
    let isBuiltIn: Bool

    static let localhost = URL(string: "http://localhost:5142")!

    static func resolve(
        overrideURL: String?,
        overrideKey: String?,
        builtInURL: String?,
        builtInKey: String?
    ) -> ServerEndpoint {
        let typedURL = overrideURL.flatMap(URL.init(string:))
        let shippedURL = clean(builtInURL).flatMap(URL.init(string:))
        let typedKey = clean(overrideKey)
        let shippedKey = clean(builtInKey)

        if let typedURL {
            // A typed address is a developer or a LAN trial; the typed key goes with it, and the
            // shipped key is deliberately not sent to a server somebody just pointed us at.
            return ServerEndpoint(baseURL: typedURL, trialKey: typedKey, isBuiltIn: false)
        }
        if let shippedURL {
            return ServerEndpoint(
                baseURL: shippedURL,
                trialKey: typedKey ?? shippedKey,
                isBuiltIn: shippedKey != nil
            )
        }
        return ServerEndpoint(baseURL: localhost, trialKey: typedKey, isBuiltIn: false)
    }

    /// Empty and unsubstituted build-setting placeholders both mean "none": an xcconfig that was
    /// never written leaves the plist holding the literal `$(KVITTA_TRIAL_KEY)`.
    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
