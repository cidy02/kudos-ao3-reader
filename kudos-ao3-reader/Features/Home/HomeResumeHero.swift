import SwiftData
import SwiftUI

struct HomeResumeHero: View {
    let work: SavedWork
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var onSelect: (() -> Void)?

    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            let hero = UnblurredHomeResumeHero(work: work)
                .environment(\.ao3AuthorNavigationEnabled, false)
                .blur(radius: 6)
                .overlay {
                    if !isSelecting {
                        Label("Tap to reveal", systemImage: "eye.slash.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .contentShape(Rectangle())

            if isSelecting {
                hero
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .onTapGesture { onToggleSelection?() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hidden mature work")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                    .localWorkContextMenu(work: work, onSelect: onSelect)
            } else {
                hero
                    .onTapGesture { gate.reveal(work) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hidden mature work. Activate to reveal.")
                    .localWorkContextMenu(work: work, onSelect: onSelect)
            }
        } else if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                UnblurredHomeResumeHero(work: work)
                    // Nested author byline would otherwise fight this Button for the
                    // same tap in selection mode — disabled here the same way the
                    // blurred branch above already disables it.
                    .environment(\.ao3AuthorNavigationEnabled, false)
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(work.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .localWorkContextMenu(work: work, onSelect: onSelect)
        } else {
            // A NavigationLink wrapping the hero, like every other card in
            // HomeView — *not* `.cardNavigation`.
            //
            // `cardNavigation` puts an invisible link in the *background* and
            // relies on the enclosing List to make the whole row activate it
            // ("The List still makes the whole card tappable" — its own doc).
            // Every other caller is inside a `List`. Home is a ScrollView, so
            // there was no row activation, and the hero's own background and
            // `contentShape` sit in front of that invisible link: the card
            // simply did not respond to taps.
            //
            // The byline keeps its own tap because it is a Button inside the
            // link's label, which takes the touch within its own bounds; the
            // author push also sets `AppRouter.cardNavigationSuppressed`, so a
            // reader/work push landing from the same touch dismisses itself
            // rather than burying the profile.
            NavigationLink(value: LocalWorkDestination.reader(work)) {
                UnblurredHomeResumeHero(work: work)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(work.title)
            .localWorkContextMenu(work: work, onSelect: onSelect)
        }
    }
}

private struct UnblurredHomeResumeHero: View {
    let work: SavedWork
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 31
    @ScaledMetric(relativeTo: .caption) private var metadataSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2) private var dateSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var buttonSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var ringSize: CGFloat = 68

    /// Spec 1b floats the four-signal tray in the card's top-trailing corner and
    /// reserves 94pt of the kicker's and title's trailing edge for it, so long
    /// titles wrap before they reach it instead of running underneath. An
    /// overlay rather than an HStack sibling: the tray is much taller than one
    /// line of kicker, and in an HStack its height would drive the whole row's
    /// spacing to whatever sits below.
    private let signalTrayReservedWidth: CGFloat = 94

    /// Individual author names for the byline — matches WorkDetailView's
    /// `displayAuthorList` derivation for the same work.
    private var authorNames: [String] {
        work.verifiedAuthorIdentities.isEmpty
            ? (work.author.isEmpty ? [] : [work.author])
            : work.verifiedAuthorIdentities.map(\.displayName)
    }

    private var subjectHue: Double {
        CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
    }

    private var subjectPalette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: subjectHue)
    }

    private var primaryFandomName: String? {
        work.workFandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Clamped so a nil or out-of-range stored fraction can never draw a
    /// negative or over-full ring. An in-progress work can legitimately have no
    /// stored fraction (only a `lastReadDate`), which shows as 0% rather than
    /// an invented number.
    private var resolvedReadingProgress: Double {
        min(1, max(0, work.readingProgress ?? 0))
    }

    /// The last-opened date backs up the stored locator title and remains useful
    /// for legacy or restored records with no publication label (spec 1b).
    private var lastReadRelativeDescription: String? {
        guard let lastReadDate = work.lastReadDate else { return nil }
        return lastReadDate.formatted(.relative(presentation: .named))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize { signalTray }
            if let primaryFandomName {
                SubjectKicker(text: primaryFandomName, palette: subjectPalette, size: 9.5, ruleSpacing: 7)
                    .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : signalTrayReservedWidth)
            }

            Text(work.title)
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-0.62)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : signalTrayReservedWidth)

