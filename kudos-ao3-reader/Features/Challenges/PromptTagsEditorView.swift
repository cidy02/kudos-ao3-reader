import SwiftUI

/// Auxiliary editor for tags and prompts within a challenge sign-up.
struct PromptTagsEditorView: View {
    @Binding var prompt: AO3ChallengePrompt
    let palette: SubjectPalette
    let isOffer: Bool
    let index: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    @State private var fandomsText: String = ""
    @State private var relationshipsText: String = ""
    @State private var charactersText: String = ""
    @State private var freeformsText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SubjectHeaderBlock(
                        kicker: isOffer ? "Offer \(index + 1)" : "Request \(index + 1)",
                        title: "Tags",
                        subtitle: "Comma-separated tag names",
                        palette: palette,
                        gutter: SubjectMetrics.accountGutter
                    )
                    .pageBodyRow(top: 20, gutter: 0)
                }

                Section {
                    SectionRuleHeader(title: "Fandoms")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("Good Omens, Supernatural", text: $fandomsText)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    SectionRuleHeader(title: "Relationships")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("Aziraphale/Crowley", text: $relationshipsText)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    SectionRuleHeader(title: "Characters")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("Aziraphale, Crowley", text: $charactersText)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    SectionRuleHeader(title: "Additional tags")
                        .pageBodyRow(top: 18, gutter: 0)
                    tagInputField("slow burn, domestic", text: $freeformsText)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            }
            .cardList()
            #if os(macOS)
            .navigationTitle(isOffer ? "Offer Tags" : "Request Tags")
            #endif
            .subjectScreenWash(palette: palette)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveTags()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                }
            }
            .onAppear {
                fandomsText = prompt.fandoms.joined(separator: ", ")
                relationshipsText = prompt.relationships.joined(separator: ", ")
                charactersText = prompt.characters.joined(separator: ", ")
                freeformsText = prompt.freeforms.joined(separator: ", ")
            }
        }
    }

    private func tagInputField(_ placeholder: String, text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .subjectPanel()
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
