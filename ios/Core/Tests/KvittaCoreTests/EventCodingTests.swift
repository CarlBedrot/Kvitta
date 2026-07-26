import Foundation
import Testing
@testable import KvittaCore

@Suite("Event coding")
struct EventCodingTests {
    private let members = (1...3).map { Fixtures.member($0) }

    private var memberJSON: String {
        members.map { "\"\($0.rawValue.uuidString)\"" }.joined(separator: ",")
    }

    private func expenseEventJSON(
        eventId: String = "00000000-0000-0000-000C-000000000001",
        amountMinor: Int64 = 43_700,
        shares: [Int64] = [14_567, 14_567, 14_566],
        extras: String = ""
    ) -> String {
        let shareLines = zip(members, shares)
            .map { "{\"memberId\":\"\($0.rawValue.uuidString)\",\"amountMinor\":\($1)}" }
            .joined(separator: ",")
        return """
            {
              "eventId": "\(eventId)",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.expense(1).rawValue.uuidString)",
              "type": "ExpenseCreated",
              "schemaVersion": 1,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "serverSeq": 4711,
              \(extras)
              "payload": {
                "description": "Systembolaget",
                "categoryId": "alkohol",
                "date": "2026-07-21",
                "currency": "SEK",
                "amountMinor": \(amountMinor),
                "payers": [{"memberId":"\(members[0].rawValue.uuidString)","amountMinor":\(amountMinor)}],
                "shares": [\(shareLines)],
                "splitMethod": "equal",
                "splitInput": {"method":"equal","members":[\(memberJSON)]}
              }
            }
            """
    }

    @Test("An expense event survives a decode and re-encode unchanged")
    func expenseRoundTrip() throws {
        let decoded = try EventCoding.decode(Data(expenseEventJSON().utf8))

        #expect(decoded.type == EventType.expenseCreated)
        #expect(decoded.serverSeq == 4711)
        #expect(decoded.expenseId == Fixtures.expense(1))
        #expect(decoded.clientTimestamp == Fixtures.timestamp)

        let expense = try #require(decoded.payload.expense)
        #expect(expense.amountMinor == 43_700)
        #expect(expense.shares.map(\.amountMinor) == [14_567, 14_567, 14_566])
        #expect(expense.splitInput == .equal(among: members))

        let reencoded = try EventCoding.decode(try EventCoding.encode(decoded))
        #expect(reencoded == decoded)
    }

    @Test("Unknown fields are ignored, at both the envelope and the payload level")
    func unknownFieldsAreTolerated() throws {
        let json = """
            {
              "eventId": "00000000-0000-0000-000C-000000000002",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.member(1).rawValue.uuidString)",
              "type": "MemberAdded",
              "schemaVersion": 7,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00.500Z",
              "serverSeq": 12,
              "aFieldFromTheFuture": {"nested": [1, 2, 3]},
              "payload": {
                "displayName": "Jonas",
                "favouriteColour": "clay",
                "avatarVersion": 4
              }
            }
            """
        let decoded = try EventCoding.decode(Data(json.utf8))

        guard case .memberAdded(let payload) = decoded.payload else {
            Issue.record("Expected a MemberAdded payload, got \(decoded.payload)")
            return
        }
        #expect(payload.displayName == "Jonas")
        #expect(payload.linkedUserId == nil)
        #expect(decoded.schemaVersion == 7)
        #expect(decoded.clientTimestamp.epochMilliseconds % 1000 == 500)
    }

