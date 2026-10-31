import SwiftData
import SwiftUI

/// Artboard **07** / `Insights-Options.dc.html` — Insights Options sheet.
///
/// Controls privacy, which reading sessions count, exclusions, export, and reset.
/// Settings are local-only and stored via `@AppStorage`.
struct InsightsOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme

    @AppStorage("kudos.insights.discreetMode") private var discreetMode: Bool = false
    @AppStorage("kudos.insights.hideReadingTime") private var hideReadingTime: Bool = false
    @AppStorage("kudos.insights.countRereads") private var countRereads: Bool = true
    @AppStorage("kudos.insights.countReadAloud") private var countReadAloud: Bool = true
    @AppStorage("kudos.insights.askAboutUntouched") private var askAboutUntouched: Bool = true

    let onShowHowCounted: () -> Void
    let onExport: () -> Void

    @State private var showingResetAlert = false
    @State private var showingLeftOutInfo = false

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
                    Toggle(isOn: $countRereads) {
                        Label {
                            Text("Count Rereads in Totals")
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.effectiveTint)

                    Toggle(isOn: $countReadAloud) {
                        Label {
                            Text("Count Read Aloud as Reading")
                        } icon: {
                            Image(systemName: "headphones")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.effectiveTint)

                    Toggle(isOn: $askAboutUntouched) {
                        Label {
                            Text("Ask About Untouched Works")
                        } icon: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.effectiveTint)

                    Button {
                        showingLeftOutInfo = true
                    } label: {
                        HStack {
                            Label {
                                Text("Left Out of Insights")
                            } icon: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("0")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("What Counts")
                } footer: {
                    Text("Kudos asks after 3 weeks without opening a work you’re partway through. A work is only marked stopped when you say so.")
                }
                .appThemedRows()

                Section {
                    Button {
                        onExport()
                    } label: {
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
                    Text("Export saves sessions, statuses and reasons. Reset deletes the reading log only; works, progress and statuses stay.")
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
                Text("This permanently deletes your local reading log. Your saved works, shelves and reading progress are kept.")
            }
            .alert("Left Out of Insights", isPresented: $showingLeftOutInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Works, fandoms or tags you exclude in Settings won't be counted in Reading Insights.")
            }
        }
    }

    private func resetReadingLog() {
        let descriptor = FetchDescriptor<ReadingSession>()
        if let sessions = try? modelContext.fetch(descriptor) {
            for session in sessions {
                modelContext.delete(session)
            }
            try? modelContext.save()
        }
    }
}

/// Artboard **07** / `Insights-Stopped.dc.html` — Stopped Reading sheet.
///
/// Prompts for why reading was stopped, offers to hide the tag in search,
/// and lets the reader put the work On Hold instead.
struct StoppedReadingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let work: SavedWork
    let onMarkStopped: (String, String?) -> Void
    let onPutOnHold: () -> Void

    @State private var selectedReason: String = "Lost Interest"
    @State private var selectedTag: String? = nil
    @State private var hideTagInSearch: Bool = false
    @State private var privateNote: String = ""

    private let reasons = [
        "Lost Interest",
        "Too Long",
        "Writing Style",
        "Tag Dealbreaker",
        "Got Spoiled",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Work Summary Card
                    workCard

                    // Reason Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        FlowLayout(spacing: 8) {
                            ForEach(reasons, id: \.self) { reason in
                                let isSelected = selectedReason == reason
                                Button {
                                    selectedReason = reason
                                } label: {
                                    Text(reason)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? theme.effectiveTint : theme.appTheme.cardSurface
                                        )
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.clear : theme.appTheme.cardBorder, lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Reason: \(reason)")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }

                    // Which Tag Section
                    let availableTags = work.workWarnings + work.workTags
                    if !availableTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Which Tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            VStack(alignment: .leading, spacing: 12) {
                                FlowLayout(spacing: 8) {
                                    ForEach(Array(availableTags.prefix(8)), id: \.self) { tag in
                                        let isSelected = selectedTag == tag
                                        Button {
                                            selectedTag = isSelected ? nil : tag
                                        } label: {
                                            Text(tag)
                                                .font(.footnote)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    isSelected ? theme.effectiveTint.opacity(0.16) : theme.appTheme.cardBackdrop
                                                )
                                                .foregroundStyle(isSelected ? theme.effectiveTint : Color.primary)
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(isSelected ? theme.effectiveTint : Color.clear, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Tag: \(tag)")
                                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                                    }
                                }

                                Divider()

                                Toggle("Hide This Tag in Search", isOn: $hideTagInSearch)
                                    .font(.subheadline)
                                    .tint(theme.effectiveTint)

                                Divider()

                                HStack(spacing: 8) {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                    TextField("Private Note", text: $privateNote)
                                        .font(.subheadline)
                                }
                            }
                            .padding(14)
                            .background(theme.appTheme.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                            )
                        }
                    }

                    // Action Buttons (50 pt full-width per I-9)
                    VStack(spacing: 10) {
                        Button {
                            onMarkStopped(selectedReason, selectedTag)
                            dismiss()
                        } label: {
                            Text("Mark as Stopped")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 50)
                                .background(theme.effectiveTint)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            onPutOnHold()
                            dismiss()
                        } label: {
                            Text("Put On Hold Instead")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 50)
                                .background(Color.primary.opacity(0.08))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(theme.appTheme.cardBackdrop)
            .navigationTitle("Stopped Reading?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(theme.effectiveTint)
                }
            }
        }
    }

    private var workCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let firstFandom = work.workFandoms.first, !firstFandom.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(fandomColor(for: firstFandom))
                        .frame(width: 8, height: 8)
                    Text(firstFandom)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(work.title)
                .font(.headline)
                .foregroundStyle(.primary)

            let progress = Int(((work.readingProgress ?? 0) * 100).rounded())
            let chapterStr = work.postedChapterCount > 0 ? "Chapter \(work.lastSpineIndex + 1) of \(work.postedChapterCount)" : ""
            Text("\(chapterStr)\(chapterStr.isEmpty ? "" : " · ")\(progress)%")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
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
