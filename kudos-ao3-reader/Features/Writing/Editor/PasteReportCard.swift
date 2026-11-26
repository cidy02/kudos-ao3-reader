import Foundation
import SwiftUI

/// One itemized category inside a `PasteLossReport` (kept, removed, or normalized), with its
/// occurrence count and optional sample snippets.
nonisolated struct PasteChangeItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let label: String
    let count: Int
    let examples: [String]

    init(id: String? = nil, label: String, count: Int, examples: [String] = []) {
        self.id = id ?? label
        self.label = label
        self.count = max(0, count)
        self.examples = examples
    }
}

/// Summary of what survived and what AO3 cannot show after pasting formatted text
/// (`Editor-Paste.dc.html`, plan §6.8 & §6.9).
nonisolated struct PasteLossReport: Equatable, Hashable, Sendable {
    var wordCount: Int
    var sourceName: String?
    var kept: [PasteChangeItem]
    var removed: [PasteChangeItem]
    var normalized: [PasteChangeItem]

    init(
        wordCount: Int,
        sourceName: String? = nil,
        kept: [PasteChangeItem] = [],
        removed: [PasteChangeItem] = [],
        normalized: [PasteChangeItem] = []
    ) {
        self.wordCount = max(0, wordCount)
        self.sourceName = sourceName
        self.kept = kept
        self.removed = removed
        self.normalized = normalized
    }

    var totalRemovedCount: Int {
        removed.reduce(0) { $0 + $1.count }
    }

    var totalNormalizedCount: Int {
        normalized.reduce(0) { $0 + $1.count }
    }

    var hasChangeDetails: Bool {
        !kept.isEmpty || !removed.isEmpty || !normalized.isEmpty
    }

    /// Headline text (e.g. `"Pasted 2,140 words from Google Docs"`).
    var headline: String {
        let base = "Pasted \(wordCount.formatted()) \(wordCount == 1 ? "word" : "words")"
        if let source = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            return "\(base) from \(source)"
        }
        return base
    }

    /// Natural-language summary of kept formatting (e.g. `"Kept italics, bold and centred lines."`).
    var keptSummary: String? {
        let names = kept.map(\.label).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return "Kept \(Self.joinList(names))."
    }

    /// Natural-language summary of removed elements/styles AO3 can't show.
    var removedSummary: String? {
        let nonZero = removed.filter { $0.count > 0 }
        guard !nonZero.isEmpty else { return nil }
        if nonZero.count == 1, let only = nonZero.first {
            return "Removed \(only.count.formatted()) \(only.label) AO3 can’t show."
        }
        let total = nonZero.reduce(0) { $0 + $1.count }
        return "Removed \(total.formatted()) \(total == 1 ? "item" : "items") AO3 can’t show."
    }

    /// Summary sentence shown under the card headline.
    var summaryText: String {
        let clauses = [keptSummary, removedSummary].compactMap { $0 }
        if !clauses.isEmpty {
            return clauses.joined(separator: " ")
        }
        if totalNormalizedCount > 0 {
            let noun = totalNormalizedCount == 1 ? "detail" : "details"
            return "Normalized \(totalNormalizedCount.formatted()) markup \(noun) for AO3."
        }
        return "Ready for AO3."
    }

    private static func joinList(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }
}

/// Floating card summarizing a paste operation (`Editor-Paste.dc.html`): shows word count,
/// source app, what was kept, what AO3 can't show, Undo Paste, and a What Changed breakdown.
struct PasteReportCard: View {
    let report: PasteLossReport
    let onUndoPaste: () -> Void
    var onWhatChanged: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDetailsSheet = false

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            actionRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        .shadow(
            color: appTheme.cardShadow.color,
            radius: max(appTheme.cardShadow.radius, appTheme.isDarkFamily ? 0 : 10),
            y: max(appTheme.cardShadow.y, appTheme.isDarkFamily ? 0 : 4)
        )
        .sheet(isPresented: $showingDetailsSheet) {
            PasteReportDetailsSheet(report: report)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(report.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondaryInk)
                        .frame(width: 28, height: 28)
                        .background(appTheme.glassFill(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .minimumHitTarget(44)
                .accessibilityLabel("Dismiss paste report")
            }
        }
    }

    private var statusIcon: some View {
        let color = appTheme.statusSuccessColor
        return Image(systemName: "checkmark")
            .font(.footnote.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(
                color.opacity(appTheme.isDarkFamily ? 0.22 : 0.14),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var actionRow: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            pillButton(title: "Undo Paste", accessibilityLabel: "Undo paste", action: onUndoPaste)
            if report.hasChangeDetails || onWhatChanged != nil {
                pillButton(title: "What Changed", accessibilityLabel: "What changed") {
                    if let onWhatChanged {
                        onWhatChanged()
                    } else {
                        showingDetailsSheet = true
                    }
                }
            }
        }
    }

    private func pillButton(
        title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .background(appTheme.glassFill(0.10), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Native detail list opened from `PasteReportCard`'s "What Changed" button.
struct PasteReportDetailsSheet: View {
    let report: PasteLossReport

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }

    var body: some View {
        NavigationStack {
            List {
                if !report.kept.isEmpty {
                    Section("Kept") {
                        ForEach(report.kept) { item in
                            changeRow(item, symbol: "checkmark.circle.fill", tint: appTheme.statusSuccessColor)
                        }
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }

                if !report.removed.isEmpty {
                    Section {
                        ForEach(report.removed) { item in
                            changeRow(
                                item,
                                symbol: "minus.circle.fill",
                                tint: appTheme.isDarkFamily ? .subjectAmber : Color(red: 0.68, green: 0.40, blue: 0.0)
                            )
                        }
                    } header: {
                        Text("Removed (AO3 Can’t Show)")
                    } footer: {
                        Text("AO3’s sanitizer strips these automatically when you post.")
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }

                if !report.normalized.isEmpty {
                    Section {
                        ForEach(report.normalized) { item in
                            changeRow(item, symbol: "arrow.triangle.2.circlepath", tint: .secondary)
                        }
                    } header: {
                        Text("Normalized for AO3")
                    } footer: {
                        Text("Same meaning, rewritten into clean AO3 HTML.")
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }
            }
            .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
            .background((appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("What Changed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
        }
    }

    private func changeRow(_ item: PasteChangeItem, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(item.label)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                if item.count > 0 {
                    Text("×\(item.count.formatted())")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
            }
            if !item.examples.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.examples, id: \.self) { example in
                        Text(example)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Paste Report Card") {
    let sample = PasteLossReport(
        wordCount: 2_140,
        sourceName: "Google Docs",
        kept: [
            PasteChangeItem(label: "italics", count: 18, examples: ["<em>someone else’s</em>"]),
            PasteChangeItem(label: "bold", count: 4, examples: ["<strong>She</strong>"]),
            PasteChangeItem(label: "centred lines", count: 2, examples: ["<p align=\"center\">~</p>"])
        ],
        removed: [
            PasteChangeItem(label: "indents", count: 3, examples: ["style=\"margin-left: 36pt\""])
        ],
        normalized: [
            PasteChangeItem(
                label: "Google Docs wrapper spans",
                count: 1,
                examples: ["<b id=\"docs-internal-guid-…\">"]
            )
        ]
    )
    return VStack {
        Spacer()
        PasteReportCard(report: sample, onUndoPaste: {}, onDismiss: {})
            .padding()
    }
    .environment(ThemeManager())
}
