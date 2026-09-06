import Foundation
import Testing
@testable import Kvitta

/// Which server a build talks to. The bug this guards against is the one the first hosted
/// deploy had: a real server existed and every phone still pointed at localhost.
@Suite("ServerEndpoint")
struct ServerEndpointTests {
    private let fly = "https://slice-api.fly.dev"
    private let key = "friend-trial-key-that-is-long-enough-to-count-as-one"

    @Test("a build with a server and a key uses both, and knows it")
    func builtIn() {
        let endpoint = ServerEndpoint.resolve(overrideURL: nil, overrideKey: nil, builtInURL: fly, builtInKey: key)
        #expect(endpoint.baseURL.absoluteString == fly)
        #expect(endpoint.trialKey == key)
        #expect(endpoint.isBuiltIn)
    }

    @Test("a typed address wins, and the shipped key does not follow it")
    func override() {
        let endpoint = ServerEndpoint.resolve(
            overrideURL: "http://192.168.0.155:5142", overrideKey: nil, builtInURL: fly, builtInKey: key
        )
        #expect(endpoint.baseURL.absoluteString == "http://192.168.0.155:5142")
        #expect(endpoint.trialKey == nil)
        #expect(!endpoint.isBuiltIn)
    }

    @Test("an unwritten xcconfig leaves a placeholder, which counts as no key")
    func placeholder() {
        let endpoint = ServerEndpoint.resolve(
            overrideURL: nil, overrideKey: nil, builtInURL: fly, builtInKey: "$(KVITTA_TRIAL_KEY)"
        )
        #expect(endpoint.baseURL.absoluteString == fly)
        #expect(endpoint.trialKey == nil)
        #expect(!endpoint.isBuiltIn)
    }

    @Test("a typed key fills in for a build made without one")
    func typedKey() {
        let endpoint = ServerEndpoint.resolve(overrideURL: nil, overrideKey: " \(key) ", builtInURL: fly, builtInKey: "")
        #expect(endpoint.trialKey == key)
        #expect(!endpoint.isBuiltIn)
    }

    @Test("the word default as an override means the built-in server, key and all")
    func defaultWord() {
        let endpoint = ServerEndpoint.resolve(overrideURL: "default", overrideKey: nil, builtInURL: fly, builtInKey: key)
        #expect(endpoint.baseURL.absoluteString == fly)
        #expect(endpoint.trialKey == key)
        #expect(endpoint.isBuiltIn)
    }

    @Test("no server anywhere means localhost, the fresh-clone shape")
    func nothing() {
        let endpoint = ServerEndpoint.resolve(overrideURL: nil, overrideKey: nil, builtInURL: nil, builtInKey: nil)
        #expect(endpoint.baseURL == ServerEndpoint.localhost)
        #expect(endpoint.trialKey == nil)
    }
}
