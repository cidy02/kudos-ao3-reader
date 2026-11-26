import Foundation
import SwiftUI

/// Refused gifts list pushed from `WritingRequestsView`. Fetches
/// `GET /users/:login/gifts?refused=true` only when opened or refreshed.
struct WritingRefusedGiftsView: View {
    @Bindable var model: WritingRequestsModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var service: WritingRequestsModel.Service { .live(auth: auth) }

    var body: some View {
        List {
            if let status = model.statusMessage {
                Section {
                    WritingRequestFeedbackBanner(message: status, isError: false) {
                        model.statusMessage = nil
                    }
                    .pageBodyRow(top: 12, gutter: gutter)
                }
            }
            if let error = model.actionError {
                Section {
                    WritingRequestFeedbackBanner(message: error, isError: true) {
                        model.actionError = nil
                    }
                    .pageBodyRow(top: 12, gutter: gutter)
                }
            }

            Section {
                refusedGiftsContent
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Refused Gifts", palette: theme.scopePalette)
        .task(id: auth.sessionGeneration) {
            guard auth.isLoggedIn else { return }
            await model.loadRefusedGifts(page: 1, append: false, using: service)
        }
        .refreshable {
            guard auth.isLoggedIn else { return }
            model.statusMessage = nil
            model.actionError = nil
            await model.loadRefusedGifts(page: 1, append: false, using: service)
        }
    }

    @ViewBuilder
    private var refusedGiftsContent: some View {
        switch model.refusedGiftsPhase {
        case .idle, .loading where model.refusedGifts.isEmpty:
            WritingRequestLoadingPanel(title: "Loading refused gifts…")
                .pageBodyRow(top: 12, gutter: gutter)
        case let .failed(message) where model.refusedGifts.isEmpty:
            WritingRequestErrorPanel(message: message) {
                Task { await model.loadRefusedGifts(page: 1, append: false, using: service) }
            }
            .pageBodyRow(top: 12, gutter: gutter)
        default:
            if model.refusedGifts.isEmpty {
                WritingRequestEmptyPanel(message: "No refused gifts")
                    .pageBodyRow(top: 12, gutter: gutter)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(model.refusedGifts.enumerated()),
                        id: \.element.id
                    ) { index, gift in
                        if index > 0 { SubjectRowSeparator() }
                        WritingRequestGiftRow(
                            gift: gift,
                            refuseAction: false,
                            isSubmitting: model.isSubmitting
                        ) {
                            Task { await model.setGiftRefused(gift, refused: false, using: service) }
                        }
                    }
                }
                .subjectPanel()
                .pageBodyRow(top: 12, gutter: gutter)

                if model.hasMoreRefusedGifts {
                    WritingRequestLoadMoreButton(
                        title: "Load More Refused Gifts",
                        isLoading: model.isLoadingMoreRefusedGifts
                    ) {
                        Task {
                            await model.loadRefusedGifts(
                                page: model.refusedGiftsCurrentPage + 1,
                                append: true,
                                using: service
                            )
                        }
                    }
                    .pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
    }
}

struct WritingRequestGiftRow: View {
    let gift: AO3GiftRow
    let refuseAction: Bool
    let isSubmitting: Bool
    let onAction: () -> Void

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var subtitleSize: CGFloat = 13

    var body: some View {
        let creatorLine = gift.isAnonymous
            ? "by Anonymous"
            : (gift.creators.isEmpty ? "" : "by \(gift.creators.joined(separator: ", "))")
        let fandomLine = gift.work.fandoms.joined(separator: ", ")
        let subtitle = [creatorLine, fandomLine].filter { !$0.isEmpty }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gift.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: subtitleSize))
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if refuseAction {
                Button("Refuse Gift", role: .destructive, action: onAction)
                    .buttonStyle(.kudosSecondary)
                    .tint(.red)
                    .disabled(isSubmitting)
                    .accessibilityLabel("Refuse gift \(gift.title)")
            } else {
                Button("Accept Gift", action: onAction)
                    .buttonStyle(.kudosPrimary)
                    .disabled(isSubmitting)
                    .accessibilityLabel("Accept gift \(gift.title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct WritingRequestLoadingPanel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().accentFill()
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel()
    }
}

struct WritingRequestEmptyPanel: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .subjectPanel()
    }
}

struct WritingRequestErrorPanel: View {
    let message: String
    let onRetry: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.appTheme.errorColor)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: onRetry)
                .buttonStyle(.kudosSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel()
    }
}

struct WritingRequestFeedbackBanner: View {
    let message: String
    let isError: Bool
    let onDismiss: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(isError ? theme.appTheme.errorColor : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Dismiss message")
        }
        .padding(14)
        .subjectPanel()
    }
}

struct WritingRequestLoadMoreButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().accentFill() }
                Text(isLoading ? "Loading…" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accentInk)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .subjectPanel()
    }
}