    @Test("schemaVersion defaults to 1 when a sender omits it")
    func missingSchemaVersionDefaults() throws {
        let json = """
            {
              "eventId": "00000000-0000-0000-000C-000000000003",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.groupId.rawValue.uuidString)",
              "type": "GroupCreated",
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "payload": {"name": "Fjällresan", "currency": "SEK"}
            }
            """
        let decoded = try EventCoding.decode(Data(json.utf8))
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.serverSeq == nil)
        #expect(decoded.isAcknowledged == false)
    }

    @Test("An event type from a newer build decodes, survives a round trip, and keeps its payload")
    func unknownEventTypeIsPreserved() throws {
        let json = """
            {
              "eventId": "00000000-0000-0000-000C-000000000004",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.expense(9).rawValue.uuidString)",
              "type": "CommentAdded",
              "schemaVersion": 2,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "serverSeq": 99,
              "payload": {"text": "vem drack all vin", "reactions": ["🍷"]}
            }
            """
        let decoded = try EventCoding.decode(Data(json.utf8))

        guard case .unknown(let type, let raw) = decoded.payload else {
            Issue.record("Expected an unknown payload, got \(decoded.payload)")
            return
        }
        #expect(type == "CommentAdded")
        #expect(raw["text"]?.stringValue == "vem drack all vin")
        #expect(decoded.type == "CommentAdded")

        // The whole point: an older build can hold this event and hand it back byte-identically.
        let reencoded = try EventCoding.decode(try EventCoding.encode(decoded))
        #expect(reencoded == decoded)
    }

    @Test("A lifecycle payload tolerates fields it has never heard of")
    func lifecyclePayloadTolerance() throws {
        let json = """
            {
              "eventId": "00000000-0000-0000-000C-000000000005",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.expense(1).rawValue.uuidString)",
              "type": "ExpenseDeleted",
              "schemaVersion": 1,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "serverSeq": 5,
              "payload": {"reason": "duplicate", "deletedFrom": "iPhone"}
            }
            """
        let decoded = try EventCoding.decode(Data(json.utf8))
        #expect(decoded.type == EventType.expenseDeleted)
    }

    @Test("A payment round-trips, including an unfamiliar payment method")
    func paymentRoundTrip() throws {
        let json = """
            {
              "eventId": "00000000-0000-0000-000C-000000000006",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.payment(1).rawValue.uuidString)",
              "type": "PaymentRecorded",
              "schemaVersion": 1,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "serverSeq": 6,
              "payload": {
                "fromMemberId": "\(members[1].rawValue.uuidString)",
                "toMemberId": "\(members[0].rawValue.uuidString)",
                "currency": "SEK",
                "amountMinor": 14567,
                "date": "2026-07-22",
                "method": "vipps",
                "note": "tack!"
              }
            }
            """
        let decoded = try EventCoding.decode(Data(json.utf8))

        guard case .paymentRecorded(let payload) = decoded.payload else {
            Issue.record("Expected a PaymentRecorded payload, got \(decoded.payload)")
            return
        }
        #expect(payload.amountMinor == 14_567)
        #expect(payload.method == PaymentMethod(rawValue: "vipps"))
        #expect(payload.date == CalendarDate(year: 2026, month: 7, day: 22))

        let reencoded = try EventCoding.decode(try EventCoding.encode(decoded))
        #expect(reencoded == decoded)
    }

    @Test("A payment that violates the money rules is rejected on decode")
    func invalidPaymentIsRejected() {
        let json = """
            {
              "eventId": "00000000-0000-0000-000C-000000000007",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.payment(2).rawValue.uuidString)",
              "type": "PaymentRecorded",
              "schemaVersion": 1,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "serverSeq": 7,
              "payload": {
                "fromMemberId": "\(members[0].rawValue.uuidString)",
                "toMemberId": "\(members[0].rawValue.uuidString)",
                "currency": "SEK",
                "amountMinor": 100,
                "date": "2026-07-22",
                "method": "cash"
              }
            }
            """
        #expect(throws: (any Error).self) {
            try EventCoding.decode(Data(json.utf8))
        }
    }

    @Test("An expense that breaks the money invariant cannot be decoded into existence")
    func invariantViolationIsRejectedOnDecode() {
        // Shares total 43 699, one öre short of the stated amount.
        let json = expenseEventJSON(shares: [14_567, 14_567, 14_565])
        #expect(throws: (any Error).self) {
            try EventCoding.decode(Data(json.utf8))
        }
    }

    @Test("One rotten event does not spoil the sync page it arrived in")
    func batchDecodeIsolatesFailures() throws {
        let good = expenseEventJSON(eventId: "00000000-0000-0000-000D-000000000001")
        let bad = expenseEventJSON(
            eventId: "00000000-0000-0000-000D-000000000002",
            shares: [14_567, 14_567, 99_999]
        )
        let futureType = """
            {
              "eventId": "00000000-0000-0000-000D-000000000003",
              "groupId": "\(Fixtures.groupId.rawValue.uuidString)",
              "entityId": "\(Fixtures.expense(3).rawValue.uuidString)",
              "type": "SomethingNew",
              "schemaVersion": 3,
              "authorId": "\(Fixtures.authorId.rawValue.uuidString)",
              "clientTimestamp": "2026-07-21T18:30:00Z",
              "serverSeq": 3,
              "payload": {"whatever": true}
            }
            """

        let result = try EventCoding.decodeBatch(Data("[\(good),\(bad),\(futureType)]".utf8))

        // The unknown type is accepted — it is not malformed, just unfamiliar.
        #expect(result.accepted.count == 2)
        #expect(result.rejected.count == 1)
        #expect(result.rejected.first?.index == 1)
        #expect(result.rejected.first?.eventId
            == EventID(uuidString: "00000000-0000-0000-000D-000000000002"))
        #expect(result.accepted.contains { $0.payload.isUnknown })
    }
}
