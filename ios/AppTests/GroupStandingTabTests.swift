import Testing
@testable import Kvitta

/// `shortMemberName` is the one pure function behind STÄLLNING's member cards (#149,
/// README §1.2: "Ellen E" — first name plus the initial of the last).
struct GroupStandingTabTests {
    @Test func firstNameAndLastInitial() {
        #expect(shortMemberName("Ellen Ekwall") == "Ellen E")
        #expect(shortMemberName("Carl Bedrot") == "Carl B")
    }

    @Test func oneWordNameIsLeftAsIs() {
        #expect(shortMemberName("Carl") == "Carl")
    }

    @Test func middleNamesCollapseIntoTheInitial() {
        // "maxSplits: 1" — only the first space matters; everything after it is "the last name".
        #expect(shortMemberName("Carl Magnus Bedrot") == "Carl M")
    }

    @Test func extraWhitespaceDoesNotCrash() {
        #expect(shortMemberName("") == "")
        #expect(shortMemberName(" ") == " ")
    }
}
