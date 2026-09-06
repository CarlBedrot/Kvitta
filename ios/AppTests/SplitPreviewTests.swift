import Foundation
import Testing
import KvittaCore
@testable import Kvitta

/// The line under "delas lika (4)" on the add sheet is the first place the split is *shown*
/// rather than described, so it has to be read off the resolved shares — the same ones that get
/// saved — and never from a division of its own. Otherwise the preview and the ledger could
/// disagree by an öre, which is the one lie this app is built not to tell.
struct SplitPreviewTests {

    private let members = (0..<4).map { _ in MemberID() }

    @Test("Four people on 480 kr: everyone carries 120 kr, and the row says so once")
    func equalSplitHasOnePerPersonAmount() {
        let draft = SplitDraft(members: members)
        let preview = draft.preview(totalMinor: 48_000, members: members)

        #expect(preview.participants == members)
        #expect(preview.perPersonMinor == 12_000)
        #expect(preview.shares.map(\.amountMinor) == [12_000, 12_000, 12_000, 12_000])
    }

    @Test("Three people on 100 kr: the shown shares sum to exactly 100,00 kr")
    func unevenRemainderStaysHonest() {
        let three = Array(members.prefix(3))
        let draft = SplitDraft(members: three)
        let preview = draft.preview(totalMinor: 10_000, members: three)

        // 33,34 + 33,33 + 33,33 — the remainder goes to one person, so there is no single
        // "var" amount to promise, and what is listed still adds up to the total.
        #expect(preview.perPersonMinor == nil)
        #expect(preview.shares.map(\.amountMinor).reduce(0, +) == 10_000)
        #expect(preview.shares.map(\.amountMinor).sorted(by: >) == [3_334, 3_333, 3_333])
    }

    @Test("Someone left out in the editor is not in the row")
    func excludedMemberDisappears() {
        var draft = SplitDraft(members: members)
        draft.included.remove(members[1])
        let preview = draft.preview(totalMinor: 30_000, members: members)

        #expect(preview.participants == [members[0], members[2], members[3]])
        #expect(preview.perPersonMinor == 10_000)
    }

    @Test("Before there is an amount, the row still knows who is included")
    func zeroAmountShowsParticipantsOnly() {
        let draft = SplitDraft(members: members)
        let preview = draft.preview(totalMinor: 0, members: members)

        #expect(preview.participants == members)
        #expect(preview.perPersonMinor == nil)
        #expect(preview.shares.isEmpty)
    }
}
