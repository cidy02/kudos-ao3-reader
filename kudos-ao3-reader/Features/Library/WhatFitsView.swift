import SwiftData
import SwiftUI

/// `Queue-TimeFit.dc.html`: pick how long you have and see across all queues
/// what you can finish now, then what you can start and finish (offline first).
/// Purely local — makes zero AO3 requests and excludes works with no word count.
struct WhatFitsView: View {
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(filter: #Predicate<ReadingQueue> { !$0.isPendingDeletion }, sort: \ReadingQueue.sortOrder)
    private var readingQueues: [ReadingQueue]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })
    private var libraryWorks: [SavedWork]
    @Query private var tagAliases: [TagAlias]

    @State private var selectedBucket: WhatFitsBucket = .defaultSelection

    @ScaledMetric(relativeTo: .subheadline) private var pillFontSize: CGFloat = 15

    private var plan: WhatFitsPlan {
        WhatFitsPlanner.plan(
            queues: readingQueues,
            bucket: selectedBucket,
            isVisible: { !gate.isHidden($0, enabled: hideMature, mode: matureMode) },
            libraryWorks: libraryWorks,
            tagAliases: TagAliasResolver(models: tagAliases)
        )
    }

    private func showsMatureMenu(for plan: WhatFitsPlan) -> Bool {
        guard hideMature else { return false }
        return plan.hasHiddenMatureFits || plan.allEntries.contains { $0.work.isAdult }
    }

    var body: some View {
        let currentPlan = plan
        List {
            Section {
                SubjectPageHeading(
                    title: "What Fits",
                    subtitle: subtitleText(queueCount: currentPlan.queueCount),
                    palette: themeManager.scopePalette
                )
                .pageBodyRow(top: 12, gutter: 0)

                bucketPicker
                    .pageBodyRow(top: 14, gutter: SubjectMetrics.gutter)
            }

            if currentPlan.isEmpty {
                Section {
                    emptyStateView(for: currentPlan)
                        .bareListRow()
                }
            } else {
                if !currentPlan.finishInThisSitting.isEmpty {
                    Section {
                        SectionRuleHeader(title: "Finish in this sitting")
                            .accessibilityAddTraits(.isHeader)
                            .pageBodyRow(top: 18, gutter: 0)
                        ForEach(currentPlan.finishInThisSitting) { entry in
                            workRow(for: entry)
                        }
                    }
                }

                if !currentPlan.startAndFinish.isEmpty {
                    Section {
                        SectionRuleHeader(title: "Start and finish")
                            .accessibilityAddTraits(.isHeader)
                            .pageBodyRow(top: 18, gutter: 0)
                        ForEach(currentPlan.startAndFinish) { entry in
                            workRow(for: entry)
                        }
                    }
                }
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: themeManager.scopePalette, role: .content)
        .subjectOwnHeadingChrome(title: "What Fits")
        .toolbar {
            if showsMatureMenu(for: currentPlan) {
                ToolbarItem(placement: .primaryAction) {
                    WorkListMoreMenu {
                        MatureRevealToggle()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    private func subtitleText(queueCount: Int) -> String {
        guard queueCount > 0 else { return "No reading queues yet" }
        let noun = queueCount == 1 ? "queue" : "queues"
        return "From your \(queueCount) \(noun) · offline works first"
    }

    private var bucketPicker: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            : Array(repeating: GridItem(.flexible(), spacing: 8), count: WhatFitsBucket.allCases.count)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(WhatFitsBucket.allCases) { bucket in
                bucketButton(bucket)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time you have")
    }

    private func bucketButton(_ bucket: WhatFitsBucket) -> some View {
        let isSelected = bucket == selectedBucket
        let fill = themeManager.effectiveTint
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return Button {
            Haptics.selection()
            selectedBucket = bucket
        } label: {
            Text(bucket.title)
                .font(.system(size: pillFontSize, weight: .semibold))
                .foregroundStyle(isSelected ? ThemeManager.label(on: fill) : Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    shape.fill(isSelected ? AnyShapeStyle(fill) : AnyShapeStyle(themeManager.appTheme.glassFill()))
                )
        }
        .buttonStyle(.borderless)
        .minimumHitTarget()
        .accessibilityLabel(bucket.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func workRow(for entry: WhatFitsEntry) -> some View {
        let isBlurred = gate.isBlurred(entry.work, enabled: hideMature, mode: matureMode)
        return VStack(alignment: .leading, spacing: 0) {
            SensitiveWorkRow(
                work: entry.work,
                openMode: .reader,
                presentation: .ledger,
                showsFavoriteStar: true,
                showsFullLedgerStats: true,
                showsSummary: false,
                showsSeparator: false
            )
            if !isBlurred {
                entryFootnote(for: entry)
            }
            WorkRowSeparator()
        }
        .cardRow(isSelected: false, chrome: .plain)
    }

    private func entryFootnote(for entry: WhatFitsEntry) -> some View {
        let timeText = Text(entry.timeLabel)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
        let queueText = entry.queueSummary.isEmpty
            ? Text("")
            : Text(" · \(entry.queueSummary)")
                .foregroundStyle(.secondaryInk)
        let downloadText = entry.isOffline
            ? Text("")
            : Text(" · Needs download")
                .foregroundStyle(.secondaryInk)
        return Text("\(timeText)\(queueText)\(downloadText)")
            .font(.footnote)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WorkRowMetrics.horizontalPadding)
            .padding(.bottom, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.accessibilitySummary)
    }

    @ViewBuilder
    private func emptyStateView(for plan: WhatFitsPlan) -> some View {
        if plan.hasHiddenMatureFits {
            ContentUnavailableView {
                Label("Mature works are hidden", systemImage: "eye.slash")
            } description: {
                Text("Hide Mature is hiding works that fit \(selectedBucket.title).")
            } actions: {
                MatureRevealToggle()
            }
        } else if !plan.hasAnyVisibleWorks {
            ContentUnavailableView {
                Label("Nothing queued yet", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Add works to your reading queues to see what fits the time you have.")
            }
        } else if !plan.hasAnyUnfinishedWorks {
            ContentUnavailableView {
                Label("All queued works are finished", systemImage: "checkmark.circle")
            } description: {
                Text("Unfinished works in your reading queues will appear here.")
            }
        } else if !plan.hasAnyWordCounts {
            ContentUnavailableView {
                Label("No word counts yet", systemImage: "clock")
            } description: {
                Text("What Fits uses each work's word count to estimate reading time without making AO3 requests.")
            }
        } else {
            ContentUnavailableView {
                Label("Nothing fits in \(selectedBucket.title)", systemImage: "clock")
            } description: {
                if let next = plan.nextFittingBucket {
                    Text("\(next.bucket.title) has \(next.count) \(next.count == 1 ? "work" : "works") that fit.")
                } else {
                    Text("None of your queued works fit in \(selectedBucket.title).")
                }
            } actions: {
                if let next = plan.nextFittingBucket {
                    Button("Try \(next.bucket.title)") {
                        Haptics.selection()
                        selectedBucket = next.bucket
                    }
                    .buttonStyle(.borderedProminent)
                    .accentFill()
                    .prominentLabel()
                }
            }
        }
    }
}

/// Entry row at the top of the Queues organizer (`AllReadingQueuesGridView`)
/// pushing `WhatFitsView`.
struct WhatFitsOrganizerRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.accentInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("What Fits")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("See what you can finish across your queues")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .subjectRowNavigation(accessibilityLabel: "What Fits, see what you can finish across your queues") {
            WhatFitsView()
        }
    }
}
