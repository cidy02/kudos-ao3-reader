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
                        .pageBodyRow(top: 14, gutter: gutter)
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
                    #if os(iOS)
                    Button {
                        saveTag()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .sheetConfirmStyle()
                    .disabled(isLimitReached)
                    .accessibilityLabel(isEditing ? "Save settings for \(tagName)" : "Follow \(tagName)")
                    #else
                    Button(isEditing ? "Save" : "Follow") {
                        saveTag()
                    }
                    .disabled(isLimitReached)
                    .accessibilityLabel(isEditing ? "Save settings for \(tagName)" : "Follow \(tagName)")
                    #endif
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
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

    private static let tagTileGreen = Color(red: 0x25 / 255, green: 0x66 / 255, blue: 0x3C / 255)

    private var headerSubtitle: String {
        FollowTagSheetCopy.subtitle(
            category: effectiveCategory,
            followedCount: followedTags.count,
            maxCount: FollowedTag.maxFollowedCount,
            lastCheckedAt: existingTag?.lastCheckedAt
        )
    }

    private var headerCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Image(systemName: isEditing ? "bell.fill" : "tag")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Self.tagTileGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(tagName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var raisedCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return shape
            .fill(theme.appTheme.cardSurface)
            .overlay(shape.strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
    }

    private var limitBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(FollowedTag.maxFollowedCount) of \(FollowedTag.maxFollowedCount) tags followed")
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
        .background(raisedCardBackground)
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
        .background(raisedCardBackground)
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How Kudos learns what’s new")
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
        .background(raisedCardBackground)
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
        .background(raisedCardBackground)
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

/// Pure board-copy formatting for `FollowTagSheet` (`Subscriptions-Plan.dc.html`).
enum FollowTagSheetCopy {
    static func subtitle(
        category: String?,
        followedCount: Int,
        maxCount: Int = FollowedTag.maxFollowedCount,
        lastCheckedAt: Date?
    ) -> String {
        subtitle(
            category: category,
            followedCount: followedCount,
            maxCount: maxCount,
            lastCheckedRelativeText: lastCheckedAt?.formatted(.relative(presentation: .named))
        )
    }

    static func subtitle(
        category: String?,
        followedCount: Int,
        maxCount: Int = FollowedTag.maxFollowedCount,
        lastCheckedRelativeText: String?
    ) -> String {
        var parts: [String] = []
        if let category {
            let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        if let lastCheckedRelativeText, !lastCheckedRelativeText.isEmpty {
            parts.append("Last checked \(lastCheckedRelativeText)")
        } else {
            parts.append("\(followedCount) of \(maxCount) tags followed")
        }
        return parts.joined(separator: " · ")
    }
}
