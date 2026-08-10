import UIKit
import KvittaCore
import KvittaStorage
import KvittaSync

/// The text a friend pastes into chat when something looks wrong.
///
/// Everything needed to reason about "my balance is weird" or "it won't sync" — versions,
/// sync state, queue depths, rejection codes, skip reasons — and deliberately **nothing else**:
/// no names, no amounts, no phone numbers, no group names. The report must be safe to forward
/// without thinking, or nobody will send it.
@MainActor
enum DiagnosticReport {

    static func text(
        ledger: LedgerStore,
        sync: SyncEngine,
        rates: RateStore,
        signedIn: Bool
    ) -> String {
        var lines: [String] = []

        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        lines.append("Slice \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)")
        lines.append("Konto: \(signedIn ? "inloggad" : "utloggad") · Synk: \(label(for: sync.status))")
        if let last = sync.lastSyncedAt {
            lines.append("Senast synkad: \(last.date.formatted(.iso8601))")
        }
        if let rates = rates.rates {
            lines.append("Valutakurser: \(rates.asOf)")
        } else {
            lines.append("Valutakurser: saknas")
        }
        lines.append("Utkorg: \((try? ledger.pendingPushCount()) ?? -1) · Oläsbara rader: \(ledger.rejected.count)")

        // One line per group, identified by an id prefix — enough to correlate against the
        // server, useless to anyone else.
        lines.append("")
        lines.append("Grupper: \(ledger.state.groups.count)")
        for group in ledger.state.groupsByLastActivity {
            let id = String(group.id.rawValue.uuidString.prefix(8)).lowercased()
            let pending = group.paymentsAwaitingConfirmation().count
            lines.append(
                "· \(id): \(group.members.count) medlemmar, \(group.expenses.count) utgifter, "
                + "\(group.payments.count) betalningar (\(pending) väntar), seq \(group.lastAppliedSeq ?? 0)"
            )
        }

        // Skips and rejections are the two "should always be empty" lists. Reasons only.
        if !ledger.state.skipped.isEmpty {
            lines.append("")
            lines.append("Överhoppade händelser: \(ledger.state.skipped.count)")
            for (reason, count) in countedDescriptions(ledger.state.skipped.map(\.reason)) {
                lines.append("· \(count)× \(reason)")
            }
        }
        if !ledger.rejectedPushes.isEmpty {
            lines.append("")
            lines.append("Avvisade av servern: \(ledger.rejectedPushes.count)")
            for rejected in ledger.rejectedPushes {
                let id = String(rejected.event.eventId.rawValue.uuidString.prefix(8)).lowercased()
                lines.append("· \(rejected.event.type) \(id): \(rejected.code)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func label(for status: SyncStatus) -> String {
        switch status {
        case .disabled: return "avstängd"
        case .idle: return "ok"
        case .syncing: return "pågår"
        case .offline: return "offline"
        case .blocked(let message): return "blockerad (\(message))"
        }
    }

    private static func countedDescriptions(_ reasons: [SkipReason]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for reason in reasons {
            // The reason's shape without its ids: "unknownMember(...)" → "unknownMember".
            let name = String(describing: reason).prefix { $0 != "(" }
            counts[String(name), default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
    }
}
