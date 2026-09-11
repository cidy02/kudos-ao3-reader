import SwiftUI

/// Dual-handle numeric range over AO3's existing From/To string bindings.
/// Untouched handles read as "Any" and emit no query bound; dragging a handle
/// to the open edge clears that string so `rangeExpression` stays one-sided.
struct FilterRangeSlider: View {
    @Binding var from: String
    @Binding var to: String
    /// Default right-edge value when both fields are empty. Grows if the typed
    /// numbers exceed it, so the thumbs never pin a larger value to the open
    /// "Any" edge.
    var defaultMaximum: Int

    @Environment(ThemeManager.self) private var theme

    @GestureState private var isDragging = false
    @State private var dragMaximum: Int?
    @State private var dragStartValue = 0

    private enum Handle {
        case lower, upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            track
            fields
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Range")
        .accessibilityValue(accessibilityValue)
        .onChange(of: isDragging) { _, dragging in
            // GestureState also resets on cancellation, which skips onEnded.
            if !dragging { dragMaximum = nil }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let maximum = currentMaximum
            let lowerX = xPosition(for: lowerValue, width: width, maximum: maximum)
            let upperX = xPosition(for: upperValue, width: width, maximum: maximum)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.appTheme.glassFill(0.18))
                    .frame(height: 4)
                if showsSelectedRange {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(upperX - lowerX, 0), height: 4)
                        .offset(x: lowerX)
                }
                thumb(at: lowerX, handle: .lower, width: width, maximum: maximum)
                thumb(at: upperX, handle: .upper, width: width, maximum: maximum)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 11)
        .frame(height: 22)
    }

    private var fields: some View {
        HStack(spacing: 10) {
            boundField("From", text: $from)
            boundField("To", text: $to)
        }
    }

    private func boundField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
            TextField("Any", text: Self.digitsOnly(text))
                .accessibilityLabel(title)
                .font(.system(size: 14, design: .monospaced))
                .monospacedDigit()
            #if !os(macOS)
                .keyboardType(.numberPad)
            #endif
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.appTheme.glassFill(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.appTheme.glassStroke(0.16), lineWidth: 0.5)
                )
        )
    }

    private func thumb(at x: CGFloat, handle: Handle, width: CGFloat, maximum: Int) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .minimumHitTarget()
            .position(x: x, y: 11)
            .gesture(drag(handle, width: width, maximum: maximum))
            .accessibilityLabel(handle == .lower ? "From" : "To")
            .accessibilityValue(handle == .lower ? lowerAccessibilityValue : upperAccessibilityValue)
            .accessibilityAdjustableAction { direction in
                let step = max(maximum / 20, 1)
                let current = handle == .lower ? lowerValue : upperValue
                switch direction {
                case .increment:
                    apply(handle, Self.offsetValue(current, by: Double(step), maximum: maximum), maximum: maximum)
                case .decrement:
                    apply(handle, Self.offsetValue(current, by: -Double(step), maximum: maximum), maximum: maximum)
                @unknown default: break
                }
            }
    }

    private func drag(_ handle: Handle, width: CGFloat, maximum: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if dragMaximum == nil {
                    dragMaximum = maximum
                    dragStartValue = handle == .lower ? lowerValue : upperValue
                }
                let scale = dragMaximum ?? maximum
                let delta = Double(value.translation.width / width) * Double(scale)
                apply(handle, Self.offsetValue(dragStartValue, by: delta, maximum: scale), maximum: scale)
            }
            .onEnded { _ in
                dragMaximum = nil
            }
    }

    private var currentMaximum: Int {
        // The scale must stay fixed during a drag: changing a bound otherwise
        // changes the domain beneath the finger and reverses the thumb's motion.
        dragMaximum ?? Self.expandedMaximum(
            defaultMaximum: defaultMaximum,
            values: [Self.integer(from: from), Self.integer(from: to)].compactMap { $0 }
        )
    }

    private var lowerValue: Int {
        Self.integer(from: from) ?? 0
    }

    private var upperValue: Int {
        Self.integer(from: to) ?? currentMaximum
    }

    private var showsSelectedRange: Bool {
        Self.integer(from: from) != nil || Self.integer(from: to) != nil
    }

    private var lowerAccessibilityValue: String {
        Self.integer(from: from).map(String.init) ?? "Any"
    }

    private var upperAccessibilityValue: String {
        Self.integer(from: to).map(String.init) ?? "Any"
    }

    private var accessibilityValue: String {
        "\(lowerAccessibilityValue) to \(upperAccessibilityValue)"
    }

    private func xPosition(for value: Int, width: CGFloat, maximum: Int) -> CGFloat {
        guard maximum > 0 else { return 0 }
        let clamped = min(max(value, 0), maximum)
        return CGFloat(clamped) / CGFloat(maximum) * width
    }

    private func apply(_ handle: Handle, _ raw: Int, maximum: Int) {
        let clamped = min(max(raw, 0), maximum)
        switch handle {
        case .lower:
            let ceiling = Self.integer(from: to) ?? maximum
            let value = min(clamped, ceiling)
            from = value == 0 ? "" : String(value)
        case .upper:
            let floor = Self.integer(from: from) ?? 0
            let value = max(clamped, floor)
            to = value >= maximum ? "" : String(value)
        }
    }

    /// ASCII digits only — same rule as the panel's old From/To fields. AO3
    /// drops a malformed range silently, which looks like an unfiltered search.
    static func digitsOnly(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = $0.filter { $0.isASCII && $0.isNumber } }
        )
    }

    static func integer(from text: String) -> Int? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Grows past `defaultMaximum` when a typed bound exceeds it, so the thumb
    /// for that number sits inside the track instead of on the open-bound edge.
    static func expandedMaximum(defaultMaximum: Int, values: [Int]) -> Int {
        guard let peak = values.max(), peak > defaultMaximum else { return defaultMaximum }
        return niceCeiling(peak)
    }

    static func niceCeiling(_ value: Int) -> Int {
        // Bounded *before* the conversion back. `8000000000000000000` survives
        // digitsOnly and Int parsing, and ×1.25 then exceeds Int.max — so the
        // Int(_:) trapped while the slider was rendering, crashing the app on a
        // paste into a filter field.
        let expanded = (Double(value) * 1.25).rounded(.up)
        let ceiling = Double(Int.max)
        let target = expanded >= ceiling ? Int.max : Int(expanded)
        let steps = [
            1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000,
            200_000, 500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000,
            20_000_000, 50_000_000
        ]
        return steps.first { $0 >= target } ?? target
    }

    /// Clamp before converting: pasted Int.max bounds, accessibility increments,
    /// and drags past the track must not overflow either Int or its conversion.
    static func offsetValue(_ value: Int, by delta: Double, maximum: Int) -> Int {
        let shifted = (Double(value) + delta).rounded()
        if shifted <= 0 { return 0 }
        if shifted >= Double(maximum) { return maximum }
        return Int(shifted)
    }

    static let wordCountMaximum = 200_000
    static let hitsMaximum = 1_000_000
    static let kudosMaximum = 50_000
    static let commentsMaximum = 10_000
    static let bookmarksMaximum = 10_000
}
