import SwiftUI

/// Artboard **1ch** — Tag set.
///
/// A tag set is not addressed by `collectionSlug` like the other four screens in
/// this batch — AO3 gives it its own numeric id, so this screen takes `tagSetID`
/// directly, the way `AO3TagSet` and `AO3ChallengeURL.tagSet` already do. The id
/// comes from `AO3Client.collectionTagSets`, which reads the `Tag Set:` links off
/// the collection **profile** page; the two challenge screens
/// (`ChallengeSettingsView` 1by, `ChallengeSettingsEditView` 1cf) push here.
///
/// Read-only except for the two surfaces AO3 genuinely lets a caller write: the
/// four comma-separated tagname fields (`saveTagSetFields`) and a per-nomination
/// reject (`reportRejectedTag`). Everything else — `isVisible`, `isNominated`, the
/// four per-person nomination limits, approving a nomination, associating
/// nominations with a fandom, deleting the tag set — has no POST behind it
/// anywhere in `AO3ChallengeActions.swift`: `AO3TagSetSave` carries only the four
/// tagname strings (`AO3Client.tagSetSaveParameters`), so those are drawn
/// read-only or as "Open on AO3" rather than controls that would silently do
/// nothing. Approving in particular is never a client write at all — AO3 only
/// approves a nomination by associating it with a fandom, which is the
/// "Associate nominations" escape hatch below.
///
/// `AO3TagSet` carries no owner/moderator pseud fields, so "Ownership" shows only
/// what the model actually has (`title`, `isVisible`) rather than inventing a
/// roster. `isModerator` — which the pushing challenge screen passes in, `true`
/// from the maintainer edit form and `false` from the read view — only swaps the
/// header's kicker between "owner" and "moderator";
/// it does not gate which rows appear, since every write path above behaves the
/// same regardless of which relationship brought the reader here.
///
/// The review queue groups by `parentTagName` per the model's own note that a
/// nominated character or relationship needs its fandom association finished
/// before AO3 will approve it — grouping is how the queue keeps that dependency
/// visible.
struct TagSetView: View {
    let tagSetID: Int
    var tagSetTitle: String = ""
    /// Swaps the header kicker between "owner" and "moderator". `AO3TagSet` has
    /// no field for this — the challenge screen that pushes this one already
    /// knows whether it is the maintainer's edit form or the open read view.
    var isModerator: Bool = false

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router

    @State private var tagSet: AO3TagSet?
    @State private var phase: Phase = .idle

    @State private var fandomTagnames: String = ""
    @State private var characterTagnames: String = ""
    @State private var relationshipTagnames: String = ""
    @State private var freeformTagnames: String = ""
    @State private var isSavingFields: Bool = false
    @State private var saveFieldsNotice: String?
    @State private var saveFieldsError: String?

