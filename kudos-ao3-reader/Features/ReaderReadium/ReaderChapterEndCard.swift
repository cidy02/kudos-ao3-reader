import SwiftUI

/// The last page of a chapter (Reader-ChapterEnd, T-554): the author's end note cut to four
/// lines with More, the next chapter as the one filled button, Comment on this chapter, and
/// Kudos. Swiping on still turns to the next chapter, so nothing here blocks reading.
///
/// It sits in the reader's bottom chrome (like `ReaderEndCard`), so it never moves the page or
/// the saved position; it shows and hides with the chrome. Kudos is per work on AO3, so once
/// given the button reads "Kudos given". With no end note the note card is absent.
struct ReaderChapterEndCard: View {
    let chapter: Int
    let nextChapterTitle: String
    /// "About 15 min", or nil when the work has no usable per-chapter counts.
    var nextChapterTime: String?
    var endNote: String?
    let footer: String
    /// Comment and Kudos exist only for a work that has an AO3 page.
    var showsAO3Actions: Bool = true
    var kudosGiven: Bool = false
    var kudosEnabled: Bool = true
    /// Cap on the card's height; taller content scrolls inside it.
    var maxHeight: CGFloat = 420
    var onNextChapter: () -> Void = {}
    var onComment: () -> Void = {}
    var onKudos: () -> Void = {}

    @Environment(\.accentFill) private var fill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var noteExpanded = false
    @State private var noteIsTruncated = false
    @State private var clampedNoteHeight: CGFloat = 0
    @State private var fullNoteHeight: CGFloat = 0

    var body: some View {
        // The card is taller than the page's spare room at the largest text sizes, so it
        // scrolls inside itself rather than clipping its buttons.
        ReaderContentCappedScroll(maxHeight: maxHeight) { content }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ReaderChapterEndFacts.heading(chapter: chapter))
    }

    private var content: some View {
        VStack(spacing: 12) {
            headingRule
            if let endNote, !endNote.isEmpty {
                noteCard(endNote)
            }
            nextChapterButton
            if showsAO3Actions {
                actions
            }
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
        }
    }

    private var headingRule: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 0.5)
            Text(ReaderChapterEndFacts.heading(chapter: chapter))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(.separator).frame(height: 0.5)
        }
        .padding(.horizontal, 14)
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Author's note")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(noteExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { clampedNoteHeight = $0 }
                // An unclamped twin, never drawn, tells whether four lines cut the note short.
                .background(
                    Text(note)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { fullNoteHeight = $0 }
                )
                .onChange(of: clampedNoteHeight) { updateTruncation() }
                .onChange(of: fullNoteHeight) { updateTruncation() }
            if noteIsTruncated {
                moreButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func updateTruncation() {
        // Judged only while collapsed; once expanded the button stays so Less is reachable.
        if !noteExpanded { noteIsTruncated = fullNoteHeight > clampedNoteHeight + 1 }
    }

    private var moreButton: some View {
        VStack {
            Button(noteExpanded ? "Less" : "More") {
                withAnimation(reduceMotion ? nil : .snappy) { noteExpanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.accentInk)
            .buttonStyle(.plain)
            .frame(minHeight: 28, alignment: .leading)
            .minimumHitTarget()
            .accessibilityLabel(noteExpanded ? "Show less of the author's note" : "Show all of the author's note")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextChapterButton: some View {
        Button(action: onNextChapter) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(nextChapterTitle)
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.tail)
                    if let nextChapterTime {
                        Text(nextChapterTime)
                            .font(.footnote)
                            .opacity(0.86)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ThemeManager.label(on: fill))
        .background(fill, in: SubjectMetrics.controlShape(dynamicTypeSize))
        .minimumHitTarget()
        .accessibilityLabel(
            [nextChapterTitle, nextChapterTime].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityHint("Goes to the next chapter")
    }

    private var actions: some View {
        let laidOut = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return laidOut {
            ReaderEndSecondaryButton(
                title: "Comment on Ch \(chapter)",
                systemImage: "bubble.left",
                label: "Comment on chapter \(chapter)",
                action: onComment
            )
            ReaderEndSecondaryButton(
                title: kudosGiven ? "Kudos given" : "Give Kudos",
                systemImage: kudosGiven ? "heart.fill" : "heart",
                label: kudosGiven ? "Kudos given" : "Give Kudos",
                isEnabled: kudosEnabled && !kudosGiven,
                action: onKudos
            )
        }
    }
}
