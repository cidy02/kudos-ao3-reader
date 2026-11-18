import SwiftData
import SwiftUI

/// Board `Subscriptions-Plan`: Follow Tag / Edit Followed Tag settings sheet.
///
/// Opens from a feed-eligible tag's works page (`TagWorksView`, single-fandom
/// `FandomWorksView`) or from an existing row in `Subscriptions -> Tags`.
/// Switches filter entries locally inside Kudos; nothing is sent to AO3.
struct FollowTagSheet: View {
    let ao3TagID: Int
    let tagName: String
    let tagCategoryRaw: String?
    let tagURLString: String?
    let existingTag: FollowedTag?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @Environment(FollowedTagUpdateStore.self) private var updateStore

    @Query(sort: \FollowedTag.followedAt) private var followedTags: [FollowedTag]

    @State private var showOnHome: Bool
    @State private var completeOnly: Bool
    @State private var hideExplicit: Bool
    @State private var confirmingUnfollow = false
    @State private var errorMessage: String?

    init(
        ao3TagID: Int,
        tagName: String,
        tagCategoryRaw: String? = nil,
        tagURLString: String? = nil,
        existingTag: FollowedTag? = nil
    ) {
        self.ao3TagID = ao3TagID
        self.tagName = tagName
        self.tagCategoryRaw = tagCategoryRaw
        self.tagURLString = tagURLString
        self.existingTag = existingTag
        _showOnHome = State(initialValue: existingTag?.showOnHome ?? true)
        _completeOnly = State(initialValue: existingTag?.completeOnly ?? false)
        _hideExplicit = State(initialValue: existingTag?.hideExplicit ?? false)
    }

    private var isEditing: Bool { existingTag != nil }

    private var canFollow: Bool {
        FollowedTagStore.canFollow(existing: followedTags, ao3TagID: ao3TagID)
    }

    private var isLimitReached: Bool {
        !isEditing && !canFollow
    }

    private var gutter: CGFloat { SubjectMetrics.gutter }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerCard
                        .pageBodyRow(top: 10, gutter: gutter)
                }

                if isLimitReached {
                    Section {
                        limitBanner
                            .pageBodyRow(top: 4, gutter: gutter)
                    }
                }

                Section {
                    switchesCard
                        .pageBodyRow(top: 4, gutter: gutter)
                    footnoteText(
                        "Switches filter this tag's Atom feed entries locally inside Kudos."
                    )
                }

                Section {
                    explainerCard
                        .pageBodyRow(top: 4, gutter: gutter)
                }

                if isEditing {
                    Section {
                        unfollowCard
                            .pageBodyRow(top: 4, gutter: gutter)
                    }
                }
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle(isEditing ? "Followed Tag" : "Follow Tag")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .wrappingInlineTitle(
                isEditing ? "Followed Tag" : "Follow Tag",
                isActive: dynamicTypeSize.isAccessibilitySize
            )
            .subjectScreenWash(palette: theme.scopePalette)
            .screenTint(theme.scopePalette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(
                        title: "Cancel",
                        systemImage: "xmark",
                        tint: .primary
                    ) {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Follow") {
                        saveTag()
                    }
                    .sheetConfirmStyle()
                    .disabled(isLimitReached)
                    .accessibilityLabel(isEditing ? "Save settings for \(tagName)" : "Follow \(tagName)")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .confirmationDialog(
            "Unfollow “\(tagName)”?",
            isPresented: $confirmingUnfollow,
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                unfollowTag()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kudos will stop checking this tag's AO3 feed and clear its unread tag updates.")
        }
        .alert(
            "Couldn't follow tag",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isEditing ? "bell.fill" : "tag.fill")
                .font(.title3)
                .foregroundStyle(.accentInk)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let category = effectiveCategory {
                    Text(category.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondaryInk)
                }

                Text(tagName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let existingTag, let checked = existingTag.lastCheckedAt {
                    Text("Last checked \(checked.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                } else {
                    Text("\(followedTags.count) of \(FollowedTag.maxFollowedCount) tags followed")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .subjectPanel()
        .accessibilityElement(children: .combine)
    }

    private var limitBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("20 of 20 tags followed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(
                "You can follow up to \(FollowedTag.maxFollowedCount) tags at a time. "
                    + "Unfollow one in Subscriptions → Tags before following “\(tagName)”."
            )
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
        .accessibilityElement(children: .combine)
    }

    private var switchesCard: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Show new works on Home", arrangement: .control) {
                Toggle("", isOn: $showOnHome)
                    .labelsHidden()
                    .accessibilityLabel("Show new works on Home")
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Complete works only", arrangement: .control) {
                Toggle("", isOn: $completeOnly)
                    .labelsHidden()
                    .accessibilityLabel("Complete works only")
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Hide works rated Explicit", arrangement: .control) {
                Toggle("", isOn: $hideExplicit)
                    .labelsHidden()
                    .accessibilityLabel("Hide works rated Explicit")
            }
        }
        .subjectPanel()
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How Kudos learns what's new")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(
                "AO3 does not have tag subscriptions. Kudos checks this tag's public Atom feed "
                    + "at most once every 6 hours, strictly one tag at a time, and only while "
                    + "Home or Subscriptions is open."
            )
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
        .accessibilityElement(children: .combine)
    }

    private var unfollowCard: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Unfollow Tag",
                arrangement: .value,
                isDestructive: true,
                action: { confirmingUnfollow = true }
            ) {
                EmptyView()
            }
            .accessibilityLabel("Unfollow \(tagName)")
        }
        .subjectPanel()
    }

    private func footnoteText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
            .pageBodyRow(top: 6, gutter: gutter)
    }

    private var effectiveCategory: String? {
        if let raw = tagCategoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return existingTag?.displayCategory
    }

    private func saveTag() {
        do {
            try FollowedTagStore.followOrUpdate(
                ao3TagID: ao3TagID,
                name: tagName,
                tagCategoryRaw: effectiveCategory,
                tagURLString: tagURLString ?? existingTag?.tagURLString,
                showOnHome: showOnHome,
                completeOnly: completeOnly,
                hideExplicit: hideExplicit,
                in: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unfollowTag() {
        guard let existingTag else {
            dismiss()
            return
        }
        FollowedTagStore.unfollow(existingTag, in: context, updateStore: updateStore)
        dismiss()
    }
}
