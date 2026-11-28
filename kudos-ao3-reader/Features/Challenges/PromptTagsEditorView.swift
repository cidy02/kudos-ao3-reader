import SwiftUI

/// Auxiliary editor for tags and prompts within a challenge sign-up.
struct PromptTagsEditorView: View {
    @Binding var prompt: AO3ChallengePrompt
    let palette: SubjectPalette
    let isOffer: Bool
    let index: Int

    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .body) private var inputFontSize: CGFloat = 16

    @State private var fandomsText: String = ""
    @State private var relationshipsText: String = ""
    @State private var charactersText: String = ""
    @State private var freeformsText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ChallengeBoardSectionHeader(title: "Fandoms")
                        .pageBodyRow(top: 14, gutter: 0)
                    tagInputField("Good Omens, Supernatural", text: $fandomsText, label: "Fandoms")
                        .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    ChallengeBoardSectionHeader(title: "Relationships")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("Aziraphale/Crowley", text: $relationshipsText, label: "Relationships")
                        .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    ChallengeBoardSectionHeader(title: "Characters")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("Aziraphale, Crowley", text: $charactersText, label: "Characters")
                        .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    ChallengeBoardSectionHeader(title: "Additional tags")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("slow burn, domestic", text: $freeformsText, label: "Additional tags")
                        .pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)
                }
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .subjectScreenWash(
                title: isOffer ? "Offer \(index + 1) Tags" : "Request \(index + 1) Tags",
                palette: palette,
                role: .grouped
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        #if os(iOS)
                        Image(systemName: "xmark")
                        #else
                        Text("Cancel")
                        #endif
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ChallengeBoardConfirmToolbarButton(title: "Done") {
                        saveTags()
                        dismiss()
                    }
                }
            }
            .onAppear {
                fandomsText = prompt.fandoms.joined(separator: ", ")
                relationshipsText = prompt.relationships.joined(separator: ", ")
                charactersText = prompt.characters.joined(separator: ", ")
                freeformsText = prompt.freeforms.joined(separator: ", ")
            }
        }
            .screenTint(palette)
    }

    private func tagInputField(_ placeholder: String, text: Binding<String>, label: String) -> some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: text)
                .font(.system(size: inputFontSize))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityLabel(label)
        }
        .challengeBoardCard()
    }

    private func saveTags() {
        prompt.fandoms = splitTags(fandomsText)
        prompt.relationships = splitTags(relationshipsText)
        prompt.characters = splitTags(charactersText)
        prompt.freeforms = splitTags(freeformsText)
    }

    private func splitTags(_ input: String) -> [String] {
        input.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
