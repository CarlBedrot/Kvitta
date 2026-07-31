import Foundation
import KvittaCore

/// Fetches the ECB's daily reference rates. Lives in this package because it is a network call,
/// and this is the only package that knows a network exists (CLAUDE.md).
///
/// The source is `eurofxref-daily.xml`: a flat, stable document the ECB has served unchanged for
/// two decades, with each rate as a *string attribute* — which is the whole reason it was chosen
/// over any JSON API. A JSON number arrives through a decoder as a `Double`; a string attribute
/// goes straight into `ExchangeRates.micro(parsing:)` and money never meets floating point.
///
/// Failure is silence by design: conversion is a display convenience layered on exact
/// per-currency numbers, not something the app depends on. No alert, no retry loop — the next
/// foreground refresh will try again.
public struct ECBRateClient: Sendable {
    /// The currencies worth carrying — the four the app's pickers offer. Everything else in the
    /// ECB table is dead weight on a phone.
    public static let wanted: Set<CurrencyCode> = [.sek, .dkk, .nok]

    private let session: URLSession
    private let url: URL

    public init(
        session: URLSession = .shared,
        url: URL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    ) {
        self.session = session
        self.url = url
    }

    /// The day's rates, or `nil` for any failure at all.
    public func fetch() async -> ExchangeRates? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8) else { return nil }
        return Self.parse(xml)
    }

    /// Pulls `time='…'` and every `currency='…' rate='…'` pair out of the document with a plain
    /// string scan. Split out of `fetch` so the parsing is testable from a fixture string with
    /// no network anywhere near the test.
    public static func parse(_ xml: String) -> ExchangeRates? {
        guard let asOf = attribute("time", firstIn: xml) else { return nil }

        var micro: [CurrencyCode: Int64] = [:]
        // Each rate line looks like: <Cube currency='SEK' rate='11.2345'/>
        for fragment in xml.components(separatedBy: "currency=").dropFirst() {
            guard let code = quoted(at: fragment.startIndex, in: fragment),
                  let currency = CurrencyCode(code),
                  wanted.contains(currency),
                  let rateRange = fragment.range(of: "rate="),
                  let rate = quoted(at: rateRange.upperBound, in: fragment),
                  let value = ExchangeRates.micro(parsing: rate) else { continue }
            micro[currency] = value
        }

        // A table missing any wanted currency is a format change, not a partial success —
        // better to keep yesterday's complete cache than store today's incomplete one.
        guard Set(micro.keys) == wanted else { return nil }
        return ExchangeRates(asOf: asOf, microPerEuro: micro)
    }

    private static func attribute(_ name: String, firstIn xml: String) -> String? {
        guard let range = xml.range(of: "\(name)=") else { return nil }
        return quoted(at: range.upperBound, in: xml)
    }

    /// The value between the quote pair starting at `index` — ECB uses single quotes, but a
    /// future switch to double quotes should not break the world.
    private static func quoted(at index: String.Index, in text: String) -> String? {
        guard index < text.endIndex else { return nil }
        let quote = text[index]
        guard quote == "'" || quote == "\"" else { return nil }
        let valueStart = text.index(after: index)
        guard let valueEnd = text[valueStart...].firstIndex(of: quote) else { return nil }
        return String(text[valueStart..<valueEnd])
    }
}
