import SwiftData
import SwiftUI

enum ResumeCardVariant: Equatable {
    case home
    case next
    case detail

    var barsHeight: CGFloat { self == .detail ? 76 : 52 }
    var primaryHeight: CGFloat { self == .detail ? 50 : 44 }
}

struct ResumeCardModel {
    let title: String
    let authors: [String]
    let authorIdentities: [AO3AuthorIdentity]
    let fandoms: [String]
    let rating: String
    let categories: [String]
    let warnings: [String]
    let completion: WorkCompletionStatus
    let words: Int?
    let kudos: Int?
    let chapters: String
    let progress: Double?
    let chapterProgress: Double?
    let chapterName: String?
    let published: String
    let updated: String
    let newChapterCount: Int

    init(work: SavedWork) {
        title = work.title
        authors = work.verifiedAuthorIdentities.isEmpty
            ? (work.author.isEmpty ? [] : [work.author])
            : work.verifiedAuthorIdentities.map(\.displayName)
        authorIdentities = work.verifiedAuthorIdentities
        fandoms = work.workFandoms
        rating = work.rating
        categories = work.workCategories
        warnings = work.workWarnings
        completion = work.completionStatus
        words = work.wordCount > 0 ? work.wordCount : nil
        kudos = work.kudos > 0 ? work.kudos : nil
        chapters = work.chapters
        progress = work.readingProgress.map { min(max($0, 0), 1) }
        chapterProgress = WorkReadingPosition.chapterProgress(from: work.readiumLocator)
        chapterName = WorkReadingPosition.title(from: work.readiumLocator)
        published = work.datePublished
        updated = work.dateUpdated
        newChapterCount = max(0, work.postedChapterCount - work.knownChapterCount)
    }

    init(
        title: String,
        authors: [String],
        authorIdentities: [AO3AuthorIdentity],
        fandoms: [String],
        rating: String,
        categories: [String],
        warnings: [String],
        completion: WorkCompletionStatus,
        words: Int?,
        kudos: Int?,
        chapters: String,
        progress: Double?,
        chapterProgress: Double?,
        chapterName: String?,
        published: String,
        updated: String,
        newChapterCount: Int
    ) {
        self.title = title
        self.authors = authors
        self.authorIdentities = authorIdentities
        self.fandoms = fandoms
        self.rating = rating
        self.categories = categories
        self.warnings = warnings
        self.completion = completion
        self.words = words
        self.kudos = kudos
        self.chapters = chapters
        self.progress = progress.map { min(max($0, 0), 1) }
        self.chapterProgress = chapterProgress.map { min(max($0, 0), 1) }
        self.chapterName = chapterName
        self.published = published
        self.updated = updated
        self.newChapterCount = max(0, newChapterCount)
    }

    var art: CoverArt.WorkArt { CoverArt.workArt(fandoms: fandoms, title: title) }

    var primaryFandom: String? {
        fandoms.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(FandomDisplayName.bareTitle)
    }

    var workPercent: Int { Int(((progress ?? 0) * 100).rounded()) }
    var chapterPercent: Int { Int(((chapterProgress ?? 0) * 100).rounded()) }
    var postedChapters: Int { SavedWork.postedChapterCount(from: chapters) }
    var plannedChapters: Int {
        max(SavedWork.totalChapterCount(from: chapters) ?? postedChapters, postedChapters)
    }

    var chapterNumber: Int {
        if let chapterName,
           let match = chapterName.range(
               of: #"(?i)\bch(?:apter)?\s*(\d+)"#,
               options: .regularExpression
           ),
           let number = Int(chapterName[match].filter(\.isNumber)) {
            return number
        }
        return ChapterBarGeometry.readingChapter(
            posted: postedChapters,
            progress: progress ?? 0,
            weights: nil
        )
    }

    var displayedChapterName: String { chapterName ?? "Chapter \(chapterNumber)" }

    var postedLabel: String {
        guard plannedChapters > 0 else { return chapters }
        if plannedChapters == postedChapters {
            return "\(postedChapters) chapter\(postedChapters == 1 ? "" : "s")"
        }
        return "\(postedChapters) of \(plannedChapters) posted"
    }

    var postedShortLabel: String {
        plannedChapters > 0 ? "\(postedChapters) of \(plannedChapters)" : chapters
    }

    var figureLine: String? {
        var parts: [String] = []
        if let words { parts.append("\(words.formatted()) words") }
        if let kudos { parts.append("♥ \(kudos.compactCount)") }
        let text = parts.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    func chapterItems(weights: [Int]?) -> [ChapterBarItem] {
        ChapterBarModel.items(
            chapters: chapters,
            progress: progress,
            isFinished: progress == 1,
            weights: weights
        )
    }
}

struct HomeResumeHero: View {
    let work: SavedWork
    var variant: ResumeCardVariant = .home
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var onSelect: (() -> Void)?
    var onPrimary: (() -> Void)?
    var onReadAloud: (() -> Void)?

