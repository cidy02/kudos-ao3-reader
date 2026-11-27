import SwiftUI

/// The shareable card: numbers only (words, minutes, date). No title, no text from the story.
/// Fixed sizes on purpose: this is an image, not on-screen UI, and it renders the same everywhere.
struct SprintShareCard: View {
    let words: Int
    let minutes: Int
    let date: Date

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.51, green: 0.063, blue: 0.098), Color(red: 0.23, green: 0.169, blue: 0.247)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(words.formatted())
                .font(.system(size: 72, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(words == 1 ? "word" : "words")
                .font(.system(size: 22, weight: .semibold))
            Text("in \(minutes) \(minutes == 1 ? "minute" : "minutes")")
                .font(.system(size: 20))
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 16))
                .opacity(0.8)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
        .frame(width: 360, height: 240)
        .background(Self.gradient)
        .environment(\.colorScheme, .dark)
    }

    @MainActor
    static func image(for result: SprintResult) -> Image? {
        let renderer = ImageRenderer(
            content: SprintShareCard(words: result.words, minutes: result.minutes, date: result.endedAt)
        )
        renderer.scale = 3
        guard let rendered = renderer.cgImage else { return nil }
        return Image(decorative: rendered, scale: 3)
    }
}

/// Sprint Done (`Phone-Sprint.dc.html`): the words, the time, a bar per five minutes, Share Result,
/// Another N Minutes, Back to Writing. It scrolls, so every control stays reachable at AX5.
struct SprintDoneSheet: View {
    let result: SprintResult
    let onAnother: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?
    @ScaledMetric(relativeTo: .footnote) private var thumbnailSize: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                SprintBars(buckets: result.buckets)
                shareRow
                VStack(spacing: 10) {
                    Button {
                        dismiss()
                        onAnother(result.plannedMinutes)
                    } label: {
                        Text("Another \(result.plannedMinutes) Minutes")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accentFill()

                    Button { dismiss() } label: {
                        Text("Back to Writing")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
        .task(id: result.id) { shareImage = SprintShareCard.image(for: result) }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Sprint done")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondaryInk)
            Text("\(result.words.formatted()) \(result.words == 1 ? "word" : "words")")
                .font(.largeTitle.weight(.heavy))
                .monospacedDigit()
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let time = "in \(result.minutes) \(result.minutes == 1 ? "minute" : "minutes")"
        return result.isBestThisWeek ? "\(time) · your best this week" : time
    }

    @ViewBuilder
    private var shareRow: some View {
        if let shareImage {
            let thumb = min(thumbnailSize, 72)
            ShareLink(item: shareImage, preview: SharePreview("Writing sprint", image: shareImage)) {
                HStack(spacing: 12) {
                    Text(result.words.formatted())
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(4)
                        .frame(width: thumb, height: thumb)
                        .background(SprintShareCard.gradient, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share Result").font(.headline)
                        Text("A card with your words, minutes and date. Nothing from your story.")
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share Result")
            .accessibilityHint("Shares an image with your words, minutes and date")
        }
    }
}

/// One bar per five minutes; the busiest slice is full strength.
private struct SprintBars: View {
    let buckets: [Int]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var tallest: CGFloat = 44

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At AX5 a 45-minute sprint's nine columns crush their minute labels on compact widths.
                ScrollView(.horizontal, showsIndicators: false) {
                    barsRow(minBarWidth: 44)
                }
            } else {
                barsRow(minBarWidth: nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words per five minutes: " + buckets.map(String.init).joined(separator: ", "))
    }

    private func barsRow(minBarWidth: CGFloat?) -> some View {
        let maxWords = buckets.max() ?? 0
        let peak = max(maxWords, 1)
        return HStack(alignment: .bottom, spacing: buckets.count > 5 ? 6 : 10) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, words in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.tint)
                        .opacity(maxWords > 0 && words == maxWords ? 1 : 0.35)
                        .frame(height: 12 + CGFloat(words) / CGFloat(peak) * tallest)
                    Text("\((index + 1) * 5)′")
                        .font(.caption2)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(minWidth: minBarWidth, maxWidth: .infinity)
            }
        }
    }
}
