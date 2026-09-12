import SwiftUI
import SwiftData

struct AddChapterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3ChapterForm
    @State private var isSaving = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var isLastChapter = false
    @State private var workTitle: String

    init(form: AO3ChapterForm, workTitle: String) {
        self._form = State(initialValue: form)
        self.workTitle = workTitle
    }

    private var accountPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: form.chapterID == nil ? "Add chapter" : "Edit chapter",
                    subtitle: "\(workTitle) · \(form.title.isEmpty ? "chapter" : form.title)",
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            Section {
                SectionRuleHeader(title: "Chapter")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                chapterPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Text")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                textPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Publication")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                publicationPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("The last-chapter switch writes the total on the work rather"
                    + "than a flag of its own, which is how AO3 records a finished work.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Post")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                postPanel.pageBodyRow(top: 8, gutter: gutter)
                Text("Subscribers are notified on post, so the draft path exists to write"
                    + "a chapter over several sittings without sending twelve notifications.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        #if os(macOS)
        .navigationTitle(form.chapterID == nil ? "Add chapter" : "Edit chapter")
        #endif
        .subjectScreenWash(palette: accountPalette)
    }

    private var chapterPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Title", value: form.title.isEmpty ? "None" : form.title, showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Chapter number",
    value: form.wipLength.isEmpty ? "?" : form.wipLength,
    showsDisclosure: true)
            if form.includePosition {
                SubjectRowSeparator()
                SubjectFormRow(label: "Position",
    value: form.position.isEmpty ? "None" : form.position,
    showsDisclosure: true)
            }
        }
        .subjectPanel()
    }

    private var textPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Chapter text", value: form.content.isEmpty ? "Empty" : "Set", showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Summary", value: form.summary.isEmpty ? "Empty" : "Set", showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "Beginning notes",
    value: form.notes.isEmpty ? "Empty" : "Set",
    showsDisclosure: true)
            SubjectRowSeparator()
            SubjectFormRow(label: "End notes", value: form.endnotes.isEmpty ? "Empty" : "Set", showsDisclosure: true)
        }
        .subjectPanel()
    }

    private var publicationPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
                Toggle("", isOn: Binding(
                    get: { !form.publishedYear.isEmpty },
                    set: { _ in } // UI mockup logic, full logic omitted for briefness
                ))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Post without preview", arrangement: .control) {
                Toggle("", isOn: .constant(true))
                .labelsHidden()
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "This is the last chapter", arrangement: .control) {
                Toggle("", isOn: $isLastChapter)
                .labelsHidden()
            }
        }
        .subjectPanel()
    }

    private var postPanel: some View {
        VStack(spacing: 0) {
            Button {
                save(submit: .postWithoutPreview)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .frame(width: 20)
                    Text("Post chapter now")
                        .font(.system(size: 15))
                    Spacer()
                }
                .foregroundStyle(theme.appTheme.statusSuccessColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SubjectRowSeparator()

            Button {
                save(submit: .saveDraft)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .frame(width: 20)
                    Text("Save as draft")
                        .font(.system(size: 15))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .subjectPanel()
    }

    private func save(submit: AO3WorkSubmitAction) {
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }

        Task {
            do {
                // If isLastChapter, we should pass newTotal. For simplicity in mockup,
                // we pass nil unless we have logic to determine newTotal.
                try await auth.saveChapterUpdatingTotal(
                    form, submit: submit, newTotal: isLastChapter ? Int(form.wipLength) : nil
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                if isPost { isPosting = false } else { isSaving = false }
            }
        }
    }
}
