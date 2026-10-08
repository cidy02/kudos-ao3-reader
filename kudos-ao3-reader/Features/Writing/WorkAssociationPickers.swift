import SwiftUI

// MARK: - Collections and gifts (artboard 1bw, first screen)

/// Artboard **1bw** — the two screens Work Edit's Association group pushes to.
///
/// Both were rows with a disclosure chevron and no destination: `associationPanel`
/// drew five such rows, and none of them opened anything. Nothing new is fetched
/// here — `AO3WorkForm` already parses the offerable collections and the user's
/// series with their `isSelected` state, so these edit arrays the form will post
/// back rather than asking AO3 anything.
///
/// 1bw's "Search all collections by name" is AO3's own: the work form's
/// collection field autocompletes from `/autocomplete/open_collection_names`
/// (`AO3Client.openCollections`). The same query filters the collections the
/// form offers and, debounced, asks AO3 for other open ones; picking one adds
/// it to the list unticked, and only a tick posts it.
struct WorkCollectionsGiftsView: View {
    @Binding var collections: [AO3CollectionOffer]
    @Binding var gifts: [AO3GiftRecipient]
    let workTitle: String
    /// 1bw's "Also on this work" — read-only, because neither is editable from
    /// AO3's work form.
    var parentWorkCount: Int

    @Environment(ThemeManager.self) private var theme

    @ScaledMetric(relativeTo: .subheadline) private var rowTitleSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11.5

