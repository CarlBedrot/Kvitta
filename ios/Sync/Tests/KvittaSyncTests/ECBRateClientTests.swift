import Foundation
import Testing
import KvittaCore
@testable import KvittaSync

/// Parsing the ECB daily XML — from a fixture string, with no network anywhere near the test.
/// The fixture is the document's real shape, abbreviated: what matters is that rates travel as
/// string attributes and land as scaled integers without passing through a Double.
@Suite("ECB rate parsing")
struct ECBRateClientTests {

    private let fixture = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01">
            <Cube>
                <Cube time='2026-07-31'>
                    <Cube currency='USD' rate='1.0812'/>
                    <Cube currency='SEK' rate='11.2345'/>
                    <Cube currency='DKK' rate='7.4603'/>
                    <Cube currency='NOK' rate='11.6180'/>
                    <Cube currency='JPY' rate='168.51'/>
                </Cube>
            </Cube>
        </gesmes:Envelope>
        """

    @Test("The wanted currencies come out as micro-units, the rest are ignored")
    func parsesTheFixture() throws {
        let rates = try #require(ECBRateClient.parse(fixture))

        #expect(rates.asOf == "2026-07-31")
        #expect(rates.microPerEuro[.sek] == 11_234_500)
        #expect(rates.microPerEuro[.dkk] == 7_460_300)
        #expect(rates.microPerEuro[.nok] == 11_618_000)
        // EUR is the base and always present; USD and JPY are dead weight and dropped.
        #expect(rates.microPerEuro[.eur] == 1_000_000)
        #expect(rates.microPerEuro[CurrencyCode("USD")!] == nil)
    }

    @Test("A table missing a wanted currency is refused whole")
    func partialTableIsRefused() {
        let partial = fixture.replacingOccurrences(
            of: "<Cube currency='DKK' rate='7.4603'/>",
            with: ""
        )
        // Keeping yesterday's complete cache beats storing today's incomplete one.
        #expect(ECBRateClient.parse(partial) == nil)
    }

    @Test("Garbage is nil, never a crash and never a made-up rate", arguments: [
        "",
        "<html>404</html>",
        "<Cube time='2026-07-31'><Cube currency='SEK' rate='elva'/></Cube>"
    ])
    func garbageIsNil(xml: String) {
        #expect(ECBRateClient.parse(xml) == nil)
    }

    @Test("Double-quoted attributes parse the same")
    func doubleQuotesWork() throws {
        let doubled = fixture.replacingOccurrences(of: "'", with: "\"")
        let rates = try #require(ECBRateClient.parse(doubled))
        #expect(rates.microPerEuro[.sek] == 11_234_500)
    }
}