    @State private var nominationInFlight: Int?
    @State private var queueErrorMessage: String?

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: effectiveTitle))
    }

    private var effectiveTitle: String {
        if !tagSetTitle.isEmpty { return tagSetTitle }
        if let title = tagSet?.title, !title.isEmpty { return title }
        return "Tag Set \(tagSetID)"
    }

    private var totalTagCount: Int {
        guard let tagSet else { return 0 }
        return tagSet.fandomCount + tagSet.characterCount + tagSet.relationshipCount + tagSet.freeformCount
    }

    private var reviewQueue: [AO3TagNomination] { tagSet?.reviewQueue ?? [] }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
            }

            switch phase {
            case .loading:
                Section {
                    loadingRow.pageBodyRow(top: 20, gutter: gutter)
                }
            case let .failed(message):
                Section {
                    failureCard(message).pageBodyRow(top: 14, gutter: gutter)
                }
            case .idle, .loaded:
                contentSections
            }
        }
        .cardList()
        #if os(macOS)
        .navigationTitle("Tag set")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadTagSetIfNeeded() }
        .refreshable { await loadTagSet() }
    }

    // MARK: - Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: isModerator ? "Tag set · moderator" : "Tag set · owner",
            title: "Tag set",
            subtitle: "\(effectiveTitle) · \(totalTagCount) tags",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            SectionRuleHeader(title: "Ownership")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            ownershipPanel.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Tags", count: totalTagCount)
                .pageBodyRow(top: 18, gutter: selfGuttered)
            tagCountsPanel.pageBodyRow(top: 8, gutter: gutter)

            tagFieldEditor(
                title: "Fandom tags to add",
                placeholder: "Comma-separated fandom names…",
                text: $fandomTagnames
            ).pageBodyRow(top: 10, gutter: gutter)

            tagFieldEditor(
                title: "Character tags to add",
                placeholder: "Comma-separated character names…",
                text: $characterTagnames
            ).pageBodyRow(top: 8, gutter: gutter)

            tagFieldEditor(
                title: "Relationship tags to add",
                placeholder: "Comma-separated relationships…",
                text: $relationshipTagnames
            ).pageBodyRow(top: 8, gutter: gutter)

            tagFieldEditor(
                title: "Additional tags to add",
                placeholder: "Comma-separated additional tags…",
                text: $freeformTagnames
            ).pageBodyRow(top: 8, gutter: gutter)

            tagFieldsFootnote.pageBodyRow(top: 8, gutter: gutter)
            saveFieldsFeedback
            saveFieldsButton.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Nominations")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            nominationsPanel.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Review")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            reviewCountsPanel.pageBodyRow(top: 8, gutter: gutter)

            if let queueErrorMessage {
                errorCard(queueErrorMessage).pageBodyRow(top: 8, gutter: gutter)
            }

            reviewQueueList.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "At AO3")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            atAO3Panel.pageBodyRow(top: 8, gutter: gutter)
        }
    }

    // MARK: - Ownership

    private var ownershipPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Title", value: effectiveTitle)

            SubjectRowSeparator()

            SubjectFormRow(label: "Visible to everyone", arrangement: .control) {
                Toggle("", isOn: .constant(tagSet?.isVisible ?? true))
                    .labelsHidden()
                    .disabled(true)
            }
        }
        .subjectPanel()
    }

    // MARK: - Tags

    private var tagCountsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Fandoms", value: "\(tagSet?.fandomCount ?? 0)", isMonospaced: true)

            SubjectRowSeparator()

            SubjectFormRow(label: "Characters", value: "\(tagSet?.characterCount ?? 0)", isMonospaced: true)

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Relationships", value: "\(tagSet?.relationshipCount ?? 0)", isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Additional tags", value: "\(tagSet?.freeformCount ?? 0)", isMonospaced: true
            )
        }
        .subjectPanel()
    }

    private func tagFieldEditor(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SubjectFieldLabel(text: title, style: .formGroup)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: text)
                    .font(.system(size: 13))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
        .padding(14)
        .subjectPanel()
    }

    private var tagFieldsFootnote: some View {
        Text("Each type is its own field on AO3 and takes a comma-separated list. "
            + "The app writes them back as one save, so a rejected tag has to be reported "
            + "against the field it came from.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var saveFieldsFeedback: some View {
        if let saveFieldsError {
            errorCard(saveFieldsError).pageBodyRow(top: 8, gutter: gutter)
        }
        if let saveFieldsNotice {
            noticeCard(saveFieldsNotice).pageBodyRow(top: 8, gutter: gutter)
        }
    }

    private var saveFieldsButton: some View {
        Button {
            Task { await saveTagFields() }
        } label: {
            HStack(spacing: 6) {
                if isSavingFields {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accentOnFill)
                }
                Text("Save tags")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accentOnFill)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSavingFields)
    }

    // MARK: - Nominations

    private var nominationsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Nominations open", arrangement: .control) {
                Toggle("", isOn: .constant(tagSet?.isNominated ?? false))
                    .labelsHidden()
                    .disabled(true)
            }

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Fandoms per person",
                value: "\(tagSet?.fandomNominationLimit ?? 0)",
                showsDisclosure: true,
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Characters per person",
                value: "\(tagSet?.characterNominationLimit ?? 0)",
                showsDisclosure: true,
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Relationships per person",
                value: "\(tagSet?.relationshipNominationLimit ?? 0)",
                showsDisclosure: true,
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Additional tags per person",
                value: "\(tagSet?.freeformNominationLimit ?? 0)",
                showsDisclosure: true,
                isMonospaced: true
            )
        }
        .subjectPanel()
    }

    // MARK: - Review

    private var reviewCountsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Awaiting review",
                value: "\(reviewQueue.filter { $0.state == .unreviewed }.count)",
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Approved",
                value: "\(reviewQueue.filter { $0.state == .approved }.count)",
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Rejected",
                value: "\(reviewQueue.filter { $0.state == .rejected }.count)",
                isMonospaced: true
            )
        }
        .subjectPanel()
    }

    /// `parentTagName` groups, sorted alphabetically with the fandom-less bucket
    /// last — a nomination without one is the exception, not the common case.
    private var groupedQueue: [(fandom: String, nominations: [AO3TagNomination])] {
        let groups = Dictionary(grouping: reviewQueue, by: \.parentTagName)
        return groups.keys
            .sorted { lhs, rhs in
                if lhs.isEmpty != rhs.isEmpty { return rhs.isEmpty }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { (fandom: $0, nominations: groups[$0] ?? []) }
    }

    @ViewBuilder
    private var reviewQueueList: some View {
        if reviewQueue.isEmpty {
            emptyQueueCard
        } else {
            VStack(spacing: 9) {
                ForEach(groupedQueue, id: \.fandom) { group in
                    fandomGroupPanel(fandom: group.fandom, nominations: group.nominations)
                }
            }
        }
    }

    private func fandomGroupPanel(fandom: String, nominations: [AO3TagNomination]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fandom.isEmpty ? "No fandom listed" : fandom)
                .font(.system(size: 11, weight: .bold))
                .tracking(11 * 0.07)
                .textCase(.uppercase)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ForEach(Array(nominations.enumerated()), id: \.element.id) { index, nomination in
                if index > 0 { SubjectRowSeparator() }
                nominationRow(nomination)
            }
        }
        .subjectPanel()
    }

    private func nominationRow(_ nomination: AO3TagNomination) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nomination.tagName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(fieldLabel(nomination.field))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch nomination.state {
            case .unreviewed:
                rejectButton(for: nomination)
            case .approved:
                stateBadge("Approved", color: .green)
            case .rejected:
                stateBadge("Rejected", color: .red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func fieldLabel(_ field: AO3TagSetField) -> String {
        switch field {
        case .fandom: "Fandom"
        case .character: "Character"
        case .relationship: "Relationship"
        case .freeform: "Additional tag"
        }
    }

    private func rejectButton(for nomination: AO3TagNomination) -> some View {
        let isInFlight = nominationInFlight == nomination.id
        return Button {
            Task { await reject(nomination) }
        } label: {
            HStack(spacing: 4) {
                if isInFlight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.red)
                }
                Text("Reject")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.12))
                    .overlay(Capsule().strokeBorder(Color.red.opacity(0.32), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(nominationInFlight != nil)
    }

    private func stateBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private var emptyQueueCard: some View {
        VStack(spacing: 6) {
            Text("No nominations yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Nothing has been nominated to this tag set.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - At AO3

    private var atAO3Panel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Associate nominations",
                value: "Opens AO3",
                showsDisclosure: true
            ) {
                router.open(tagSet?.associationOpenOnAO3 ?? AO3ChallengeURL.tagSetAssociations(id: tagSetID))
            }

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Delete tag set",
                value: "Opens AO3",
                showsDisclosure: true,
                isDestructive: true
            ) {
                router.open(AO3ChallengeURL.tagSetEdit(tagSetID))
            }
        }
        .subjectPanel()
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading tag set…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load tag set")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadTagSet() }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(palette.accent)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .subjectPanel()
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.red)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .subjectPanel()
    }

    // MARK: - Actions

    private func loadTagSetIfNeeded() async {
        guard phase == .idle else { return }
        await loadTagSet()
    }

    private func loadTagSet() async {
        phase = .loading
        do {
            var baseRequest: URLRequest?
            if auth.isLoggedIn {
                baseRequest = try? auth.authenticatedRequest(for: AO3ChallengeURL.tagSet(tagSetID))
            }
            var loaded = try await AO3Client.shared.tagSet(id: tagSetID, request: baseRequest)

            // The edit form is the owner-only surface: CSRF, the save action, and
            // the writable tagname fields all live there rather than on the public
            // read. Fall back to the public read's own fields when signed out or
            // when the caller isn't the owner and AO3 refuses the edit page.
            if auth.isLoggedIn,
               let editRequest = try? auth.authenticatedRequest(for: AO3ChallengeURL.tagSetEdit(tagSetID)),
               let editForm = try? await AO3Client.shared.tagSetEditForm(id: tagSetID, request: editRequest) {
                loaded = editForm
            }

            // The dedicated nominations route is the actual review queue; the base
            // page's own best-effort parse of it (`parseTagSet` calling
            // `parseTagSetNominations` on whatever HTML it was given) is the
            // fallback for a signed-out or non-owner read.
            if auth.isLoggedIn,
               let nominationsRequest = try? auth.authenticatedRequest(for: AO3ChallengeURL.tagSetNominations(tagSetID)),
               let queue = try? await AO3Client.shared.tagSetNominations(id: tagSetID, request: nominationsRequest) {
                loaded.reviewQueue = queue
            }

            tagSet = loaded
            resetEditFields(from: loaded)
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func resetEditFields(from tagSet: AO3TagSet) {
        fandomTagnames = tagSet.fandomTagnames
        characterTagnames = tagSet.characterTagnames
        relationshipTagnames = tagSet.relationshipTagnames
        freeformTagnames = tagSet.freeformTagnames
    }

    private func saveTagFields() async {
        guard let tagSet else { return }
        isSavingFields = true
        saveFieldsError = nil
        saveFieldsNotice = nil
        let fields = AO3TagSetSave(
            fandomTagnames: fandomTagnames,
            characterTagnames: characterTagnames,
            relationshipTagnames: relationshipTagnames,
            freeformTagnames: freeformTagnames
        )
        do {
            try await auth.saveTagSetFields(tagSet: tagSet, fields: fields)
            saveFieldsNotice = "Tags saved."
        } catch {
            saveFieldsError = error.localizedDescription
        }
        isSavingFields = false
    }

    private func reject(_ nomination: AO3TagNomination) async {
        nominationInFlight = nomination.id
        queueErrorMessage = nil
        do {
            try await auth.reportRejectedTag(
                tagSetID: tagSetID, field: nomination.field, tagName: nomination.tagName
            )
            withAnimation { markRejectedLocally(nomination) }
        } catch {
            queueErrorMessage = "Couldn't reject \u{201c}\(nomination.tagName)\u{201d}: \(error.localizedDescription)"
        }
        nominationInFlight = nil
    }

    private func markRejectedLocally(_ nomination: AO3TagNomination) {
        guard var current = tagSet,
              let index = current.reviewQueue.firstIndex(where: { $0.id == nomination.id })
        else { return }
        current.reviewQueue[index].state = .rejected
        tagSet = current
    }
}
