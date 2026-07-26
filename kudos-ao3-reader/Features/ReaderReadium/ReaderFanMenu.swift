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
///
/// As in Apple Books, the button is *replaced by* the menu rather than sitting
/// above it: opening hides the button and the pills take its place, and closing
/// brings it back. Dismissal therefore can't come from the button — the host
/// supplies a tap-anywhere-else backdrop (`ReaderFanMenu.dismissBackdrop`), and
/// VoiceOver uses the standard escape action below.
///
/// The open/close transition is the system's own Liquid Glass morph, not a
/// fade: a `GlassEffectContainer` plus a shared `glassEffectID` per row lets the
/// button's glass shape flow outward into the pills and pour back into the
/// button on dismiss, which is the effect Apple Books uses. Everything inside a
/// container is one glass system, so neighbouring shapes also blend as they
/// separate instead of popping in independently.
struct ReaderFanMenu: View {
    @Binding var isOpen: Bool
    let pills: [ReaderFanMenuPill]
    /// The work's AO3 URL, shared via a native `ShareLink` in the round row's first
    /// slot. nil for works with no AO3 origin (imported EPUBs) — the slot is omitted.
    let shareURL: URL?
    let roundActions: [ReaderFanRoundAction]
    let reduceMotion: Bool

    /// Ties the button's glass to the pills' so the system morphs between them
    /// rather than cross-fading two unrelated shapes.
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 9) {
            content
        }
        // With the button gone while open there is no control to close the menu,
        // so give VoiceOver the standard dismiss gesture (two-finger scrub) it
        // would otherwise get from that button.
        .accessibilityAction(.escape) { close() }
    }

    private var content: some View {
        VStack(alignment: .trailing, spacing: 9) {
            if !isOpen {
                toggleButton
            }

            if isOpen {
                ForEach(pills) { pill in
                    Button {
                        close()
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
                    // The first pill inherits the button's glass identity, so the
                    // button morphs into it; the rest get their own so they read as
                    // separating out of that same shape.
                    .glassEffectID(pill.id == pills.first?.id ? Self.rootGlassID : pill.id,
                                   in: glassNamespace)
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
                        .glassEffectID("share", in: glassNamespace)
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
                        .glassEffectID(action.id, in: glassNamespace)
                        .disabled(!action.isEnabled)
                        .accessibilityLabel(action.accessibilityLabel)
                        .accessibilityHint(action.isEnabled ? "" : "Coming soon")
                    }
                }
            }
        }
        // With the button gone while open there is no control to close the menu,
        // so give VoiceOver the standard dismiss gesture (two-finger scrub) it
        // would otherwise get from that button.
        .accessibilityAction(.escape) { close() }
    }

    /// The glass morph's curve. A gently damped spring, not a linear fade — the
    /// shapes should look like they flow apart and back together. Shared by every
    /// open/close path so the two directions always match.
    static let morph: Animation = .spring(response: 0.34, dampingFraction: 0.82)

    /// Closes the menu, matching the open animation (and skipping it under
    /// Reduce Motion). Shared by the escape action and the host's backdrop.
    static func close(isOpen: Binding<Bool>, reduceMotion: Bool) {
        if reduceMotion {
            isOpen.wrappedValue = false
        } else {
            withAnimation(morph) { isOpen.wrappedValue = false }
        }
    }

    private func close() {
        Self.close(isOpen: $isOpen, reduceMotion: reduceMotion)
    }

    private var toggleButton: some View {
        Button {
            if reduceMotion {
                isOpen = true
            } else {
                withAnimation(Self.morph) { isOpen = true }
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
        .glassEffectID(Self.rootGlassID, in: glassNamespace)
        // Only ever rendered while closed, so the label is unconditional.
        .accessibilityLabel("More")
    }

    /// Shared by the closed button and the first open pill — the identity the
    /// system morphs along.
    private static let rootGlassID = "reader-fan-root"
}

extension ReaderFanMenu {
    /// A full-screen, invisible tap target that closes the open menu — the
    /// dismissal path that the toggle button used to provide before it started
    /// hiding itself (Apple Books' tap-anywhere-else behaviour). Closing the menu
    /// this way leaves the surrounding chrome up, unlike a tap on the page, which
    /// Readium turns into a chrome toggle.
    ///
    /// Host it *beneath* the menu and above the other chrome layers so the first
    /// tap outside the menu dismisses it instead of hitting a control behind it.
    /// Hidden from VoiceOver — a screen-sized invisible button is noise there, and
    /// the menu's own `.escape` action covers dismissal.
    static func dismissBackdrop(isOpen: Binding<Bool>, reduceMotion: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { close(isOpen: isOpen, reduceMotion: reduceMotion) }
            .accessibilityHidden(true)
    }
}
#endif
