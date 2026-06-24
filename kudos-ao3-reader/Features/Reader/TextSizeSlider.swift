#if os(iOS)
import SwiftUI

/// Text-size control: a slider flanked by a small and large "A", matching the
/// Line/Character Spacing sliders in Customize Theme. Owns the `readerFontPt`
/// setting (absolute point size); the reader applies it live (see `ReaderStylesheet`).
struct TextSizeSlider: View {
    @AppStorage("readerFontPt") private var fontSizePt: Double = ReaderTextStyle.defaultFontSizePt

    var body: some View {
        HStack(spacing: 14) {
            Text("A")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Slider(value: $fontSizePt,
                   in: ReaderTextStyle.fontSizeRange,
                   step: ReaderTextStyle.fontSizeStep)
                .accessibilityLabel("Text size")
                .accessibilityValue("\(Int(fontSizePt.rounded())) points")
            Text("A")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .padding(.vertical, 2)
    }
}
#endif
