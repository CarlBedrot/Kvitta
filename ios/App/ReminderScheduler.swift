import Foundation
import KvittaCore
import KvittaStorage
import UserNotifications

/// Weekly local reminders about money you owe.
///
/// Local notifications, not push. That is not a compromise here — it is the right tool: the phone
/// already knows every balance, because the whole ledger is on it. Asking a server to tell you
/// something you can compute offline would make a core feature depend on a network the app is
/// designed to work without.
///
/// It also means this needs no Apple Developer team, unlike the APNs silent push in the same
/// milestone, which cannot be built at all without one.
@MainActor
@Observable
final class ReminderScheduler {
    /// The one request identifier, so rescheduling replaces rather than accumulates.
    private static let identifier = "se.kvitta.reminder.debts"
    private static let confirmIdentifier = "se.kvitta.reminder.confirmations"
    private static let enabledKey = "se.kvitta.reminders.enabled"

    private let centre: UNUserNotificationCenter
    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var wasDenied = false

    init(centre: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.centre = centre
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func setEnabled(_ enabled: Bool, ledger: LedgerStore, userId: UserID) async {
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            centre.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            return
        }

        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        wasDenied = !granted
        isEnabled = granted
        defaults.set(granted, forKey: Self.enabledKey)

        if granted {
            await reschedule(ledger: ledger, userId: userId)
        }
    }

    /// Recomputes the pending reminder from the current ledger.
    ///
    /// Called after any change worth reacting to. Cancelling when nothing is owed matters as much
    /// as scheduling: a notification that fires on Sunday about a debt settled on Friday is worse
    /// than no notification, because it teaches people the app is wrong.
    func reschedule(ledger: LedgerStore, userId: UserID) async {
        centre.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        guard isEnabled else { return }

        await scheduleConfirmationNudge(ledger: ledger, userId: userId)

        let outstanding = ReminderPlanner.outstanding(in: ledger.state, for: userId)
        guard let largest = outstanding.first else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Du är skyldig pengar")
        content.body = outstanding.count == 1
            ? String(
                format: String(localized: "%@ i %@."),
                MoneyFormat.string(largest.owed.amountMinor, largest.owed.currency),
                largest.groupName
            )
            : String(
                format: String(localized: "%@ i %@, och i %d grupper till."),
                MoneyFormat.string(largest.owed.amountMinor, largest.owed.currency),
                largest.groupName,
                outstanding.count - 1
            )
        content.sound = .default

        // Sunday evening: late enough that the weekend's spending has happened, early enough to
        // do something about it. Weekly rather than daily — this is a nudge, not a debt collector.
        var when = DateComponents()
        when.weekday = 1
        when.hour = 19

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        )

        try? await centre.add(request)
    }

    /// Somebody says they paid you and is waiting on your answer (M8). One notification the
    /// next morning, not weekly: unlike a debt, this blocks *their* books, and after seven days
    /// it auto-confirms anyway — so the useful window is short.
    private func scheduleConfirmationNudge(ledger: LedgerStore, userId: UserID) async {
        centre.removePendingNotificationRequests(withIdentifiers: [Self.confirmIdentifier])

        let awaiting = ReminderPlanner.awaitingMyConfirmation(in: ledger.state, for: userId)
        guard let largest = awaiting.first else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Stämmer betalningen?")
        content.body = awaiting.count == 1
            ? String(
                format: String(localized: "%@ i %@ väntar på att du bekräftar."),
                MoneyFormat.string(largest.amount.amountMinor, largest.amount.currency),
                largest.groupName
            )
            : String(
                format: String(localized: "%d betalningar väntar på att du bekräftar."),
                awaiting.count
            )
        content.sound = .default

        var when = DateComponents()
        when.hour = 9

        let request = UNNotificationRequest(
            identifier: Self.confirmIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )

        try? await centre.add(request)
    }

    /// For the debug menu: what is actually queued.
    func pendingCount() async -> Int {
        await centre.pendingNotificationRequests().count
    }
}
