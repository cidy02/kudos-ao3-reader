import SwiftUI

/// Kudos primary, secondary, and on-gradient button styles (T-485, rule I-9).
///
/// Design system:
/// - Main action: filled capsule. App accent fill (`ThemeManager.effectiveTint`),
///   high-contrast readable label via `ThemeManager.label(on:)`. Destructive stays system red.
/// - Secondary: tinted capsule with a label, or tinted circle when icon-only (rule I-9).
/// - On a gradient: white capsule with an app-colour label.
/// - Two sizes per I-9: 50 pt for full-width or sheet confirm (Login, End of work,
///   onboarding, Resume) and 44 pt otherwise. `minHeight` is used, never fixed height,
///   so text grows to AX5.
public struct KudosButtonStyle: ButtonStyle {
    public enum Variant: Equatable, Sendable {
        case primary
        case secondary
        case secondaryCircle
        case onGradient
    }

    public enum Size: Equatable, Sendable {
        case regular   // 44 pt minHeight (inline, toolbar)
        case confirm   // 50 pt minHeight (full-width or sheet confirm)

        public var minHeight: CGFloat {
            switch self {
            case .regular: 44
            case .confirm: 50
            }
        }
    }

    public let variant: Variant
    public let size: Size

    public init(variant: Variant = .primary, size: Size = .regular, dense: Bool = false) {
        self.variant = variant
        self.size = size
        self.dense = dense
    }

    /// Three labelled buttons in one row (board 35): 15 pt semibold and tighter
    /// sides, so none truncates. Same heights as every other button.
    private let dense: Bool
    private var labelFont: Font { dense ? .subheadline.weight(.semibold) : .headline }
    private var sidePadding: CGFloat { dense ? 10 : (size == .confirm ? 22 : 18) }

    @Environment(\.accentFill) private var envAccentFill
    @Environment(\.accentInk) private var envAccentInk
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isEnabled) private var isEnabled

    private var effectiveAccent: Color {
        if let themeManager {
            return themeManager.effectiveTint
        }
        return envAccentFill
    }

    private var effectiveInk: Color {
        if let themeManager {
            return themeManager.appTheme.accentInk(for: effectiveAccent)
        }
        return envAccentInk
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isDestructive = configuration.role == .destructive
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)

        Group {
            switch variant {
            case .primary:
                let bg = isDestructive ? Color.red : effectiveAccent
                let fg = isDestructive ? Color.white : ThemeManager.label(on: bg)
                configuration.label
                    .font(labelFont)
                    .foregroundStyle(fg)
                    .padding(.horizontal, sidePadding)
                    .padding(.vertical, 8)
                    .frame(minHeight: size.minHeight)
                    .background(bg, in: shape)
                    .contentShape(shape)

            case .secondary:
                let bg = isDestructive ? Color.red.opacity(0.12) : effectiveAccent.opacity(0.12)
                let fg = isDestructive ? Color.red : effectiveInk
                configuration.label
                    .font(labelFont)
                    .foregroundStyle(fg)
                    .padding(.horizontal, sidePadding)
                    .padding(.vertical, 8)
                    .frame(minHeight: size.minHeight)
                    .background(bg, in: shape)
                    .contentShape(shape)

            case .secondaryCircle:
                let bg = isDestructive ? Color.red.opacity(0.12) : effectiveAccent.opacity(0.12)
                let fg = isDestructive ? Color.red : effectiveInk
                configuration.label
                    .font(.headline)
                    .foregroundStyle(fg)
                    .padding(6)
                    .frame(minWidth: size.minHeight, minHeight: size.minHeight)
                    .background(bg, in: Circle())
                    .contentShape(Circle())

            case .onGradient:
                let fg = isDestructive ? Color.red : effectiveAccent
                configuration.label
                    .font(.headline)
                    .foregroundStyle(fg)
                    .padding(.horizontal, size == .confirm ? 22 : 18)
                    .padding(.vertical, 8)
                    .frame(minHeight: size.minHeight)
                    .background(Color.white, in: shape)
                    .contentShape(shape)
            }
        }
        .opacity(configuration.isPressed ? 0.78 : 1.0)
        .opacity(isEnabled ? 1.0 : 0.45)
    }
}

public typealias AppCapsuleButtonStyle = KudosButtonStyle
public typealias AppButtonVariant = KudosButtonStyle.Variant
public typealias AppButtonSize = KudosButtonStyle.Size

extension ButtonStyle where Self == KudosButtonStyle {
    public static var kudosPrimary: KudosButtonStyle {
        KudosButtonStyle(variant: .primary, size: .regular)
    }

    public static var kudosPrimaryConfirm: KudosButtonStyle {
        KudosButtonStyle(variant: .primary, size: .confirm)
    }

    public static var kudosSecondary: KudosButtonStyle {
        KudosButtonStyle(variant: .secondary, size: .regular)
    }

    public static var kudosSecondaryConfirm: KudosButtonStyle {
        KudosButtonStyle(variant: .secondary, size: .confirm)
    }

    public static var kudosSecondaryCircle: KudosButtonStyle {
        KudosButtonStyle(variant: .secondaryCircle, size: .regular)
    }

    public static var kudosSecondaryCircleConfirm: KudosButtonStyle {
        KudosButtonStyle(variant: .secondaryCircle, size: .confirm)
    }

    public static var kudosOnGradient: KudosButtonStyle {
        KudosButtonStyle(variant: .onGradient, size: .regular)
    }

    public static var kudosOnGradientConfirm: KudosButtonStyle {
        KudosButtonStyle(variant: .onGradient, size: .confirm)
    }

    public static func kudos(
        variant: KudosButtonStyle.Variant = .primary,
        size: KudosButtonStyle.Size = .regular,
        dense: Bool = false
    ) -> KudosButtonStyle {
        KudosButtonStyle(variant: variant, size: size, dense: dense)
    }
}

extension View {
    public func kudosButton(
        variant: KudosButtonStyle.Variant = .primary,
        size: KudosButtonStyle.Size = .regular
    ) -> some View {
        buttonStyle(KudosButtonStyle(variant: variant, size: size))
    }
}