            metadataLine
            resumeRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(heroCardBackground)
        .overlay(alignment: .topTrailing) {
            if !dynamicTypeSize.isAccessibilitySize { signalTray.padding(14) }
        }
        .contentShape(RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous))
        .workCardZoomSource(work.zoomKey, in: zoomNamespace)
    }

    private var signalTray: some View {
        WorkStatusIconGrid(
                rating: work.rating.isEmpty ? nil : work.rating,
                categories: work.workCategories,
                warnings: work.workWarnings,
                completion: work.completionStatus,
                tileSize: 22,
                announcesToVoiceOver: true,
                showsTray: true
        )
    }

    /// The author is a real `AO3AuthorBylineView` so the name stays tappable
    /// here exactly as it is everywhere else in the app; the two figures beside
    /// it are plain text, joined by the spec's dimmed middle dot.
    @ViewBuilder
    private var metadataLine: some View {
        let figureSegments = WorkStat.localWorkMetadata(
            author: "", wordCount: work.wordCount, chapters: work.chapters
        )
        FlowLayout(spacing: 8, rowSpacing: 6) {
            if !work.author.isEmpty {
                AO3AuthorBylineView(
                    names: authorNames,
                    identities: work.verifiedAuthorIdentities,
                    includesBy: false,
                    font: .system(size: metadataSize),
                    expandsHitTarget: false
                )
                if !figureSegments.isEmpty {
                    metadataSeparator
                }
            }
            ForEach(Array(figureSegments.enumerated()), id: \.offset) { index, segment in
                Text(segment)
                    .font(.system(size: metadataSize))
                if index < figureSegments.count - 1 {
                    metadataSeparator
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.primary.opacity(0.75))
    }

    private var metadataSeparator: some View {
        Text("·")
            .font(.system(size: metadataSize))
            .foregroundStyle(Color.primary.opacity(0.35))
            .accessibilityHidden(true)
    }

    /// Ring, then where you stopped, then the one filled control on the card.
    private var resumeRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            HStack(spacing: 16) {
                WorkProgressRing(
                    progress: resolvedReadingProgress,
                    state: resolvedReadingProgress >= 1 ? "Finished" : "Reading",
                    diameter: ringSize
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(WorkReadingPosition.title(from: work.readiumLocator)
                         ?? (lastReadRelativeDescription == nil ? "Ready to resume" : "Last opened"))
                        .font(.system(size: metadataSize, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let lastReadRelativeDescription {
                        Text(lastReadRelativeDescription)
                            .font(.system(size: dateSize))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Drawn, not a Button: the whole hero is already one navigation
            // link into the reader, and a second tap target inside it would
            // race the link for the same touch. VoiceOver reads the card's own
            // label and hint instead, so this stays out of the tree.
            Text("Resume")
                .font(.system(size: buttonSize, weight: .semibold))
                .foregroundStyle(subjectPalette.solidButtonLabel)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(subjectPalette.solidButtonFill, in: Capsule())
                .accessibilityHidden(true)
        }
    }

    private var heroCardBackground: some View {
        let heroShape = RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous)
        return heroShape
            .fill(themeManager.appTheme.carouselCardSurface)
            .overlay(heroShape.fill(subjectPalette.cardWash))
            .overlay(heroShape.strokeBorder(subjectPalette.cardBorder, lineWidth: 0.5))
            .shadow(
                color: themeManager.appTheme.carouselCardShadow.color,
                radius: themeManager.appTheme.carouselCardShadow.radius + 6,
                x: 0,
                y: themeManager.appTheme.carouselCardShadow.y + 2
            )
    }
}
