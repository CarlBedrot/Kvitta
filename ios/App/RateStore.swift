import Foundation
import KvittaCore
import KvittaSync

/// The last good ECB rate table, cached on this device, and the refresh that keeps it current.
///
/// Rates power *display-only* conversion — the ≈ numbers. They are never written to an event and
/// never touch a stored amount, so the failure mode of everything here is mild by construction:
/// no rates simply means the ≈ view is unavailable and the exact per-currency numbers stand alone.
@MainActor
@Observable
final class RateStore {
    private static let key = "se.kvitta.exchangeRates"

    private let defaults: UserDefaults
    private(set) var rates: ExchangeRates?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            self.rates = try? JSONDecoder().decode(ExchangeRates.self, from: data)
        }
    }

    /// Fetches at most once per ECB fixing date. Called from the foreground hook, next to the
    /// sync pull — silence on failure, because conversion is a convenience, not a dependency.
    func refresh(using client: ECBRateClient = ECBRateClient()) async {
        let today = Date().formatted(.iso8601.year().month().day())
        if let rates, rates.asOf == today { return }

        guard let fresh = await client.fetch() else { return }
        rates = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// How one group's mixed-currency money is shown to *this viewer*. A display preference, per
/// group, on this device — never an event, because how Carl likes to read a balance is not a
/// fact about the group.
enum CurrencyDisplay: Hashable {
    /// Every bucket, exact. The default: precision first, approximation on request.
    case native
    /// One bucket only — "bara DKK".
    case only(CurrencyCode)
    /// Everything ≈-converted into the group's primary currency. Needs rates.
    case converted

    var storageValue: String {
        switch self {
        case .native: return "native"
        case .only(let code): return "only:\(code.code)"
        case .converted: return "converted"
        }
    }

    init(storageValue: String) {
        if storageValue == "converted" { self = .converted }
        else if storageValue.hasPrefix("only:"), let code = CurrencyCode(String(storageValue.dropFirst(5))) {
            self = .only(code)
        } else {
            self = .native
        }
    }
}

/// The per-group persistence for `CurrencyDisplay`, same pattern as `PayeeDirectory`.
@MainActor
@Observable
final class CurrencyDisplayStore {
    private let defaults: UserDefaults
    private var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func mode(for groupId: GroupID) -> CurrencyDisplay {
        _ = generation
        guard let raw = defaults.string(forKey: key(groupId)) else { return .native }
        return CurrencyDisplay(storageValue: raw)
    }

    func set(_ mode: CurrencyDisplay, for groupId: GroupID) {
        defaults.set(mode.storageValue, forKey: key(groupId))
        generation += 1
    }

    private func key(_ groupId: GroupID) -> String {
        "se.kvitta.currencyDisplay.\(groupId.rawValue.uuidString)"
    }
}
