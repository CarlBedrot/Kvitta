import SwiftUI

/// Mer → Hjälpcenter (#157): `docs/how-slice-works.md`, read straight from the app instead of
/// the repo, for the friend who is curious how their money is actually handled. Mermaid diagrams
/// and tables render fine on GitHub but not in a `Text`, so they are dropped here rather than
/// shown as raw source; everything else is the document's own words.
struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Hjälpcenter", leading: .back { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Self.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(verbatim: section.title)
                                .stevenFont(.cardTitle)
                                .foregroundStyle(StevenColor.ink)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(Self.inlineMarkdown(paragraph))
                                    .stevenFont(.rowTitle)
                                    .foregroundStyle(StevenColor.inkSoft)
                            }
                        }
                    }
                }
                .padding(StevenMetric.gutter)
            }
        }
        .background(StevenColor.screen)
        .navigationBarHidden(true)
    }

    fileprivate struct Section {
        let title: String
        let paragraphs: [String]
    }

    private static let sections: [Section] = parse(HelpCenterContent.markdown)

    /// `## Heading` starts a new section; fenced code (Mermaid included) and table rows are
    /// skipped; everything else becomes a paragraph, one per non-empty line.
    static func parse(_ text: String) -> [Section] {
        var sections: [Section] = []
        var title = ""
        var paragraphs: [String] = []
        var inFence = false

        func flush() {
            guard !title.isEmpty else { return }
            sections.append(Section(title: title, paragraphs: paragraphs))
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if line.hasPrefix("## ") {
                flush()
                title = String(line.dropFirst(3))
                paragraphs = []
            } else if line.isEmpty || line.hasPrefix("# ") || line == "---" || line.hasPrefix("|") {
                continue
            } else {
                paragraphs.append(line)
            }
        }
        flush()
        return sections
    }

    /// Best-effort inline styling (bold, links, code); falls back to the raw line rather than
    /// showing nothing if a line is not valid inline Markdown.
    private static func inlineMarkdown(_ line: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
    }
}

#Preview("Hjälpcenter – light") { HelpCenterView() }
#Preview("Hjälpcenter – dark") { HelpCenterView().preferredColorScheme(.dark) }