    @Environment(PrivacyGate.self) private var gate
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    private var blurred: Bool {
        hideMature && work.isAdult && mode == .obscure && !gate.isRevealed(work)
    }

    var body: some View {
        if blurred {
            ZStack {
                resumeCard(interactive: false)
                    .environment(\.ao3AuthorNavigationEnabled, false)
                    .blur(radius: 6)
                    .allowsHitTesting(false)
                if !isSelecting { MatureRevealCapsule() }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if isSelecting { WorkSelectionBubble(isSelected: isSelected).padding(8) }
            }
            .onTapGesture {
                if isSelecting { onToggleSelection?() } else { gate.reveal(work) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work")
            .accessibilityValue(isSelecting ? (isSelected ? "Selected" : "Not selected") : "")
            .accessibilityHint(isSelecting ? "Double-tap to toggle selection." : "Activate to reveal.")
            .localWorkContextMenu(work: work, onSelect: onSelect)
        } else if isSelecting {
            ZStack {
                resumeCard(interactive: false)
                    .environment(\.ao3AuthorNavigationEnabled, false)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                WorkSelectionBubble(isSelected: isSelected).padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                        lineWidth: 2
                    )
                    .allowsHitTesting(false)
            }
            .onTapGesture { onToggleSelection?() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(work.title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .localWorkContextMenu(work: work, onSelect: onSelect)
        } else {
            resumeCard(interactive: true)
                .localWorkContextMenu(work: work, onSelect: onSelect)
        }
    }

    private func resumeCard(interactive: Bool) -> some View {
        WorkResumeCard(
            model: ResumeCardModel(work: work),
            localWork: work,
            variant: variant,
            primaryLabel: variant == .next ? "Start" : "Resume",
            isBusy: false,
            isInteractive: interactive,
            onPrimary: { onPrimary?() },
            onReadAloud: { onReadAloud?() }
        )
        .workCardZoomSource(work.zoomKey, in: zoomNamespace)
    }
}

struct WorkResumeCard: View {
    let model: ResumeCardModel
    var localWork: SavedWork?
    let variant: ResumeCardVariant
    let primaryLabel: String
    var isBusy = false
    var isInteractive = true
    let onPrimary: () -> Void
    let onReadAloud: () -> Void
    var onContents: (() -> Void)?
    var onUpdate: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accentFill) private var accentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var chapterWeights: [Int]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch variant {
            case .home: homeHeader
            case .next: nextHeader
            case .detail: detailHeader
            }
            chapterSection
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .task(id: chapterCacheKey) { await loadChapterWeights() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var homeHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                progressRing(diameter: 96, showsLabel: true)
                identity
            }
            VStack(alignment: .leading, spacing: 12) {
                progressRing(diameter: 96, showsLabel: true)
                identity
            }
        }
    }

