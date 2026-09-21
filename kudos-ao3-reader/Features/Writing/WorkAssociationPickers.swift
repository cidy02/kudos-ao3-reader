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
/// **What 1bw draws that this does not build:** the "Search all collections by
/// name" field. The form carries the collections AO3 offers *this* work; there is
/// no endpoint here for searching every collection on the site, and a field that
/// filtered only the offered list would be a different control wearing that
/// label. Filtering the offered list is what the search field here actually does,
/// and it is named accordingly.
struct WorkCollectionsGiftsView: View {
    @Binding var collections: [AO3CollectionOffer]
    @Binding var gifts: [AO3GiftRecipient]
    let workTitle: String
    /// 1bw's "Also on this work" — read-only, because neither is editable from
    /// AO3's work form.
    var parentWorkCount: Int

    @Environment(ThemeManager.self) private var theme
    @State private var query = ""
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
                footnote("A work submitted to a moderated collection is pending until a "
                    + "maintainer approves it, and to an unrevealed collection it is hidden "
                    + "until reveal. Both states show on the work, so neither is silent.")
            }

            Section {
                SectionRuleHeader(title: "Gift recipients", count: gifts.count)
                    .pageBodyRow(top: 18, gutter: 0)
                giftsPanel.pageBodyRow(top: 8, gutter: gutter)
                footnote("Gifts are notified by email on post and cannot be taken back, so a "
                    + "typo matters here. AO3 checks the name when the work is saved.")
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
        .subjectScreenWash(palette: palette)
        #if os(macOS)
        .navigationTitle("Collections and gifts")
        #endif
    }

    private var collectionsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Filter", arrangement: .control) {
                TextField("Filter your collections by name", text: $query)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
            if visibleCollections.isEmpty {
                SubjectRowSeparator()
                SubjectFormRow(
                    label: collections.isEmpty
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
        }
        .subjectPanel()
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
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(Self.stateText(offer.access))
                        .font(.system(size: 11.5))
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
        case .moderated: text = "Moderated — a maintainer approves the work"
        case .closed: text = "Closed to new works"
        case .open: text = "Open"
        case .unknown: text = "State unknown"
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
            .font(.system(size: 11.5))
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
/// writes one work and the second writes all of them" — reordering is 1br's own
/// screen, reached from the series rather than from here.
struct WorkSeriesPickerView: View {
    @Binding var series: [AO3SeriesMembership]
    let workTitle: String

    @Environment(ThemeManager.self) private var theme

    private var palette: SubjectPalette { theme.scopePalette }
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    private var selectedCount: Int { series.filter(\.isSelected).count }

    private var subtitle: String {
        switch selectedCount {
        case 0: "\(workTitle) is not in a series"
        case 1: "\(workTitle) is part of one series"
        default: "\(workTitle) is part of \(selectedCount) series"
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
                Text("Placing a work in a series writes to this work. Changing the reading "
                    + "order writes to every work in the series, so it lives on the series "
                    + "itself rather than here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
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
        Button {
            guard let index = series.firstIndex(where: { $0.id == membership.id }) else { return }
            series[index].isSelected.toggle()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: membership.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(membership.isSelected ? palette.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(membership.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(.primary)
                    if let detail = Self.detailText(membership) {
                        Text(detail)
                            .font(.system(size: 11.5))
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
        .accessibilityLabel(membership.title)
        .accessibilityValue(membership.isSelected ? "In this series" : "Not in this series")
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
                Text("A co-creator is invited rather than added: the work is unchanged "
                    + "until the other account accepts. Use the byline exactly as it "
                    + "appears on AO3, as username or username (pseud).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
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
                Text("A work already on AO3 needs only its URL. Title and author are for "
                    + "a source somewhere else, and are shown instead of the link.")
                    .font(.system(size: 11.5))
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
