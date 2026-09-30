import SwiftUI

/// AO3's preview page, read-only (1bq / 1bo "preview path").
///
/// The actions are the page's own (`_posting_fieldset.html.erb` in preview
/// mode): Edit, and Post — or Update once the work or chapter is posted. Save
/// Draft and Cancel are left to the form this was opened from, which already
/// has both. Post is not a write of its own: it runs the form's existing
/// save path, and the form closes itself (and this) when that succeeds.
struct WritingPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    let preview: AO3PreviewHTML
    let subtitle: String
    /// "Post chapter" / "Post work" / "Update".
    let postTitle: String
    /// Asked before Post when the form asks too — 1bs's "Post this work?".
    var confirmation: (title: String, message: String)?
    let post: () async throws -> Void
    @State private var isPosting = false
    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account", title: "Preview", subtitle: subtitle,
                    palette: theme.scopePalette, gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
                if let notice = preview.notice { footnote(notice) }
            }
            // One row per paragraph, so a long chapter lays out lazily.
            Section {
                ForEach(Array(preview.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block).pageBodyRow(top: 10, gutter: gutter)
                }
            }
            Section {
                SectionRuleHeader(title: "Post").pageBodyRow(top: 18, gutter: 0)
                VStack(spacing: 0) {
                    row(postTitle, icon: "arrow.up.circle.fill", color: theme.appTheme.statusSuccessColor,
                        busy: isPosting) {
                        if confirmation == nil { Task { await runPost() } } else { isConfirming = true }
                    }
                    SubjectRowSeparator()
                    row("Edit", icon: "pencil", color: .primary) { dismiss() }
                }
                .subjectPanel()
                .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .disabled(isPosting)
        #if os(macOS)
        .navigationTitle("Preview")
        #endif
        .subjectScreenWash(palette: theme.scopePalette)
        .alert("AO3 could not post this", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert(confirmation?.title ?? "", isPresented: $isConfirming) {
            Button(postTitle) { Task { await runPost() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(confirmation?.message ?? "") }
    }

    @ViewBuilder
    private func blockView(_ block: AO3PreviewHTML.Block) -> some View {
        switch block {
        case let .heading(text):
            Text(text).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
        case let .label(text):
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .text(document):
            AO3RichTextView(document: document).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runPost() async {
        isPosting = true
        defer { isPosting = false }
        do { try await post() } catch { errorMessage = UserFacingError.message(for: error) }
    }

    /// `WorkEditView.postPanelRow`'s shape.
    private func row(
        _ title: String, icon: String, color: Color, busy: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20).accessibilityHidden(true)
                Text(title).font(.system(size: 15))
                Spacer()
                if busy { ProgressView() }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }
}