    private var nextHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            identity
        }
    }

    private var detailHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                progressRing(diameter: 52, showsLabel: false)
                detailChapterLabels
                contentsButton
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    progressRing(diameter: 52, showsLabel: false)
                    detailChapterLabels
                }
                contentsButton
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let fandom = model.primaryFandom {
                Text(fandom.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 16, height: 2)
                    .padding(.vertical, 2)
            }
            Text(model.title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            AO3AuthorBylineView(
                names: model.authors,
                identities: model.authorIdentities,
                fallbackText: "Anonymous",
                includesBy: false,
                font: .subheadline,
                tinted: true,
                expandsHitTarget: false
            )
            .tint(.white)
            if let figureLine = model.figureLine {
                Text(figureLine)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailChapterLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.displayedChapterName)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            Text("\(model.chapterPercent)% of the chapter · \(model.workPercent)% of the work")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentsButton: some View {
        Button { if isInteractive { onContents?() } } label: {
            Text(model.postedShortLabel + " ›")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive || onContents == nil)
        .accessibilityLabel("Contents, \(model.postedShortLabel) chapters")
    }

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChapterBars(
                items: model.chapterItems(weights: chapterWeights),
                scale: .card,
                onGradient: true,
                height: variant.barsHeight
            )
            if variant == .detail {
                chapterLegend
                if !model.published.isEmpty || !model.updated.isEmpty {
                    Text(detailDates)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.displayedChapterName + " · " + model.postedLabel)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !model.updated.isEmpty { Text("Updated \(model.updated)").lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }

    private var chapterLegend: some View {
        HStack(spacing: 14) {
            legendItem("Read", fill: .white)
            legendItem("Posted, unread", fill: Color.white.opacity(0.3))
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                    .frame(width: 10, height: 10)
                Text("Not posted yet")
            }
        }
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.9))
    }

    private func legendItem(_ title: String, fill: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 10, height: 10)
            Text(title)
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionContents }
            VStack(alignment: .leading, spacing: 10) { actionContents }
        }
    }

    @ViewBuilder
    private var actionContents: some View {
        if variant != .detail {
            WorkStatusIconGrid(
                rating: model.rating.isEmpty ? nil : model.rating,
                categories: model.categories,
                warnings: model.warnings,
                completion: model.completion,
                tileSize: 24,
                announcesToVoiceOver: true,
                arrangement: .strip
            )
            Spacer(minLength: 0)
        }
        actionCircle(title: "Read Aloud", systemImage: "speaker.wave.2.fill", action: onReadAloud)
        primaryButton
        if variant == .detail, model.newChapterCount > 0, let onUpdate {
            ZStack(alignment: .topTrailing) {
                actionCircle(title: "Update download", systemImage: "arrow.down", action: onUpdate)
                Text("\(model.newChapterCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(accentFill, in: Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 2, y: -2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var primaryButton: some View {
        Button { if isInteractive { onPrimary() } } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(accentFill)
                } else {
                    Image(systemName: "play.fill").font(.caption)
                }
                Text(variant == .detail ? "Resume Chapter \(model.chapterNumber)" : primaryLabel)
                    .lineLimit(1)
            }
            .font(.headline)
            .foregroundStyle(accentFill)
            .frame(maxWidth: variant == .detail ? .infinity : nil)
            .frame(height: variant.primaryHeight)
            .padding(.horizontal, variant == .detail ? 16 : 22)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive || isBusy)
    }

    private func actionCircle(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button { if isInteractive { action() } } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: variant.primaryHeight, height: variant.primaryHeight)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel(title)
    }

    private func progressRing(diameter: CGFloat, showsLabel: Bool) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.24), lineWidth: showsLabel ? 10 : 6)
            Circle()
                .trim(from: 0, to: model.progress ?? 0)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: showsLabel ? 10 : 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsLabel {
                VStack(spacing: 0) {
                    Text("\(model.workPercent)%")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Read").font(.caption2.weight(.semibold)).textCase(.uppercase)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.workPercent) percent read")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
            .fill(CoverArt.workGradient(for: model.art))
            .overlay(alignment: .bottomTrailing) {
                Text(model.title.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "")
                    .font(.system(size: 250, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.08))
                    .offset(x: 10, y: 58)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(
                color: themeManager.appTheme.carouselCardShadow.color,
                radius: themeManager.appTheme.carouselCardShadow.radius + 6,
                x: 0,
                y: themeManager.appTheme.carouselCardShadow.y + 2
            )
    }

    private var detailDates: String {
        var parts: [String] = []
        if !model.published.isEmpty { parts.append("Published \(model.published)") }
        if !model.updated.isEmpty { parts.append("updated \(model.updated)") }
        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let prefix = variant == .next
            ? "Up next"
            : variant == .detail ? "Your reading" : "Continue reading"
        return "\(prefix): \(model.title), \(model.workPercent) percent read"
    }

    private var chapterCacheKey: String {
        guard let localWork, localWork.hasEPUB else { return "none" }
        let values = try? localWork.fileURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        return "\(localWork.id)-\(values?.fileSize ?? -1)-"
            + "\(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)"
    }

    private func loadChapterWeights() async {
        guard let localWork, localWork.hasEPUB else {
            chapterWeights = nil
            return
        }
        let id = localWork.id
        let url = localWork.fileURL
        let weights = await Task.detached(priority: .utility) {
            ChapterLengthCache.weights(workID: id, fileURL: url)
        }.value
        guard localWork.modelContext != nil else { return }
        chapterWeights = weights
    }
}

/// The same hero and next four works, composed only when their measured region
/// fits. Privacy, navigation and selection remain with the original card views.
struct HomeResumeComposition<Hero: View, Next: View>: View {
    let hasNext: Bool
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var next: () -> Next
    @Environment(\.dashboardContentRegions) private var regions
    @Environment(\.layoutDirection) private var direction
    private var cardSize = ScaledCarouselCardSize()

    var body: some View {
        #if os(iOS)
        if let regions, let panes = regions.resumePanes(
            hasNext: hasNext,
            cardWidth: cardSize.width(in: nil),
            rightToLeft: direction == .rightToLeft
        ) {
            DashboardRegionRow(panes: panes, width: regions.viewport.width) {
                hero().padding(.horizontal, 16)
                if hasNext, panes.count > 1 {
                    DashboardCardShelf(groupsInSinglePane: true) { next() }
                        .environment(\.dashboardContentRegions, AdaptiveContentRegions(
                            bounds: CGRect(origin: .zero, size: panes[1].size)
                        ))
                }
            }
        } else {
            compactContent
        }
        #else
        compactContent
        #endif
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            hero().padding(.horizontal, 16)
            if hasNext {
                DashboardCardShelf { next() }
                    .padding(.top, -8)
            }
        }
    }
}
