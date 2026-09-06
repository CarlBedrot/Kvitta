import Foundation
import Testing
@testable import Kvitta

/// "1 personer" was the kind of slip that makes an app look machine-made. The plural lives in the
/// String Catalog, not in code, so the only honest test is to ask the compiled catalog — in both
/// languages, because the source language gets its own plural table too.
///
/// Each language is asked through its own `.lproj` bundle. `String(localized:locale:)` alone
/// does not do that: the locale picks the plural *rule*, the strings still come from whatever
/// language the host app is running in, so a Swedish check on an English simulator quietly
/// passes for the wrong reason (or fails for the right one).
struct PluralCopyTests {

    private func personer(_ count: Int, in language: String) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return String(localized: "\(count) personer", bundle: bundle, locale: Locale(identifier: language))
    }

    @Test func swedishSingularAndPlural() throws {
        #expect(try personer(1, in: "sv") == "1 person")
        #expect(try personer(2, in: "sv") == "2 personer")
    }

    @Test func englishSingularAndPlural() throws {
        #expect(try personer(1, in: "en") == "1 person")
        #expect(try personer(2, in: "en") == "2 people")
    }
}
