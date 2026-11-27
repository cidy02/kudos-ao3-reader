import SwiftUI

/// Paper preview card shown in the Recent grid of `StudioDocumentsPagesView`.
struct StudioRecentPaperCard: View {
    let item: StudioRecentDocumentItem

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let paperBackground: Color = theme.appTheme == .light
            ? Color(red: 0.984, green: 0.980, blue: 0.965)
            : theme.appTheme.cardSurface
        let paperBorder: Color = theme.appTheme == .light
            ? Color(red: 0.898, green: 0.875, blue: 0.824)
            : theme.appTheme.glassStroke(0.18)

        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.paperHeading)
                    .font(.system(.caption, design: .serif, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text(item.excerpt)
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 7)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(
                minHeight: dynamicTypeSize.isAccessibilitySize ? 130 : 172,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(paperBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(paperBorder, lineWidth: 0.5)
            )
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                if let badgeText = item.badgeText {
                    badgeView(text: badgeText, tone: item.badgeTone)
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(item.metaLine)
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    @ViewBuilder
    private func badgeView(text: String, tone: StudioRecentDocumentItem.BadgeTone) -> some View {
        switch tone {
        case .draft:
            SubjectStateBadge(title: text, color: .orange)
        case .onDevice:
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.appTheme.glassFill(0.12), in: Capsule())
        case .none:
            EmptyView()
        }
    }
}

/// Expanded top manuscript card on `Studio-Documents`, showing state, chapter
/// status dots, Work Details shortcut, and Add Chapter.
struct StudioFeaturedManuscriptCard: View {
    let work: StudioWorkItem
    let store: WritingDocumentStore
    let onChanged: () -> Void
    var onAO3Write: () -> Void = {}
    let onAddChapter: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let previewChapters = Array(work.localChapters.prefix(5))
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if let localWork = work.localWork, !previewChapters.isEmpty {
                ForEach(Array(previewChapters.enumerated()), id: \.element.id) { index, chapter in
                    SubjectRowSeparator(inset: 14)
                    chapterRow(
                        chapter: chapter,
                        position: index + 1,
                        workID: localWork.id,
                        workTitle: work.title
                    )
                }
            } else {
                SubjectRowSeparator(inset: 14)
                openFilesLink
            }
            SubjectRowSeparator(inset: 14)
            addChapterButton
        }
        .subjectPanel(cornerRadius: 18)
    }

    private var headerRow: some View {
        let stateLine = work.manuscriptStateLine(deviceName: ThisDevice.name)
        return HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                StudioWorkFilesView(
                    work: work,
                    store: store,
                    onChanged: onChanged,
                    onAO3Write: onAO3Write
                )
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(work.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stateLine)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(work.title), \(stateLine)")

            if let ao3WorkID = work.ao3WorkID, auth.isLoggedIn {
                NavigationLink {
                    WritingWorkDestination(workID: ao3WorkID) { onAO3Write() }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.accentInk)
                        .frame(width: 34, height: 34)
                        .background(theme.appTheme.cardSurface, in: Circle())
                        .overlay(
                            Circle().strokeBorder(theme.appTheme.glassStroke(0.14), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel("Work details for \(work.title)")
            }
        }
        .padding(14)
    }

    private var openFilesLink: some View {
        NavigationLink {
            StudioWorkFilesView(
                work: work,
                store: store,
                onChanged: onChanged,
                onAO3Write: onAO3Write
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.body)
                    .foregroundStyle(theme.accentInk)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Open chapters and notes")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open chapters and notes for \(work.title)")
    }

    private var addChapterButton: some View {
        Button(action: onAddChapter) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accentInk)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Add Chapter")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.accentInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add chapter to \(work.title)")
    }

    private func chapterRow(
        chapter: WritingChapter,
        position: Int,
        workID: UUID,
        workTitle: String
    ) -> some View {
        let badge = StudioWorkFilesLogic.badgeStatus(for: chapter)
        let rawTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled" : rawTitle
        let statusLine = chapterStatusLine(chapter: chapter, badge: badge)
        let wordsText = chapter.wordCount > 0 ? chapter.wordCount.formatted() : ""
        let titleColor: AnyShapeStyle = badge == .planned
            ? AnyShapeStyle(.secondaryInk)
            : AnyShapeStyle(Color.primary)
        let statusColor: AnyShapeStyle = badge == .ao3Draft
            ? AnyShapeStyle(Color.orange)
            : AnyShapeStyle(.secondaryInk)

        return NavigationLink {
            LocalChapterEditorScreen(
                workID: workID,
                chapterID: chapter.id,
                initialWorkTitle: workTitle,
                store: store
            )
        } label: {
            HStack(spacing: 12) {
                chapterNumberDot(position: position, badge: badge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(badge == .ao3Draft ? .semibold : .medium))
                        .foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(statusLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !wordsText.isEmpty {
                    Text(wordsText)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Chapter \(position), \(title), \(statusLine)"
                + (wordsText.isEmpty ? "" : ", \(chapter.wordCount) words")
        )
        .accessibilityAddTraits(.isButton)
    }

    private func chapterNumberDot(position: Int, badge: StudioChapterBadgeStatus) -> some View {
        let label = Text("\(position)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
        return Group {
            switch badge {
            case .posted:
                Circle()
                    .fill(theme.effectiveTint)
                    .overlay(label.foregroundStyle(ThemeManager.label(on: theme.effectiveTint)))
            case .ao3Draft, .onDevice:
                Circle()
                    .fill(theme.appTheme.cardSurface)
                    .overlay(Circle().strokeBorder(theme.accentInk, lineWidth: 1.5))
                    .overlay(label.foregroundStyle(theme.accentInk))
            case .planned:
                Circle()
                    .strokeBorder(
                        theme.appTheme.glassStroke(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    )
                    .overlay(label.foregroundStyle(.secondaryInk))
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func chapterStatusLine(
        chapter: WritingChapter,
        badge: StudioChapterBadgeStatus
    ) -> String {
        switch badge {
        case .posted:
            "Posted · \(WorkStat.displayDate(chapter.updatedAt))"
        case .ao3Draft:
            "Draft · edited \(WorkStat.displayDate(chapter.updatedAt))"
        case .onDevice:
            "On this \(ThisDevice.name) · edited \(WorkStat.displayDate(chapter.updatedAt))"
        case .planned:
            "Planned"
        }
    }
}

/// Compact row for additional manuscripts under the featured card on Pages.
struct StudioManuscriptListRow: View {
    let work: StudioWorkItem
    let store: WritingDocumentStore
    let onChanged: () -> Void
    var onAO3Write: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stateLine = work.manuscriptStateLine(deviceName: ThisDevice.name)
        NavigationLink {
            StudioWorkFilesView(
                work: work,
                store: store,
                onChanged: onChanged,
                onAO3Write: onAO3Write
            )
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.title)
                        .font(.system(.body, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stateLine)
                        .font(.footnote)
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
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(work.title), \(stateLine)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Single loose local draft row opening directly into `LocalChapterEditorScreen`.
struct StudioLooseDraftRow: View {
    let item: StudioWorkItem
    let store: WritingDocumentStore

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        if let localWork = item.localWork {
            let meta = item.looseDraftMetaLine(deviceName: ThisDevice.name)
            NavigationLink {
                LocalChapterEditorScreen(
                    workID: localWork.id,
                    chapterID: item.localChapters.first?.id,
                    initialWorkTitle: item.title,
                    store: store
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.body)
                        .foregroundStyle(theme.accentInk)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(meta)")
            .accessibilityAddTraits(.isButton)
        }
    }
}