    @State private var query = ""
    @State private var searchResults: [AO3CollectionOffer] = []
    @State private var newRecipient = ""

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    private var visibleCollections: [AO3CollectionOffer] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return collections }
        return collections.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "Edit work",
                    title: "Collections and gifts",
                    subtitle: workTitle,
                    palette: palette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            Section {
                SectionRuleHeader(title: "Your collections", count: collections.count)
                    .pageBodyRow(top: 18, gutter: 0)
                collectionsPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("A work submitted to a moderated collection waits for a maintainer's approval. "
                    + "A work in an unrevealed collection stays hidden until the reveal. AO3 shows "
                    + "either state on the work.")
            }

            Section {
                SectionRuleHeader(title: "Gift recipients", count: gifts.count)
                    .pageBodyRow(top: 18, gutter: 0)
                giftsPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("When you post, AO3 emails each gift recipient. You can't take back the gift, "
                    + "so check each name before you save.")
            }

            if parentWorkCount > 0 {
                Section {
                    SectionRuleHeader(title: "Also on this work")
                        .pageBodyRow(top: 18, gutter: 0)
                    SubjectFormRow(
                        label: "Inspired by",
                        value: parentWorkCount == 1 ? "1 work" : "\(parentWorkCount) works",
                        isDisabled: true
                    )
                    .subjectPanel()
                    .pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: palette)
        #if os(macOS)
        .navigationTitle("Collections and gifts")
        #endif
        .task(id: query) { await search() }
    }

    /// One paced GET per pause in typing: a new keystroke cancels the wait.
    private func search() async {
        searchResults = []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(AO3TagAutocomplete.debounceMilliseconds))
        guard !Task.isCancelled,
              let found = try? await AO3Client.shared.openCollections(matching: query),
              !Task.isCancelled
        else { return }
        searchResults = Self.newOffers(found, excluding: collections)
    }

    /// AO3's answers the list doesn't already hold — a collection is one name.
    static func newOffers(_ found: [AO3CollectionOffer], excluding held: [AO3CollectionOffer]) -> [AO3CollectionOffer] {
        found.filter { offer in
            !held.contains { $0.name.caseInsensitiveCompare(offer.name) == .orderedSame }
        }
    }

    /// A search hit joins the list unticked. AO3's answer is every collection
    /// not closed — moderated, unrevealed and anonymous ones included — so
    /// posting the work into one is the writer's tick, not the add.
    static func adding(_ offer: AO3CollectionOffer, to held: [AO3CollectionOffer]) -> [AO3CollectionOffer] {
        var added = offer
        added.isSelected = false
        return held + [added]
    }

    private var collectionsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Search", arrangement: .control) {
                TextField("Search all collections by name", text: $query)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
            if visibleCollections.isEmpty && searchResults.isEmpty {
                SubjectRowSeparator()
                SubjectFormRow(
                    label: collections.isEmpty && query.isEmpty
                        ? "AO3 offers this work no collections"
                        : "No collection matches “\(query)”",
                    value: "",
                    isDisabled: true
                )
            }
            ForEach(visibleCollections) { offer in
                SubjectRowSeparator()
                collectionRow(offer)
            }
            ForEach(searchResults) { offer in
                SubjectRowSeparator()
                searchResultRow(offer)
            }
        }
        .subjectPanel()
    }

    /// A collection found on AO3: adding it lists it, unticked.
    private func searchResultRow(_ offer: AO3CollectionOffer) -> some View {
        Button {
            collections = Self.adding(offer, to: collections)
            searchResults.removeAll { $0.id == offer.id }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "plus.circle").foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.title.isEmpty ? offer.name : offer.title)
                        .font(.system(size: rowTitleSize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(Self.stateText(offer.access))
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(offer.title.isEmpty ? offer.name : offer.title)")
        .accessibilityValue(Self.stateText(offer.access))
    }

    /// 1bw: "Collections show their state on the row — moderated, closed, open —
    /// because submitting to a moderated collection leaves the work pending and
    /// that should be known before the tap, not after."
    private func collectionRow(_ offer: AO3CollectionOffer) -> some View {
        Button {
            guard let index = collections.firstIndex(where: { $0.id == offer.id }) else { return }
            collections[index].isSelected.toggle()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: offer.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(offer.isSelected ? palette.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.title.isEmpty ? offer.name : offer.title)
                        .font(.system(size: rowTitleSize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(Self.stateText(offer.access))
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offer.title.isEmpty ? offer.name : offer.title)
        .accessibilityValue(
            "\(Self.stateText(offer.access)). \(offer.isSelected ? "Selected" : "Not selected")"
        )
    }

    /// Unrevealed is additive rather than a fourth state: a collection can be both
    /// moderated and unrevealed, and the footnote below explains both.
    static func stateText(_ access: AO3CollectionAccess) -> String {
        var text: String
        switch access.rowState {
        case .moderated: text = "Moderated (a maintainer approves the work)"
        case .closed: text = "Closed to new works"
        case .open: text = "Open"
        case .unknown: text = "Open to new works (it may be moderated or unrevealed)"
        }
        if access.isUnrevealed { text += " · Unrevealed until reveal" }
        if access.isAnonymous { text += " · Anonymous" }
        return text
    }

    private var giftsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Add", arrangement: .control) {
                HStack(spacing: 8) {
                    TextField("Username or pseud", text: $newRecipient)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .onSubmit(addRecipient)
                    Button("Add", action: addRecipient)
                        .buttonStyle(.borderless)
                        .disabled(trimmedRecipient.isEmpty)
                }
            }
            ForEach(gifts) { recipient in
                SubjectRowSeparator()
                SubjectFormRow(label: recipient.name, arrangement: .value) {
                    Button {
                        gifts.removeAll { $0.id == recipient.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(theme.appTheme.excludeColor)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(recipient.name)")
                }
            }
        }
        .subjectPanel()
    }

    private var trimmedRecipient: String {
        newRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addRecipient() {
        let name = trimmedRecipient
        guard !name.isEmpty,
              !gifts.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        gifts.append(AO3GiftRecipient(name: name))
        newRecipient = ""
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: captionSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }
}

// MARK: - Series picker (artboard 1bw, second screen)

/// 1bw's series picker. Places this work in a series and nothing more: the board
/// "separates placing this work from reordering the series, since the first
/// writes one work and the second writes all of them" — so "Reorder the series"
/// pushes 1br's own screen, which saves on its own.
///
/// **One series per save, and adding only.** otwarchive's work form has one
/// `work[series_attributes][id]` select and one `[title]` field, and
/// `Work#series_attributes=` adds the chosen series (or creates the titled one,
/// the id winning) and removes nothing; `work_series_value` preselects only on
/// a re-rendered failed save. Taking a work out of a series is a separate
/// "Remove Work From Series" link (`DELETE /serial_works/:id`) this app does not
/// send. So the list is single-select and a tick means "add on save" — it was
/// multi-select, and every tick past the first was silently dropped.
struct WorkSeriesPickerView: View {
    @Binding var series: [AO3SeriesMembership]
    @Binding var newSeriesTitle: String
    let workTitle: String
    /// AO3's "Current Series". Shown, never posted: a tick on one of these
    /// would be a no-op on AO3, so they cannot be ticked.
    var currentSeries: [AO3CurrentSeries] = []

    @Environment(ThemeManager.self) private var theme

    @ScaledMetric(relativeTo: .subheadline) private var rowTitleSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11.5

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    private var selected: AO3SeriesMembership? { series.first(where: \.isSelected) }

    private var subtitle: String {
        if let selected { return "Saving adds \(workTitle) to \(selected.title)" }
        if let title = AO3WorkForm.newSeriesTitle(newSeriesTitle) {
            return "Saving creates \(title) with \(workTitle) in it"
        }
        if !currentSeries.isEmpty { return Self.membershipText(workTitle: workTitle, count: currentSeries.count) }
        return "Choose a series to add \(workTitle) to"
    }

    /// 1bw's "The Weight of Water is part of one series".
    static func membershipText(workTitle: String, count: Int) -> String {
        "\(workTitle) is part of \(count == 1 ? "one series" : "\(count) series")"
    }

    private func isCurrent(_ membership: AO3SeriesMembership) -> Bool {
        currentSeries.contains { $0.seriesID == membership.seriesID }
    }

    /// Where "Reorder the series" points: the series being added to, else the
    /// first one the work is already in.
    private var orderedSeries: AO3SeriesMembership? {
        if let selected { return selected }
        guard let current = currentSeries.first else { return nil }
        return series.first { $0.seriesID == current.seriesID }
            ?? AO3SeriesMembership(seriesID: current.seriesID, title: current.title)
    }

    /// Ticking a row picks it alone; ticking the picked row clears it.
    static func selecting(_ id: Int, in series: [AO3SeriesMembership]) -> [AO3SeriesMembership] {
        let pick = series.first { $0.id == id }?.isSelected == false
        return series.map { row in
            var row = row
            row.isSelected = pick && row.id == id
            return row
        }
    }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "Edit work",
                    title: "Series",
                    subtitle: subtitle,
                    palette: palette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            Section {
                SectionRuleHeader(title: "Your series", count: series.count)
                    .pageBodyRow(top: 18, gutter: 0)
                seriesPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("Each save adds this work to one series. Saving doesn't remove it from another "
                    + "series. To do that, use Remove works on the series' Edit screen.")
            }

            if let ordered = orderedSeries {
                Section {
                    SectionRuleHeader(title: "Position in \(ordered.title)")
                        .pageBodyRow(top: 18, gutter: 0)
                    SubjectFormRow(
                        label: "Reorder the series",
                        value: ordered.workCount.map { "\($0) work\($0 == 1 ? "" : "s")" } ?? "",
                        showsDisclosure: true
                    )
                    .subjectRowNavigation(accessibilityLabel: "Reorder the series") {
                        SeriesReorderDestination(seriesID: ordered.seriesID, seriesTitle: ordered.title)
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 8, gutter: gutter)
                    footnote("Changing the reading order updates every work in the series. Save the new "
                        + "order on its own screen.")
                }
            }

            Section {
                SectionRuleHeader(title: "New series")
                    .pageBodyRow(top: 18, gutter: 0)
                SubjectFormRow(label: "Create a series from this work", arrangement: .control) {
                    TextField("Title", text: $newSeriesTitle)
                        .multilineTextAlignment(.trailing)
                        // The form posts the picked id over a title, so typing
                        // a title un-picks rather than being silently ignored.
                        .onChange(of: newSeriesTitle) { _, title in
                            if AO3WorkForm.newSeriesTitle(title) != nil, selected != nil {
                                series = series.map { var row = $0; row.isSelected = false; return row }
                            }
                        }
                }
                .subjectPanel()
                .pageBodyRow(top: 8, gutter: gutter)
                footnote("AO3 creates the series with this work first. Add the series summary and notes afterwards.")
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: palette)
        #if os(macOS)
        .navigationTitle("Series")
        #endif
    }

    private var seriesPanel: some View {
        VStack(spacing: 0) {
            if series.isEmpty {
                SubjectFormRow(label: "You have no series yet", value: "", isDisabled: true)
            }
            ForEach(series) { membership in
                if membership.id != series.first?.id { SubjectRowSeparator() }
                seriesRow(membership)
            }
        }
        .subjectPanel()
    }

    private func seriesRow(_ membership: AO3SeriesMembership) -> some View {
        let isCurrent = isCurrent(membership)
        return Button {
            series = Self.selecting(membership.id, in: series)
            if series.contains(where: \.isSelected) { newSeriesTitle = "" }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isCurrent ? "checkmark" : membership.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(membership.isSelected ? palette.accent : Color.secondary)
                    .frame(minWidth: 17)
                VStack(alignment: .leading, spacing: 3) {
                    Text(membership.title)
                        .font(.system(size: rowTitleSize, weight: .medium))
                        .foregroundStyle(.primary)
                    if let detail = isCurrent ? "This work is in it" : Self.detailText(membership) {
                        Text(detail)
                            .font(.system(size: captionSize))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .accessibilityLabel(membership.title)
        .accessibilityValue(isCurrent ? "This work is in it" : membership.isSelected ? "Added on save" : "Not selected")
        .accessibilityAddTraits(membership.isSelected ? .isSelected : [])
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: captionSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }

    /// "3 works · this work is 2nd". Each half is dropped rather than guessed when
    /// AO3's form did not carry it.
    static func detailText(_ membership: AO3SeriesMembership) -> String? {
        var parts: [String] = []
        if let count = membership.workCount {
            parts.append("\(count) work\(count == 1 ? "" : "s")")
        }
        if membership.isSelected, let position = membership.position {
            parts.append("this work is \(ordinal(position))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "2nd". `NumberFormatter`'s ordinal style rather than a hand-rolled
    /// suffix table, so a non-English locale gets its own ordinal rather than
    /// English's.
    private static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// 1bo/1bs's **Co-creators** row.
///
/// Two different things wear one label on AO3, and the row that pushed nowhere
/// hid both: which of *your own* pseuds this work is posted under, and an
/// invitation to another account. The first is a plain multi-select; the second
/// is a byline that AO3 turns into an invitation the other person must accept,
/// which is why it is stated on the screen rather than left to surprise anyone.
struct WorkCreatorsPickerView: View {
    @Binding var creators: AO3CreatorDraft
    let workTitle: String

    @Environment(ThemeManager.self) private var theme

    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "Edit work",
                    title: "Co-creators",
                    subtitle: workTitle,
                    palette: palette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            Section {
                SectionRuleHeader(title: "Your pseuds", count: creators.availablePseuds.count)
                    .pageBodyRow(top: 18, gutter: 0)
                pseudsPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Invite a co-creator")
                    .pageBodyRow(top: 18, gutter: 0)
                bylinePanel.pageBodyRow(top: 8, gutter: gutter)
                Text("AO3 invites a co-creator, and the work stays unchanged until they accept. "
                    + "Enter their byline exactly as it appears on AO3, as username or username (pseud).")
                    .font(.system(size: footnoteSize))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle("Co-creators")
        .subjectScreenWash(palette: palette)
    }

    @ViewBuilder
    private var pseudsPanel: some View {
        if creators.availablePseuds.isEmpty {
            VStack(spacing: 0) {
                SubjectFormRow(label: "AO3 listed no pseuds for this work", value: "", isDisabled: true)
            }
            .subjectPanel()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(creators.availablePseuds.enumerated()), id: \.element.id) { index, pseud in
                    if index > 0 { SubjectRowSeparator() }
                    SubjectFormRow(label: pseud.title, arrangement: .control) {
                        Toggle("", isOn: binding(for: pseud.value))
                            .labelsHidden()
                    }
                }
            }
            .subjectPanel()
        }
    }

    private var bylinePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Byline", arrangement: .control) {
                TextField("username (pseud)", text: $creators.coauthorByline)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
        }
        .subjectPanel()
    }

    /// AO3 posts a work under at least one pseud, so the last one on cannot be
    /// turned off here — an empty set would post the work under nobody.
    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { creators.selectedPseudIDs.contains(id) },
            set: { isOn in
                if isOn {
                    if !creators.selectedPseudIDs.contains(id) {
                        creators.selectedPseudIDs.append(id)
                    }
                } else if creators.selectedPseudIDs.count > 1 {
                    creators.selectedPseudIDs.removeAll { $0 == id }
                }
            }
        )
    }
}

/// 1bo's **Inspired by** row — AO3's parent-work fields.
///
/// A URL alone is enough for a work already on AO3; the title and author exist
/// for a source that is not, and the translation flag changes what AO3 calls the
/// relationship. All four are the same `work[parent_attributes]` group, so they
/// belong on one screen rather than four rows that each push somewhere.
struct WorkParentWorkPickerView: View {
    @Binding var parentWork: AO3ParentWorkDraft
    let languageOptions: [AO3FormOption]

    @Environment(ThemeManager.self) private var theme

    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "Edit work",
                    title: "Inspired by",
                    subtitle: parentWork.url.isEmpty
                        ? "No source work"
                        : parentWork.url,
                    palette: palette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }

            Section {
                SectionRuleHeader(title: "Source work")
                    .pageBodyRow(top: 18, gutter: 0)
                sourcePanel.pageBodyRow(top: 8, gutter: gutter)
                Text("For a work on AO3, enter its web address. For a work from elsewhere, enter its "
                    + "title and author, which will appear instead of a link.")
                    .font(.system(size: footnoteSize))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Translation")
                    .pageBodyRow(top: 18, gutter: 0)
                translationPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle("Inspired by")
        .subjectScreenWash(palette: palette)
    }

    private var sourcePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "URL", arrangement: .control) {
                TextField("https://archiveofourown.org/works/…", text: $parentWork.url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.URL)
                    #endif
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Title", arrangement: .control) {
                TextField("Optional", text: $parentWork.title)
                    .multilineTextAlignment(.trailing)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Author", arrangement: .control) {
                TextField("Optional", text: $parentWork.author)
                    .multilineTextAlignment(.trailing)
            }
        }
        .subjectPanel()
    }

    private var translationPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "This work is a translation", arrangement: .control) {
                Toggle("", isOn: $parentWork.isTranslation)
                    .labelsHidden()
            }
            SubjectRowSeparator()
            WritingChoiceRow(
                title: "Language of the source",
                value: $parentWork.languageID,
                options: languageOptions
            )
        }
        .subjectPanel()
    }
}
