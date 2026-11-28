import SwiftData
import SwiftUI

/// Artboard **1j**'s "New Queue" sheet — shared by Home, the queue organizer
/// (`AllReadingQueuesGridView`) and the per-queue browser
/// (`ReadingQueueBrowserView`), which each opened their own near-identical
/// plain `Form` before this.
///
/// **The colour swatches are built.** They were not, and the note that used to
/// sit here explained why: 1j wants a colour "set once instead of derived from
/// the name", every queue's colour was `CoverArt.hue(for: queue.displayName)`,
/// and storing one independently "would be a schema change, not a restyle".
/// That was the right call for a restyling task. `ReadingQueue.hue` is that
/// schema change, made by the sweep that was chartered for missing
/// functionality rather than layout, and it fixes a real defect on the way:
/// renaming a queue used to silently repaint it.
///
/// **Start from is a radio list, not a segmented pair.** The spec's own
/// one-grammar-per-choice rule sends a two-way choice to a segmented control,
/// and 1j draws two radio rows instead — so the board wins, and for a reason
/// that shows: its second row carries its own subtitle, "Copy all 12, leaving
/// them saved". A segmented pair has nowhere to put the count, and the count is
/// the thing a reader needs to decide. `savedForLaterSeedCount` reads it without
/// writing, and the row is disabled at zero rather than offering a choice that
/// would silently produce an empty queue — the same call `NewQueueSeed` already
/// made about seeding from a fandom.
///
/// **Tags and the swatch-following wash are built.** Tags are chosen here as
/// names and written by `ReadingQueueService.createQueue` through
/// `ReadingQueue.addTag`, the same lookup-before-create `QueueTagSheet` uses, so
/// nothing is created until Create. The wash follows the queue hue; controls
/// use the app tint.
///
/// **The colour row ends in the "More colours" well** (`SubjectHueSwatchRow`):
/// any colour, stored exactly as `ReadingQueue.colorHex` (`options.colorHex`
/// here) with its hue in `hue` beside it. A preset clears the hex.
///
/// **Edit Queue is this sheet too** (`EditReadingQueueSheet`, owner request
/// 2026-10-01): the same fields over an existing queue, saved rather than
/// created. Start from is left out — seeding only means something for a queue
/// that does not exist yet.
///
/// Header chrome matches board 05 (and `WorkEditView` / board 42): circular
/// `xmark` dismiss via `ToolbarIconButton` on the leading edge and a filled
/// primary action pill styled with `sheetConfirmStyle()` on the confirmation edge.
struct NewReadingQueueSheet: View {
    @Binding var name: String
    /// 1j: the colour is chosen before the name is typed, so it is committed with
    /// the queue rather than set afterwards. `nil` keeps the name-derived hue.
    @Binding var hue: Double?
    /// Owned by the sheet rather than the three hosts: they each held `name` and
    /// `hue` already, and two more bindings apiece would be three identical
    /// copies of state that only this sheet reads.
    /// Returns whether the queue was saved: false keeps the sheet open and says so.
    let onCreate: (NewQueueOptions) -> Bool
    let onCancel: () -> Void
    /// Edit Queue: title and confirm read "Edit queue" / "Save", and Start
    /// from is left out. Set through `init(name:hue:editing:onSave:onCancel:)`.
    var isEditing = false
    var editingQueue: ReadingQueue?

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(sort: \SavedSearch.name) private var savedSearches: [SavedSearch]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.title)
    private var libraryWorks: [SavedWork]
    @Query private var tagAliases: [TagAlias]
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var options = NewQueueOptions()
    /// Create only. Editing never converts a list into a smart queue.
    @State private var queueStyle = NewQueueDraftKind.list
    @State private var smartDocument = SmartQueueDocument.starter
    @State private var editingRule: SmartQueueRuleEditTarget?
    @State private var deletedRuleFallback: SmartQueueDocument.Rule?
    /// Set when the stored JSON does not decode. Save keeps that string.
    @State private var rulesUnreadable = false
    @State private var preservedRulesJSON: String?
    @State private var showingNewTag = false
    @State private var newTagName = ""
    /// Read once when the sheet appears rather than in `body`: the sheet is
    /// modal, so nothing can change the count while it is open, and counting
    /// memberships on every body evaluation would walk the whole shelf.
    @State private var seedCount: Int?
    @State private var saveFailed = false
    @State private var showingAddWorks = false
    @State private var showingSourcePicker = false
    @State private var colorWellSession = CustomColorWellSession()

    @ScaledMetric(relativeTo: .subheadline) private var nameFieldSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var seedTitleSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .caption) private var seedSubtitleSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var gutter: CGFloat { SubjectMetrics.gutter }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 1j: "The sheet takes a wash in whichever swatch you tap". Untapped, it
    /// keeps the app's own accent.
    private var palette: SubjectPalette {
        hue.map { theme.appTheme.subjectPalette(hue: $0, pickedHex: options.colorHex) } ?? theme.scopePalette
    }

    var body: some View {
        NavigationStack {
            List {
                if !isEditing {
                    kindSection
                }
                if showsSmartEditor {
                    smartEditorContent
                } else if isEditing {
                    editListQueueContent
                } else {
                    createListQueueContent
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle(sheetTitle)
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .wrappingInlineTitle(
                    sheetTitle,
                    isActive: dynamicTypeSize.isAccessibilitySize
                )
                .subjectScreenWash(palette: palette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ToolbarIconButton(
                            title: "Cancel",
                            systemImage: "xmark",
                            tint: .primary
                        ) {
                            colorWellSession.discard()
                            onCancel()
                        }
                        .labelStyle(.iconOnly)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmTitle) {
                            colorWellSession.flush()
                            if !onCreate(submittedOptions) { saveFailed = true }
                        }
                        .sheetConfirmStyle()
                        .disabled(trimmedName.isEmpty)
                    }
                }
                .environment(\.customColorWellSession, colorWellSession)
                .navigationDestination(item: $editingRule) { target in
                    let aliases = tagAliasResolver
                    SmartQueueRuleEditor(
                        rule: ruleBinding(for: target),
                        fandoms: fandomChoices(aliases: aliases),
                        aliases: aliases,
                        onDelete: {
                            deletedRuleFallback = smartDocument.rules.first { $0.id == target.id }
                                ?? target.fallback
                            smartDocument.rules.removeAll { $0.id == target.id }
                        }
                    )
                }
        }
        // Controls use the app tint; the queue hue belongs to its cover and wash.
        .screenTint(theme.scopePalette)
        #if os(iOS)
        // Taller than .medium now: 1j's sheet carries four groups, and a medium
        // detent hid the seed step below the fold — the one decision the board
        // says you never actually want to miss.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            guard !isEditing else { return }
            seedCount = ReadingQueueService.savedForLaterSeedCount(in: context)
        }
        .alert("New tag", isPresented: $showingNewTag) {
            TextField("Tag", text: $newTagName)
            Button("Add", action: addNewTag)
            Button("Cancel", role: .cancel) {}
        }
        // Android's words. The sheet stays, holding what was typed, so Save can be tried again.
        .alert("Could not save", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The queue wasn't saved. Try again.")
        }
        .sheet(isPresented: $showingAddWorks) {
            AddLibraryWorksSheet(
                destinationName: previewName,
                scopeName: "queue",
                candidates: { $0.filter { !$0.isQueueOnlyWork } },
                onAdd: { options.seedWorkIDs = $0.map(\.id) },
                initialSelection: Set(options.seedWorkIDs)
            )
        }
        .sheet(isPresented: $showingSourcePicker) {
            AddQueueSourceSheet(
                queueName: previewName,
                existingSearchIDs: Set(options.searchIDs),
                existingSourceKeys: Set(options.sources.map(\.dedupKey)),
                onAddSearch: { search in
                    if !options.searchIDs.contains(search.id) {
                        options.searchIDs.append(search.id)
                    }
                },
                onAddSource: { draft in
                    if !options.sources.contains(where: { $0.dedupKey == draft.dedupKey }) {
                        options.sources.append(draft)
                    }
                    options.syncsNonSearchSources = true
                }
            )
            #if os(iOS)
            .modifier(ScopeSurfaceAccent())
            #endif
        }
    }

    /// Placeholder until a name is typed. Create stays disabled while it is empty.
    private var previewName: String {
        trimmedName.isEmpty ? "New Queue" : trimmedName
    }

    /// Works the sheet will add, in the order they were picked.
    private var seedWorks: [SavedWork] {
        let byID = Dictionary(libraryWorks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return options.seedWorkIDs.compactMap { byID[$0] }
    }

    static func coverIdentity(for editingQueue: ReadingQueue?, options: NewQueueOptions) -> UUID {
        editingQueue?.id ?? options.draftID
    }

    static func previewCoverFace(
        name: String,
        identity: UUID,
        hue: Double?,
        pickedHex: String?,
        width: CGFloat = 88,
        height: CGFloat = 120
    ) -> CoverStackNameFace {
        CoverStackNameFace(
            kind: .queue,
            name: name,
            identity: identity,
            hue: hue,
            pickedHex: pickedHex,
            coverWidth: width,
            coverHeight: height
        )
    }

    private var coverWorks: [SavedWork] {
        if let editingQueue {
            return ReadingQueueService.orderedMemberships(in: editingQueue).compactMap(\.work)
        }
        return seedWorks
    }

    private var coverPreview: some View {
        let works = coverWorks
        let backs = works
            .filter { !gate.isConcealed($0, enabled: hideMature) }
            .prefix(CoverStackLayout.maxBacks)
        let subtitle = ReadingQueueFacts.previewSubtitle(for: works)
        let identity = Self.coverIdentity(for: editingQueue, options: options)
        return VStack(spacing: 8) {
            StackedWorkCover(
                kind: .queue,
                size: CGSize(width: 76, height: 76),
                backs: Array(backs)
            ) { layout in
                Self.previewCoverFace(
                    name: previewName,
                    identity: identity,
                    hue: hue,
                    pickedHex: options.colorHex,
                    width: layout.front.width,
                    height: layout.front.height
                )
            }
            VStack(spacing: 1) {
                Text(previewName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview, \(previewName), \(subtitle)")
    }

    private var addWorksRow: some View {
        Button {
            showingAddWorks = true
        } label: {
            HStack(spacing: 12) {
                Text(options.seedWorkIDs.isEmpty
                    ? "Choose Works"
                    : "\(options.seedWorkIDs.count) selected")
                    .font(.system(size: seedTitleSize))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.effectiveTint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .queueFormCard(theme: theme.appTheme)
        .accessibilityLabel("Add works")
        .accessibilityValue(options.seedWorkIDs.isEmpty
            ? "None selected"
            : "\(options.seedWorkIDs.count) selected")
        .accessibilityHint("Opens your library to choose works for this queue.")
    }

    /// Every existing tag, then any new names typed here that are not one yet.
    private var tagChoices: [String] {
        allTags.map(\.name) + options.tagNames.filter { !allTags.map(\.name).contains($0) }
    }

    /// A name matching an existing tag or one already picked, ignoring case,
    /// selects that one instead — the same rule `ReadingQueue.addTag` applies.
    private func addNewTag() {
        let typed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let name = tagChoices.first { $0.localizedCaseInsensitiveCompare(typed) == .orderedSame } ?? typed
        if !options.tagNames.contains(name) { options.tagNames.append(name) }
    }

    private var showsSmartEditor: Bool {
        if isEditing { return editingQueue?.kind == .smart }
        return queueStyle == .smart
    }

    private var sheetTitle: String {
        if showsSmartEditor { return "Smart Queue" }
        return isEditing ? "Edit Queue" : "New Queue"
    }

    static func confirmButtonTitle(isEditing: Bool, isSmart: Bool) -> String {
        isSmart || isEditing ? "Save" : "Add"
    }

    private var confirmTitle: String {
        Self.confirmButtonTitle(isEditing: isEditing, isSmart: showsSmartEditor)
    }

    private var submittedOptions: NewQueueOptions {
        guard showsSmartEditor else { return options }
        var submitted = options
        submitted.isSmart = true
        submitted.keepsWorksOffline = false
        submitted.seed = .empty
        submitted.seedWorkIDs = []
        if let queue = editingQueue {
            submitted.tagNames = queue.tags.map(\.name).sorted()
            submitted.searchIDs = queue.savedSearchLinks.compactMap { $0.search?.id }
            submitted.sources = []
            submitted.syncsNonSearchSources = false
            submitted.colorHex = queue.colorHex
        } else {
            submitted.tagNames = []
            submitted.searchIDs = []
            submitted.sources = []
            submitted.syncsNonSearchSources = false
            submitted.colorHex = nil
        }
        if rulesUnreadable {
            submitted.smartRulesJSON = preservedRulesJSON
        } else {
            submitted.smartRulesJSON = SmartQueueRules.encode(smartDocument)
        }
        return submitted
    }

    private var draftKind: Binding<NewQueueDraftKind> {
        Binding(
            get: { queueStyle },
            set: { newValue in
                queueStyle = newValue
                if newValue == .smart {
                    hue = nil
                    options.colorHex = nil
                }
            }
        )
    }

    private var kindSection: some View {
        Section {
            SubjectFormRow(label: "Kind", arrangement: .control) {
                SubjectSegmentedControl(
                    options: NewQueueDraftKind.allCases,
                    title: \.title,
                    selection: draftKind
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kind")
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 8, gutter: gutter)
        }
    }

    @ViewBuilder
    private var smartEditorContent: some View {
        Section {
            groupLabel("Name")
            namePanel(placeholder: "Short and finished").pageBodyRow(top: 6, gutter: gutter)
        }
        if rulesUnreadable {
            Section {
                Text("These rules were saved by a newer version of Kudos and can't be edited here.")
                    .font(.system(size: footnoteSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .pageBodyRow(top: 8, gutter: gutter)
                footnote(Self.smartFootnote)
            }
        } else {
            smartMatchSection
            smartOrderSection
            smartPreviewSection
        }
    }

    private var smartMatchSection: some View {
        Section {
            groupLabel("Works in my library that match")
            VStack(spacing: 0) {
                SubjectFormRow(label: "Match", arrangement: .control) {
                    SubjectSegmentedControl(
                        options: SmartQueueDocument.Match.allCases,
                        title: \.title,
                        selection: $smartDocument.match
                    )
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Match")
                ForEach(smartDocument.rules) { rule in
                    SubjectRowSeparator()
                    Button {
                        deletedRuleFallback = nil
                        editingRule = SmartQueueRuleEditTarget(id: rule.id, fallback: rule)
                    } label: {
                        SubjectFormRow(label: rule.kind.rowLabel, value: rule.summary, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rule.kind.rowLabel), \(rule.summary)")
                }
                SubjectRowSeparator()
                Menu {
                    ForEach(SmartQueueDocument.Rule.Kind.addOrder, id: \.self) { kind in
                        Button(kind.rowLabel) {
                            smartDocument.rules.append(kind.makeDefault())
                        }
                    }
                } label: {
                    Text("Add Rule…")
                        .font(.system(size: seedTitleSize))
                        .foregroundStyle(.accentInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .accessibilityLabel("Add Rule")
            }
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 6, gutter: gutter)
        }
    }

    private func ruleBinding(for target: SmartQueueRuleEditTarget) -> Binding<SmartQueueDocument.Rule> {
        Binding(
            get: {
                smartDocument.rules.first { $0.id == target.id }
                    ?? deletedRuleFallback
                    ?? target.fallback
            },
            set: { updated in
                guard let index = smartDocument.rules.firstIndex(where: { $0.id == target.id }) else { return }
                smartDocument.rules[index] = updated
            }
        )
    }

    private var smartOrderSection: some View {
        Section {
            groupLabel("Order")
            VStack(spacing: 0) {
                Menu {
                    ForEach(SmartQueueDocument.Sort.allCases, id: \.self) { sort in
                        Button(sort.title) { smartDocument.sort = sort }
                    }
                } label: {
                    SubjectFormRow(label: "Sort", value: smartDocument.sort.title, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort, \(smartDocument.sort.title)")
                SubjectRowSeparator()
                Menu {
                    ForEach(Array(SmartQueueDocument.limitChoices.enumerated()), id: \.offset) { _, choice in
                        Button(limitTitle(choice)) { smartDocument.limit = choice }
                    }
                } label: {
                    SubjectFormRow(label: "Limit", value: smartDocument.limitTitle, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limit, \(smartDocument.limitTitle)")
            }
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 6, gutter: gutter)
        }
    }

    private var smartPreviewSection: some View {
        let matched = smartPreviewWorks
        let copy = Self.smartPreviewCopy(for: matched)
        return Section {
            groupLabel("Preview")
            VStack(alignment: .leading, spacing: 4) {
                SubjectFormRow(label: "Matches now", value: copy.count)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Matches now, \(copy.count)")
                if !copy.detail.isEmpty {
                    Text(copy.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 6, gutter: gutter)
            footnote(Self.smartFootnote)
        }
    }

    private func limitTitle(_ limit: Int?) -> String {
        guard let limit, limit > 0 else { return "No limit" }
        return limit == 1 ? "1 work" : "\(limit.formatted()) works"
    }

    private var tagAliasResolver: TagAliasResolver {
        TagAliasResolver(models: tagAliases)
    }

    /// Excludes concealed mature works so Blur/Hide never leak fandoms, and
    /// unifies learned T-518 aliases under their canonical AO3 name.
    private func fandomChoices(aliases: TagAliasResolver) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for work in libraryWorks where !work.isQueueOnlyWork && !gate.isConcealed(work, enabled: hideMature) {
            for fandom in work.workFandoms {
                let resolved = aliases.resolveIgnoringCase(fandom, kind: .fandom)
                guard !resolved.isEmpty, seen.insert(resolved.lowercased()).inserted else { continue }
                names.append(resolved)
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Applies Hide Mature before `limit`, matching the smart queue page so
    /// hidden works never consume limit slots and shrink "Matches now".
    private var smartPreviewWorks: [SavedWork] {
        let eligible = libraryWorks.filter {
            !$0.isQueueOnlyWork && !gate.isHidden($0, enabled: hideMature, mode: matureMode)
        }
        let facts = eligible.map(SmartQueueWorkFacts.init(work:))
        let ordered = smartDocument.matching(facts, aliases: tagAliasResolver)
        let byID = Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ordered.compactMap { byID[$0.id] }
    }

    /// Preview copy for Smart Queue (`Queue-Smart.dc.html`): `"12 works"` and
    /// `"About 3 h 10 min · 9 offline"`.
    static func smartPreviewCopy(
        for works: [SavedWork],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> (count: String, detail: String) {
        let count = works.count == 1 ? "1 work" : "\(works.count.formatted()) works"
        guard !works.isEmpty else { return (count, "") }
        let facts = ReadingQueueFacts.planFacts(for: works, fileExists: fileExists)
        let parts = facts.split(separator: " · ").map(String.init)
        let detail = ReadingQueueFacts.capitalizedSentenceStart(parts.dropFirst().joined(separator: " · "))
        return (count, detail)
    }

    static let smartFootnote = "A smart queue updates itself as your library changes. "
        + "A work leaves when it stops matching, for example when you finish it."

    private func groupLabel(_ text: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
            if let trailing, !trailing.isEmpty {
                Spacer(minLength: 8)
                Text(trailing)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .pageBodyRow(top: 14, gutter: gutter)
    }

    /// Name field alone under its header (Edit Queue and Smart Queue).
    private func namePanel(placeholder: String = "Autumn Rereads") -> some View {
        TextField(placeholder, text: $name)
            // The title doubles as the accessibility label, so without this
            // VoiceOver reads the example placeholder as if it were the name.
            .accessibilityLabel("Name")
            .font(.system(size: nameFieldSize))
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            // Return creates too, so it reports a failed save the same way; an empty name
            // does nothing, as the disabled confirm button.
            .onSubmit {
                guard !trimmedName.isEmpty else { return }
                colorWellSession.flush()
                if !onCreate(submittedOptions) { saveFailed = true }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .queueFormCard(theme: theme.appTheme)
    }

    private var offlinePanel: some View {
        SubjectFormRow(label: "Keep works offline", arrangement: .control) {
            // Titled even though the title is hidden: `labelsHidden` hides it
            // from the eye, not from VoiceOver, and an empty title left the
            // switch announcing only "switch button, off".
            Toggle("Keep works offline", isOn: $options.keepsWorksOffline).labelsHidden().accentFill()
        }
        .queueFormCard(theme: theme.appTheme)
    }

    /// Board `Queues.dc.html` copy for Keep works offline when the toggle is on
    /// (`KeepOffline`, `SavedWork.isKeptOffline`). The off sentence is the other
    /// state: the board draws the switch on, so its line is not true when it is off.
    static let offlineFootnote = "Kudos downloads each work you add and keeps it while it's in this queue."

    static let offlineOffFootnote = "When this is off, the queue keeps only your list and uses no extra storage."

    static func offlineFootnote(keepsWorksOffline: Bool) -> String {
        keepsWorksOffline ? offlineFootnote : offlineOffFootnote
    }

    private var seedPanel: some View {
        VStack(spacing: 0) {
            seedRow(.empty)
            SubjectRowSeparator(inset: 43)
            seedRow(.savedForLater)
        }
        .queueFormCard(theme: theme.appTheme)
    }

    @ViewBuilder
    private func seedRow(_ seed: NewQueueSeed) -> some View {
        let isSelected = options.seed == seed
        let isDisabled = seed == .savedForLater && seedCount == 0
        Button {
            options.seed = seed
        } label: {
            HStack(spacing: 11) {
                radioMark(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(seed.title)
                        .font(.system(size: seedTitleSize))
                    if let subtitle = seedSubtitle(seed) {
                        Text(subtitle)
                            .font(.system(size: seedSubtitleSize))
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(seed.title)
        // The subtitle carries the count — the thing this row exists to show —
        // and the only reason a disabled row is disabled; the label override
        // above would otherwise drop both for VoiceOver.
        .accessibilityValue(seedSubtitle(seed) ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func radioMark(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(
                isSelected ? theme.effectiveTint : Color.secondary.opacity(0.4),
                lineWidth: 1.6
            )
            .frame(width: 19, height: 19)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(theme.effectiveTint)
                        .frame(width: 9, height: 9)
                }
            }
    }

    /// The count is 1j's own ("Copy all 12, leaving them saved") and the reason
    /// this is a list rather than a segmented pair. `nil` while the count is
    /// still being read, so the row never flashes a figure it has to correct.
    private func seedSubtitle(_ seed: NewQueueSeed) -> String? {
        switch seed {
        case .empty:
            // 1j gives Empty no subtitle: the word says it.
            return nil
        case .savedForLater:
            guard let seedCount else { return nil }
            guard seedCount > 0 else { return "You have no works in Want to Read to copy." }
            return "Copy \(seedCount) work\(seedCount == 1 ? "" : "s"). They stay in Want to Read."
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .pageBodyRow(top: 6, gutter: gutter)
    }
}

/// Create and Edit list-queue sections (`Queues.dc.html`, `Queue-Edit.dc.html`), split
/// into an extension to keep `NewReadingQueueSheet`'s main body concise.
extension NewReadingQueueSheet {
    @ViewBuilder
    private var createListQueueContent: some View {
        Section {
            coverPreview.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            VStack(spacing: 0) {
                nameInlineRow
                SubjectRowSeparator(inset: 16)
                colourInlineRow
                SubjectRowSeparator(inset: 16)
                tagsInlineRow
            }
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 14, gutter: gutter)
        }

        Section {
            offlinePanel.pageBodyRow(top: 14, gutter: gutter)
            footnote(Self.offlineFootnote(keepsWorksOffline: options.keepsWorksOffline))
        }

        Section {
            groupLabel("Start from")
            seedPanel.pageBodyRow(top: 6, gutter: gutter)
        }

        Section {
            groupLabel(
                "Add works",
                trailing: options.seedWorkIDs.isEmpty ? nil : "\(options.seedWorkIDs.count) selected"
            )
            addWorksRow.pageBodyRow(top: 6, gutter: gutter)
            footnote("Chosen from your library. They are added when you create the queue.")
        }
    }

    @ViewBuilder
    private var editListQueueContent: some View {
        let works = coverWorks
        let offlineWorks = works.filter {
            $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path)
        }
        let offlineBytes = offlineWorks.reduce(Int64(0)) { $0 + queueWorkFileSize($1.fileURL) }

        Section {
            QueueContextCard(
                name: previewName,
                identity: Self.coverIdentity(for: editingQueue, options: options),
                hue: hue,
                pickedHex: options.colorHex,
                works: works,
                offlineCount: offlineWorks.count,
                isUserQueue: editingQueue?.isUserQueue ?? true
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            groupLabel("Name")
            namePanel(placeholder: "Summer Reading").pageBodyRow(top: 6, gutter: gutter)
        }

        Section {
            VStack(spacing: 0) {
                colourInlineRow
                SubjectRowSeparator(inset: 16)
                tagsInlineRow
            }
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 14, gutter: gutter)
        }

        editSourcesSection

        Section {
            groupLabel("Offline")
            editOfflinePanel(
                offlineCount: offlineWorks.count,
                totalCount: works.count,
                byteCount: offlineBytes
            )
            .pageBodyRow(top: 6, gutter: gutter)
            footnote(Self.offlineFootnote(keepsWorksOffline: options.keepsWorksOffline))
        }
    }

    private var nameInlineRow: some View {
        let field = TextField("Autumn Rereads", text: $name)
            .accessibilityLabel("Name")
            .font(.system(size: nameFieldSize))
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            .onSubmit {
                guard !trimmedName.isEmpty else { return }
                colorWellSession.flush()
                if !onCreate(submittedOptions) { saveFailed = true }
            }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    field
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text("Name")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 70, alignment: .leading)
                        .accessibilityHidden(true)
                    field
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    }

    private var colourInlineRow: some View {
        let swatches = SubjectHueSwatchRow(selection: $hue, pickedHex: $options.colorHex)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        swatches
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Colour")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .frame(minWidth: 70, alignment: .leading)
                        swatches
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Colour")
                            .font(.callout)
                            .foregroundStyle(.primary)
                        swatches
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }

    private var tagsInlineRow: some View {
        let content = FlowLayout(spacing: 8, rowSpacing: 6) {
            ForEach(options.tagNames, id: \.self) { tagName in
                Button {
                    options.tagNames.removeAll { $0 == tagName }
                } label: {
                    Text(tagName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .frame(minHeight: 30)
                        .background(
                            theme.appTheme.glassFill(0.10),
                            in: SubjectMetrics.controlShape(dynamicTypeSize)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(tagName)")
            }
            addTagControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    content
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text("Tags")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 70, alignment: .leading)
                    content
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    }

    @ViewBuilder
    private var addTagControl: some View {
        if tagChoices.isEmpty {
            Button {
                newTagName = ""
                showingNewTag = true
            } label: {
                Text("Add…")
                    .font(.subheadline)
                    .foregroundStyle(.accentInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Add tag")
        } else {
            Menu {
                ForEach(tagChoices, id: \.self) { tagName in
                    let isOn = options.tagNames.contains(tagName)
                    Button {
                        if isOn {
                            options.tagNames.removeAll { $0 == tagName }
                        } else {
                            options.tagNames.append(tagName)
                        }
                    } label: {
                        if isOn {
                            Label(tagName, systemImage: "checkmark")
                        } else {
                            Text(tagName)
                        }
                    }
                }
                Divider()
                Button {
                    newTagName = ""
                    showingNewTag = true
                } label: {
                    Label("New Tag…", systemImage: "plus")
                }
            } label: {
                Text("Add…")
                    .font(.subheadline)
                    .foregroundStyle(.accentInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .minimumHitTarget()
            .accessibilityLabel("Add tag")
        }
    }

    private var editSourcesSection: some View {
        let linkedSearches = savedSearches.filter { options.searchIDs.contains($0.id) }
        return Section {
            groupLabel("Find More")
            VStack(spacing: 0) {
                ForEach(Array(linkedSearches.enumerated()), id: \.element.id) { index, search in
                    if index > 0 { SubjectRowSeparator(inset: 52) }
                    HStack(spacing: 12) {
                        QueueSourceIconTile(symbolName: QueueSourceKind.savedSearch.symbolName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(search.name)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Saved search")
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Remove \(search.name)", systemImage: "minus.circle") {
                            options.searchIDs.removeAll { $0 == search.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .minimumHitTarget()
                        .foregroundStyle(.accentInk)
                        .accessibilityLabel("Remove saved search \(search.name) from queue")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                ForEach(Array(options.sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 || !linkedSearches.isEmpty { SubjectRowSeparator(inset: 52) }
                    HStack(spacing: 12) {
                        QueueSourceIconTile(symbolName: source.kind.symbolName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.displayName)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(source.subtitle ?? source.kind.kindLabel)
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Remove \(source.displayName)", systemImage: "minus.circle") {
                            options.sources.removeAll { $0.dedupKey == source.dedupKey }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .minimumHitTarget()
                        .foregroundStyle(.accentInk)
                        .accessibilityLabel(
                            "Remove \(source.kind.kindLabel.lowercased()) \(source.displayName) from queue"
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                if !linkedSearches.isEmpty || !options.sources.isEmpty {
                    SubjectRowSeparator(inset: 14)
                }
                Button {
                    showingSourcePicker = true
                } label: {
                    Text("Add a Source…")
                        .font(.system(size: seedTitleSize))
                        .foregroundStyle(.accentInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a source to this queue")
            }
            .queueFormCard(theme: theme.appTheme)
            .pageBodyRow(top: 6, gutter: gutter)
            footnote(
                "Kudos checks a source when you open this queue. "
                    + "Nothing is fetched in the background."
            )
        }
    }

    private func editOfflinePanel(offlineCount: Int, totalCount: Int, byteCount: Int64) -> some View {
        let subtitle = ReadingQueueFacts.offlineDownloadSubtitle(
            offlineCount: offlineCount,
            totalCount: totalCount,
            byteCount: byteCount
        )
        let labelStack = VStack(alignment: .leading, spacing: 2) {
            Text("Keep works offline")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        let toggle = Toggle("Keep works offline", isOn: $options.keepsWorksOffline)
            .labelsHidden()
            .accentFill()
            // Hint, not value: a toggle's value is On or Off, and replacing it
            // would hide which way the switch sits.
            .accessibilityHint(subtitle ?? "")
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        QueueSourceIconTile(symbolName: "arrow.down", fill: .indigo)
                        labelStack
                    }
                    toggle
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    QueueSourceIconTile(symbolName: "arrow.down", fill: .indigo)
                    labelStack
                    Spacer(minLength: 8)
                    toggle
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .queueFormCard(theme: theme.appTheme)
    }
}

private extension View {
    func queueFormCard(theme: ReaderTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return background(shape.fill(theme.cardSurface))
            .overlay(shape.strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }
}

extension NewReadingQueueSheet {
    /// Edit Queue: the sheet seeded with what the queue already has.
    init(
        name: Binding<String>,
        hue: Binding<Double?>,
        editing options: NewQueueOptions,
        queue: ReadingQueue,
        onSave: @escaping (NewQueueOptions) -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.init(name: name, hue: hue, onCreate: onSave, onCancel: onCancel)
        isEditing = true
        editingQueue = queue
        _options = State(initialValue: options)
        guard queue.kind == .smart else { return }
        if let json = queue.smartRulesJSON, let decoded = SmartQueueRules.decode(json) {
            _smartDocument = State(initialValue: decoded)
        } else if queue.smartRulesJSON != nil {
            _rulesUnreadable = State(initialValue: true)
            _preservedRulesJSON = State(initialValue: queue.smartRulesJSON)
        }
    }
}

/// "Edit Queue" in the queue's menu and the organizer's swipe — it took
/// Rename's place, since the name is one of its fields. Owns its draft, so
/// nothing is written until Save.
struct EditReadingQueueSheet: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hue: Double?

    init(queue: ReadingQueue) {
        self.queue = queue
        _name = State(initialValue: queue.name)
        _hue = State(initialValue: queue.hue)
    }

    static func editOptions(for queue: ReadingQueue) -> NewQueueOptions {
        NewQueueOptions(
            keepsWorksOffline: queue.kind == .smart ? false : KeepOffline.queueKeeps(queue.keepsWorksOffline),
            tagNames: queue.tags.map(\.name).sorted(),
            colorHex: queue.colorHex,
            searchIDs: queue.savedSearchLinks.compactMap { $0.search?.id },
            sources: (queue.authorAndSeriesSources + queue.tagSources).compactMap(\.sourceDraft),
            syncsNonSearchSources: queue.kind != .smart,
            draftID: queue.id,
            isSmart: queue.kind == .smart,
            smartRulesJSON: queue.smartRulesJSON
        )
    }

    var body: some View {
        NewReadingQueueSheet(
            name: $name,
            hue: $hue,
            editing: Self.editOptions(for: queue),
            queue: queue,
            onSave: { options in
                let offlineTurnedOn = ReadingQueueService.updateQueue(
                    queue, name: name, hue: hue, options: options, in: context
                )
                // `updateQueue` saved best-effort; this asks whether that stuck (a no-op when
                // it did). Unsaved, the edit is undone on the queue and the sheet keeps it.
                guard context.saveBestEffort(reason: "Saving queue changes failed") else {
                    context.rollback()
                    return false
                }
                if offlineTurnedOn {
                    ReadingQueueService.preserveMissingWorks(in: queue, context: context)
                }
                dismiss()
                return true
            },
            onCancel: { dismiss() }
        )
    }
}

/// 1j's "Start from". Two cases, because those are the two the app can honour:
/// the board also imagines seeding from a fandom, which needs the featured-fandom
/// parse 1g describes and this app does not have. Offering a third option that
/// silently produced an empty queue would be worse than not offering it.
nonisolated enum NewQueueSeed: String, CaseIterable, Identifiable, Sendable {
    case empty
    case savedForLater

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: "Empty"
        case .savedForLater: "Want to Read"
        }
    }
}

/// What the sheet collects beyond name and colour.
nonisolated struct NewQueueOptions: Equatable, Sendable {
    /// 1j draws it on: a new queue keeps its works, as queues always have.
    var keepsWorksOffline = true
    var seed: NewQueueSeed = .empty
    /// Tag names, resolved to `Tag`s only when the queue is created.
    var tagNames: [String] = []
    /// The exact well colour (`ReadingQueue.colorHex`); the hue travels in the
    /// sheet's `hue` binding beside it.
    var colorHex: String?
    /// Library works to add when the queue is created, in pick order.
    /// Edit Queue leaves this empty: seeding only means something for a queue
    /// that does not exist yet.
    var seedWorkIDs: [UUID] = []
    var searchIDs: [UUID] = []
    /// Non-search sources (author, series, tag) edited in Edit Queue.
    var sources: [QueueSourceDraft] = []
    /// Set by Edit Queue so `updateQueue` reconciles `sources` only when the
    /// caller actually loaded and edited them.
    var syncsNonSearchSources = false
    /// Stable draft identity made when New Queue opens so its preview cover
    /// matches the created queue; Edit Queue passes the existing queue's id.
    var draftID = UUID()
    /// Create chooses this. Edit never converts a list queue into a smart one.
    var isSmart = false
    /// Encoded `SmartQueueDocument`. `nil` on a list queue.
    var smartRulesJSON: String?
}

/// Create-only choice on the New Queue sheet. The board draws the smart form;
/// this is how that form is reached. Editing does not offer it.
enum NewQueueDraftKind: String, CaseIterable, Hashable, Identifiable {
    case list
    case smart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .smart: "Smart"
        }
    }
}

/// Pushed editor target for `.navigationDestination(item:)`, carrying a
/// fallback snapshot so deleting the rule mid-pop cannot subscript out of bounds.
private struct SmartQueueRuleEditTarget: Hashable {
    let id: UUID
    let fallback: SmartQueueDocument.Rule
}
