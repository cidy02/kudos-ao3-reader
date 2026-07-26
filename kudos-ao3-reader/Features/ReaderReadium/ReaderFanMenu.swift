#if os(iOS)
import SwiftUI

/// One labelled row in the fanned-out menu (Contents, Bookmarks & Notes, Find,
/// Themes & Settings).
struct ReaderFanMenuPill: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// False for capabilities not yet wired up (e.g. Find in Work before its
    /// search integration lands) — shown, but inert and visibly dimmed rather
    /// than silently doing nothing.
    var isEnabled = true
    let action: () -> Void
}

/// One round action button in the fan's bottom row (share, kudos, read aloud,
/// bookmark).
struct ReaderFanRoundAction: Identifiable {
    let id: String
    let systemImage: String
    let tint: Color
    let accessibilityLabel: String
    var isEnabled = true
    let action: () -> Void
}

/// The top-right "more" button that fans open into labelled menu pills plus a row
/// of round quick actions, all right-aligned below it. Modeled on Apple Books' own
/// reading-options glyph (three list bars over three dots).
struct ReaderFanMenu: View {
    @Binding var isOpen: Bool
    let pills: [ReaderFanMenuPill]
    /// The work's AO3 URL, shared via a native `ShareLink` in the round row's first
    /// slot. nil for works with no AO3 origin (imported EPUBs) — the slot is omitted.
    let shareURL: URL?
    let roundActions: [ReaderFanRoundAction]
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            toggleButton

            if isOpen {
                ForEach(pills) { pill in
                    Button {
                        isOpen = false
                        pill.action()
                    } label: {
                        HStack(spacing: 12) {
                            Text(pill.title)
                                .font(.system(size: 15.5))
                                .foregroundStyle(pill.isEnabled ? .primary : .secondary)
                            Spacer(minLength: 8)
                            Image(systemName: pill.systemImage)
                                .foregroundStyle(pill.isEnabled ? .primary : .secondary)
                        }
                        .padding(.horizontal, 18)
                        .frame(width: 264, height: 46)
                        // .plain draws no background of its own, so without this the
                        // only tappable parts are the glyphs themselves and taps in
                        // between fall through to the page.
                        .contentShape(.capsule)
                    }
                    // .plain so the label keeps its own .primary/.secondary
                    // foreground — the default button style tints it with the accent.
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .capsule)
                    .disabled(!pill.isEnabled)
                    .accessibilityLabel(pill.title)
                    .accessibilityHint(pill.isEnabled ? "" : "Coming soon")
                }

                HStack(spacing: 9) {
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17))
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 46)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityLabel("Share")
                    }
                    ForEach(roundActions) { action in
                        Button(action: action.action) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 17))
                                .foregroundStyle(action.isEnabled ? action.tint : Color.secondary)
                                .frame(width: 52, height: 46)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular, in: .capsule)
                        .disabled(!action.isEnabled)
                        .accessibilityLabel(action.accessibilityLabel)
                        .accessibilityHint(action.isEnabled ? "" : "Coming soon")
                    }
                }
            }
        }
    }

    private var toggleButton: some View {
        Button {
            if reduceMotion {
                isOpen.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            }
        } label: {
            VStack(spacing: 3) {
                VStack(spacing: 2.5) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.1).frame(width: 22, height: 2.2)
                    }
                }
                HStack(spacing: 5.5) {
                    ForEach(0 ..< 3, id: \.self) { _ in Circle().frame(width: 2.6, height: 2.6) }
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            // The glyph is thin bars and small dots; without an explicit content
            // shape a .plain button only accepts taps that land on the strokes,
            // well short of the 44pt target.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .accessibilityLabel(isOpen ? "Close menu" : "More")
    }
}
#endif
