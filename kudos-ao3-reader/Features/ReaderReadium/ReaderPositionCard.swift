#if os(iOS)
import SwiftUI

/// The bottom floating card: page-within-chapter, a slider that seeks within the
/// chapter, and a summary line across the whole work.
struct ReaderPositionCard: View {
    let pageLabel: String
    let chapterTimeLabel: String
    let workLine: String
    let tint: Color
    @Binding var sliderValue: Double
    /// Disabled (and drawn without a thumb-drag affordance) when the chapter has
    /// only one position — nothing to seek within.
    let sliderEnabled: Bool
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(pageLabel)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(chapterTimeLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $sliderValue, in: 0 ... 1, onEditingChanged: onEditingChanged)
                .tint(tint)
                .disabled(!sliderEnabled)
                .accessibilityLabel("Seek within chapter")

            Text(workLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 15)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
#endif
