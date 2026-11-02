import SwiftData
import SwiftUI

/// Artboard **07** / `Insights-Options.dc.html` — Insights Options sheet.
///
/// Controls privacy, export, and reset.
/// Settings are local-only and stored via `@AppStorage`.
struct InsightsOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme

    @AppStorage("kudos.insights.discreetMode") private var discreetMode: Bool = false
    @AppStorage("kudos.insights.hideReadingTime") private var hideReadingTime: Bool = false

    /// The same text the toolbar's ShareLink exports.
    let exportText: String
    let onShowHowCounted: () -> Void
    /// Called after a reset so the page reloads from the emptied log.
    let onReset: () -> Void

    @State private var showingResetAlert = false
    @State private var resetFailure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $discreetMode) {
                        Label {
                            Text("Discreet Mode")
                        } icon: {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.effectiveTint)

                    Toggle(isOn: $hideReadingTime) {
                        Label {
                            Text("Hide Reading Time")
                        } icon: {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.effectiveTint)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Discreet Mode hides fandom, relationship, character and tag names here and in exports. Totals stay.")
                }
                .appThemedRows()

                Section {
                    ShareLink(
                        item: exportText,
                        subject: Text("Reading Insights Export"),
                        message: Text("Export of Reading Insights from Kudos")
                    ) {
                        Label {
                            Text("Export Reading History…")
                                .foregroundStyle(theme.effectiveTint)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(theme.effectiveTint)
                        }
                    }

                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label {
                            Text("Reset Insights…")
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                } header: {
                    Text("Reading History")
                } footer: {
                    Text("Export shares this period’s totals (words, hours, works finished, reading days); no works are named. Reset deletes the reading log only; works, progress and statuses stay.")
                }
                .appThemedRows()

                Section {
                    Button {
                        onShowHowCounted()
                    } label: {
                        HStack {
                            Label {
                                Text("How Reading Insights Are Counted")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .appThemedRows()
            }
            .appThemedScroll()
            .navigationTitle("Insights Options")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(theme.effectiveTint)
                }
            }
            .alert("Reset Insights?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Log", role: .destructive) {
                    resetReadingLog()
                }
            } message: {
                Text("This permanently deletes your local reading log. Your saved works, shelves and reading progress are kept, but Finished, History and reread counts come from this log and will start again from zero.")
            }
            .alert("Couldn’t Reset Insights", isPresented: Binding(
                get: { resetFailure != nil },
                set: { if !$0 { resetFailure = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resetFailure ?? "")
            }
        }
    }

    private func resetReadingLog() {
        do {
            let sessions = try modelContext.fetch(FetchDescriptor<ReadingSession>())
            for session in sessions {
                SyncTombstones.recordDeletion(of: session, in: modelContext)
                modelContext.delete(session)
            }
            try modelContext.save()
            FolderSyncService.markDirty()
            onReset()
        } catch {
            modelContext.rollback()
            resetFailure = error.localizedDescription
        }
    }
}

/// Artboard **07** / `Insights-Metrics.dc.html` — How Reading Insights Are Counted.
///
/// Plain-English explanation of metric rules, calculations, and local privacy.
struct HowInsightsAreCountedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metricSection(
                        title: "Device-Only Privacy",
                        symbol: "lock.shield",
                        paragraphs: [
                            "Reading Insights are computed entirely on your device from your local reading log.",
                            "Nothing about what you read, when you read, or how fast you read is ever uploaded or sent anywhere."
                        ]
                    )

                    metricSection(
                        title: "Overview",
                        symbol: "chart.bar.xaxis",
                        paragraphs: [
                            "Words read: The sum of words read across your sittings in the period, based on your movement through each work and its AO3 word count.",
                            "Novels’ worth: Words read divided by 70,000, rounded to the nearest half novel. Shown when you have read at least 35,000 words.",
                            "Pace: Weighted words per hour across your active reading sessions. Sittings under 15 seconds are excluded so brief opens do not dilute your speed.",
                            "Longest streak: The longest run of consecutive calendar days with at least one recorded reading session."
                        ]
                    )

                    metricSection(
                        title: "Taste",
                        symbol: "sparkles",
                        paragraphs: [
                            "Your Usual Fic: Derived from your most frequent fandom, rating, category, and length among works read.",
                            "Fandoms & Ships: Attributed to each work's primary fandom and tagged relationships. Romantic (/) and platonic (&) bonds are distinguished.",
                            "Ship concentration: The share of a fandom’s words centered on its top relationship tag."
                        ]
                    )

                    metricSection(
                        title: "Habits",
                        symbol: "clock.arrow.circlepath",
                        paragraphs: [
                            "Time of Day: Tracks the local hours when your reading takes place, highlighting late-night reading between 1:00 AM and 5:00 AM.",
                            "Reading Days: A calendar heat map indicating days with reading activity in four color tiers based on words read.",
                            "Sittings: The median duration of your reading stretches, ignoring background pauses."
                        ]
                    )

                    metricSection(
                        title: "Library",
                        symbol: "books.vertical",
                        paragraphs: [
                            "Statuses: Every work in your library is partitioned into exactly one status: Reading, Caught Up, Letting Chapters Stack, On Hold, Saved for Later, Finished, or Stopped.",
                            "Works in Progress: Categorized as Active (updated in the last 6 months), Quiet (6 to 12 months), or Dormant (over a year).",
                            "No Longer on AO3: Identifies works you downloaded whose original AO3 pages are no longer available, safely preserved on your device."
                        ]
                    )
                }
                .padding(16)
            }
            .background(theme.appTheme.cardBackdrop)
            .navigationTitle("How Insights Are Counted")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(theme.effectiveTint)
                }
            }
        }
    }

    private func metricSection(title: String, symbol: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.effectiveTint)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}
