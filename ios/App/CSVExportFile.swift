import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import KvittaCore

/// The group ledger as a shareable CSV file, generated lazily by `ShareLink` — nothing touches
/// disk until the person picks a destination.
///
/// A mixed-currency group exports one section per currency bucket, stacked with a blank line
/// between them, because a single table mixing SEK and DKK rows would invite exactly the
/// summing-across-currencies mistake the app refuses everywhere else.
struct CSVExportFile: Transferable {
    let group: GroupState

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory
                .appending(path: Self.filename(for: export.group))
            try Data(export.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    var text: String {
        let asOf = CalendarDate(Date())
        return group.balances(asOf: asOf).currencies
            .map { GroupCSV.file(for: group, in: $0, asOf: asOf) }
            .joined(separator: "\n")
    }

    static func filename(for group: GroupState) -> String {
        // The group name minus anything a filesystem dislikes; emoji are fine, slashes are not.
        let safe = GroupBadge.title(of: group.name)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "Slice – \(safe).csv"
    }
}
