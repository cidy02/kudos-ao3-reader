import SwiftUI

/// A single-select rail of pill chips, the selected one filled — 1aj's
/// All / Rereads / Offline / WIP and 1bd's All / Unread works. The Authors rail
/// below stays its own view because its chips can be unavailable.
struct SubjectPillRail<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
        }
    }

    private func chip(_ option: Option) -> some View {
        let isSelected = selection == option
        return Button {
            selection = option
        } label: {
            SubjectChip(text: title(option), style: .pill(isSelected: isSelected), palette: palette)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 1ak's Authors-only quick filter. Its parent keeps the cache/prefetch policy;
/// this view only renders the current honest state of that policy.
struct FavoriteAuthorFilterRail: View {
    @Binding var selection: FavoriteAuthorQuickFilter
    let isReady: Bool
    let isUnavailable: Bool
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(FavoriteAuthorQuickFilter.allCases) { option in
                    chip(option)
                }
            }
        }
    }

    private func chip(_ option: FavoriteAuthorQuickFilter) -> some View {
        let isAvailable = isReady || option == .all
        let isSelected = option == .all
            ? selection == .all || !isReady
            : selection == option && isReady
        let title = option == .withNewWork ? newWorkTitle : option.title
        return Button {
            selection = option
        } label: {
            SubjectChip(text: title, style: .pill(isSelected: isSelected), palette: palette)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(title)
        .accessibilityHint(option == .withNewWork && !isAvailable ? unavailableHint : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var newWorkTitle: String {
        if isReady { return FavoriteAuthorQuickFilter.withNewWork.title }
        return isUnavailable ? "Couldn't check new work" : "Checking new work…"
    }

    private var unavailableHint: String {
        isUnavailable
            ? "Couldn't check every author. Switch away and back to retry."
            : "Checking every author before this filter is available."
    }
}
