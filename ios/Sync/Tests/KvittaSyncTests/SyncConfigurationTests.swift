import Foundation
import Testing
@testable import KvittaSync

/// Where a bearer token may be sent. The rule exists because the base URL is user-overridable —
/// and the sideload trial depends on the LAN exemption actually working: a friend's phone
/// syncing against the dev Mac is plain http to a 192.168 address, and refusing it silently was
/// a working app that mysteriously never synced.
@Suite("SyncConfiguration trust")
struct SyncConfigurationTests {

    private func configuration(_ url: String) -> SyncConfiguration {
        SyncConfiguration(baseURL: URL(string: url)!)
    }

    @Test("https is trusted anywhere, plain http only at home", arguments: [
        ("https://api.example.com", true),
        ("http://localhost:5142", true),
        ("http://127.0.0.1:5142", true),
        ("http://192.168.1.34:5142", true),      // the friend-trial case
        ("http://10.0.0.7:5142", true),
        ("http://172.20.4.1:5142", true),
        ("http://169.254.10.10:5142", true),
        ("http://172.32.0.1:5142", false),       // just past the 172.16/12 block
        ("http://100.100.1.1:5142", false),      // CGNAT is not your living room
        ("http://8.8.8.8:5142", false),
        ("http://example.com:5142", false)       // a name can point anywhere; https or nothing
    ])
    func trustBoundary(url: String, trusted: Bool) {
        #expect(configuration(url).isTrustworthy == trusted)
    }
}
