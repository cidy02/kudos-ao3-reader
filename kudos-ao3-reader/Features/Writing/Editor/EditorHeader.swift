import SwiftUI

/// The editor screen's top bar (`Studio-Editor.dc.html`, `Studio-Edit-Posted.dc.html`):
/// a prominent Done checkmark, the work title over the chapter switcher trigger, and
/// a glass capsule housing Notes and the `•••` menu (with an optional Changes pill for
/// posted chapters).
struct EditorHeader<ChapterTrigger: View, MoreTrigger: View>: View {
    let workTitle: String
    let showsNotes: Bool
    let showsChangesToggle: Bool
    let isComparingChanges: Bool
    let onDone: () -> Void
    let onNotes: () -> Void
    let onToggleChanges: (() -> Void)?
    @ViewBuilder let chapterTrigger: () -> ChapterTrigger
    @ViewBuilder let moreTrigger: () -> MoreTrigger

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    private var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    private var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    init(
        workTitle: String,
        showsNotes: Bool = true,
        showsChangesToggle: Bool = false,
        isComparingChanges: Bool = false,
        onDone: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onToggleChanges: (() -> Void)? = nil,
        @ViewBuilder chapterTrigger: @escaping () -> ChapterTrigger,
        @ViewBuilder moreTrigger: @escaping () -> MoreTrigger
    ) {
        self.workTitle = workTitle
        self.showsNotes = showsNotes
        self.showsChangesToggle = showsChangesToggle
        self.isComparingChanges = isComparingChanges
        self.onDone = onDone
        self.onNotes = onNotes
        self.onToggleChanges = onToggleChanges
        self.chapterTrigger = chapterTrigger
        self.moreTrigger = moreTrigger
    }

    var body: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.14))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    private var standardLayout: some View {
        HStack(spacing: 8) {
            doneButton
            titleStack
                .frame(maxWidth: .infinity)
            if showsChangesToggle, let onToggleChanges {
                changesToggleButton(action: onToggleChanges)
            }
            trailingCapsule
        }
    }

    /// At accessibility text sizes the title takes its own full-width row below the
    /// controls so the chapter name never collapses into a few letters between buttons.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                doneButton
                Spacer(minLength: 8)
                if showsChangesToggle, let onToggleChanges {
                    changesToggleButton(action: onToggleChanges)
                }
                trailingCapsule
            }
            titleStack
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(ThemeManager.label(on: effectiveTint))
                .frame(width: 44, height: 44)
                .background(effectiveTint, in: Circle())
                .shadow(color: effectiveTint.opacity(appTheme.isDarkFamily ? 0 : 0.25), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
    }

    private var titleStack: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: 1) {
            if !workTitle.isEmpty {
                Text(workTitle)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)
            }
            chapterTrigger()
        }
        .frame(minWidth: 0)
    }

    private func changesToggleButton(action: @escaping () -> Void) -> some View {
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return Button(action: action) {
            Text("Changes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isComparingChanges ? accentInk : Color.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(
                    isComparingChanges
                        ? effectiveTint.opacity(appTheme.isDarkFamily ? 0.24 : 0.12)
                        : appTheme.glassFill(0.10),
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel("Compare with the posted chapter")
        .accessibilityAddTraits(isComparingChanges ? .isSelected : [])
    }

    private var trailingCapsule: some View {
        HStack(spacing: 0) {
            if showsNotes {
                Button(action: onNotes) {
                    Image(systemName: "doc.text")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notes")
            }

            moreTrigger()
        }
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private var headerBackground: some View {
        if let base = appTheme.appBaseBackground {
            base.opacity(0.94)
        } else {
            Rectangle().fill(.bar)
        }
    }
}

/// Default chapter-title button used by `EditorHeader` when driven by a callback.
struct EditorHeaderChapterButton: View {
    let chapterTitle: String
    var isSwitcherOpen: Bool = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(chapterTitle)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)
                Image(systemName: isSwitcherOpen ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumHitTarget(36)
        .accessibilityLabel("\(chapterTitle). Switch chapter")
    }
}

/// Default `•••` button used by `EditorHeader` when driven by a callback.
struct EditorHeaderMoreButton: View {
    var showsUnpostedDot: Bool = false
    var isPosted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorMoreTriggerLabel(showsUnpostedDot: showsUnpostedDot)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            EditorMoreMenuModel.triggerAccessibilityLabel(
                isPosted: isPosted,
                hasUnpostedChanges: showsUnpostedDot
            )
        )
    }
}

/// Shared visual glyph for the `•••` button inside the header glass capsule,
/// including the unposted-changes dot (`Studio-Edit-Posted.dc.html`).
struct EditorMoreTriggerLabel: View {
    var showsUnpostedDot: Bool = false

    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accentInk) private var envAccentInk

    private var dotColor: Color { themeManager?.accentInk ?? envAccentInk }

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if showsUnpostedDot {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .offset(x: -9, y: 9)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
    }
}

extension EditorHeader where ChapterTrigger == EditorHeaderChapterButton, MoreTrigger == EditorHeaderMoreButton {
    /// Callback-based convenience initializer for hosts managing their own popovers/sheets.
    init(
        workTitle: String,
        chapterTitle: String,
        isPosted: Bool = false,
        hasUnpostedChanges: Bool = false,
        isChapterSwitcherOpen: Bool = false,
        showsNotes: Bool = true,
        showsChangesToggle: Bool = false,
        isComparingChanges: Bool = false,
        onDone: @escaping () -> Void,
        onSwitchChapter: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onMore: @escaping () -> Void,
        onToggleChanges: (() -> Void)? = nil
    ) {
        self.init(
            workTitle: workTitle,
            showsNotes: showsNotes,
            showsChangesToggle: showsChangesToggle,
            isComparingChanges: isComparingChanges,
            onDone: onDone,
            onNotes: onNotes,
            onToggleChanges: onToggleChanges,
            chapterTrigger: {
                EditorHeaderChapterButton(
                    chapterTitle: chapterTitle,
                    isSwitcherOpen: isChapterSwitcherOpen,
                    action: onSwitchChapter
                )
            },
            moreTrigger: {
                EditorHeaderMoreButton(
                    showsUnpostedDot: EditorMoreMenuModel.showsUnpostedDot(
                        isPosted: isPosted,
                        hasUnpostedChanges: hasUnpostedChanges
                    ),
                    isPosted: isPosted,
                    action: onMore
                )
            }
        )
    }
}

#Preview("Draft Chapter Header") {
    VStack(spacing: 0) {
        EditorHeader(
            workTitle: "What the Tide Keeps",
            chapterTitle: "Ch. 4 · Slack Water",
            onDone: {},
            onSwitchChapter: {},
            onNotes: {},
            onMore: {}
        )
        Spacer()
    }
    .environment(ThemeManager())
}

#Preview("Posted Chapter Header (Unposted Changes)") {
    VStack(spacing: 0) {
        EditorHeader(
            workTitle: "What the Tide Keeps",
            chapterTitle: "Ch. 3 · Spring Tide",
            isPosted: true,
            hasUnpostedChanges: true,
            showsChangesToggle: true,
            isComparingChanges: true,
            onDone: {},
            onSwitchChapter: {},
            onNotes: {},
            onMore: {},
            onToggleChanges: {}
        )
        Spacer()
    }
    .environment(ThemeManager())
}
