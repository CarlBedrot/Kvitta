import Testing
import Foundation
import KvittaCore
@testable import Kvitta

struct StevenComponentTests {
    private let nbsp = "\u{00A0}"

    @Test func amountsUseSwedishGroupingAndDecimalsOnlyWhenNeeded() {
        #expect(StevenMoneyFormat.string(5_354_508, .sek) == "53\(nbsp)545,08\(nbsp)kr")
        #expect(StevenMoneyFormat.string(36_800, .sek) == "368\(nbsp)kr")
        #expect(StevenMoneyFormat.string(67_655, .sek) == "676,55\(nbsp)kr")
        #expect(StevenMoneyFormat.string(5, .sek) == "0,05\(nbsp)kr")
        #expect(StevenMoneyFormat.string(100_000_000, .sek) == "1\(nbsp)000\(nbsp)000\(nbsp)kr")
        #expect(StevenMoneyFormat.string(-1_000, .sek, sign: .negativeOnly) == "-10\(nbsp)kr")
        #expect(StevenMoneyFormat.string(8_000, .dkk, explicit: true) == "80\(nbsp)DKK")
    }

    @Test func theMostNegativeAmountDoesNotTrap() {
        #expect(StevenMoneyFormat.string(.min, .sek, sign: .negativeOnly).hasPrefix("-92"))
    }

    @Test func balanceStateFollowsTheSign() {
        #expect(Steven.Balance(netMinor: 500, currency: .sek) == .theyOwe(amountMinor: 500, currency: .sek))
        #expect(Steven.Balance(netMinor: -500, currency: .sek) == .youOwe(amountMinor: 500, currency: .sek))
        #expect(Steven.Balance(netMinor: 0, currency: .sek) == .settled)
    }

    @Test func pastelIsStablePerMemberAndInRange() {
        let id = MemberID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        let first = Steven.AvatarView.pastelIndex(for: id)
        #expect(first == Steven.AvatarView.pastelIndex(for: id))
        for _ in 0..<50 {
            let index = Steven.AvatarView.pastelIndex(for: MemberID(rawValue: UUID()))
            #expect((0..<StevenColor.avatarPastelHexes.count).contains(index))
        }
    }

    @Test func initialsTakeTheFirstTwoWords() {
        #expect(Steven.AvatarView.initials(of: "Ellen Ekwall") == "EE")
        #expect(Steven.AvatarView.initials(of: "carl") == "C")
        #expect(Steven.AvatarView.initials(of: "Anna Maria Lind") == "AM")
        #expect(Steven.AvatarView.initials(of: "  ") == "?")
    }
}
