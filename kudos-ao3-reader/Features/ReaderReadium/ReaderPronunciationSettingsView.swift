#if os(iOS)
import FluidAudio
import SwiftUI

/// Edit the pronunciation overrides Read Aloud applies before anything else.
///
/// `KokoroPronunciationStore` has always been tier 1 of the phonemizer's
/// resolution order — ahead of the Misaki lexicon and the neural fallback —
/// but nothing could write to it, so a mispronounced name was permanent.
/// This is the surface that fixes that.
///
/// Global layer only, deliberately. The store also carries fandom and work
/// layers, but a reader correcting a name almost always wants it to hold
/// everywhere, and a layer picker on an empty list is a worse first
/// impression than a list that just works.
struct ReaderPronunciationSettingsView: View {
    private let store = KokoroPronunciationStore()

    @State private var entries: [Entry] = []
    @State private var editing: Entry?
    @State private var isAdding = false

    private struct Entry: Identifiable, Equatable {
        var word: String
        var ipa: String
        var id: String { word }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No corrections yet", systemImage: "character.bubble")
                    } description: {
                        Text(
                            "Add a word here to fix how Read Aloud says it. "
                                + "Corrections apply to every work."
                        )
                    }
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            editing = entry
                        } label: {
                            LabeledContent(entry.word) {
                                Text(entry.ipa)
                                    .foregroundStyle(.secondary)
                                    // IPA is easier to compare character by
                                    // character in a fixed-width face.
                                    .monospaced()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Corrections")
                } footer: {
                    Text(
                        "Read Aloud checks these before its own dictionary, "
                            + "so a correction here always wins."
                    )
                }
            }
        }
        .appThemedScroll()
        .appThemedRows()
        .navigationTitle("Pronunciations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            ReaderPronunciationEditor(word: "", ipa: "") { word, ipa in
                save(word: word, ipa: ipa)
            }
        }
        .sheet(item: $editing) { entry in
            ReaderPronunciationEditor(word: entry.word, ipa: entry.ipa) { word, ipa in
                // The word is the key, so a rename is a remove plus an add.
                if word != entry.word { remove(entry.word) }
                save(word: word, ipa: ipa)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        entries = store.overrides()
            .map { Entry(word: $0.key, ipa: $0.value) }
            .sorted { $0.word.localizedStandardCompare($1.word) == .orderedAscending }
    }

    private func save(word: String, ipa: String) {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipa = ipa.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !ipa.isEmpty else { return }
        try? store.setOverride(ipa, for: word)
        reload()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { remove(entries[index].word) }
        reload()
    }

    private func remove(_ word: String) {
        try? store.removeOverride(for: word)
    }
}

/// Add or edit a single override.
///
/// Shared by the settings list and the reader's "Fix Pronunciation" selection
/// action, so a correction made mid-chapter and one made in settings write the
/// same entry through the same path.
struct ReaderPronunciationEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var word: String
    @State var ipa: String
    let onSave: (String, String) -> Void

    /// The phonemes a respelling resolves to, shown live so the reader can see
    /// what will actually be stored before committing to it.
    @State private var preview: String?

    /// Respelling needs the real G2P, which lives behind the voice pack. Ask
    /// the availability flag rather than the installer: `readyManager()` seeds
    /// the cache from GitHub, and a settings text field must never start a
    /// 180MB download as a side effect of typing.
    private var canRespell: Bool { KokoroAneAvailability.isPackInstalled }

    /// What gets stored: pasted phonemes as-is, otherwise the respelling's
    /// conversion, otherwise the raw text so nothing is silently discarded.
    private var resolvedIPA: String {
        let trimmed = ipa.trimmingCharacters(in: .whitespacesAndNewlines)
        if KokoroRespelling.looksLikeIPA(trimmed) { return trimmed }
        return preview ?? trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Word", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("her-MY-oh-nee", text: $ipa)
                        .monospaced()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let preview, preview != ipa {
                        LabeledContent("Phonemes") {
                            Text(preview).monospaced().foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Pronunciation")
                } footer: {
                    // Say what the notation is. A reader who types a respelling
                    // and hears nothing has no way to work out why.
                    Text(
                        canRespell
                            ? "Spell it out in syllables, capitalising the stressed "
                                + "one: her-MY-oh-nee. Phonemes are also accepted."
                            : "IPA phonemes, e.g. hɜɹmˈIəni. Install the Kokoro "
                                + "voice pack to spell pronunciations out instead."
                    )
                }
            }
            .appThemedScroll()
            .appThemedRows()
            .navigationTitle(word.isEmpty ? "Add Pronunciation" : word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(word, resolvedIPA)
                        dismiss()
                    }
                    .disabled(
                        word.trimmingCharacters(in: .whitespaces).isEmpty
                            || ipa.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
        .task(id: ipa) { await updatePreview() }
    }

    /// Convert the respelling on each edit. Cheap enough to run per keystroke:
    /// it is a handful of lexicon lookups, and the model is never invoked.
    private func updatePreview() async {
        let trimmed = ipa.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canRespell, !trimmed.isEmpty, !KokoroRespelling.looksLikeIPA(trimmed) else {
            preview = nil
            return
        }
        guard let manager = try? await CoreMLKokoroPackInstaller.shared.readyManager() else {
            preview = nil
            return
        }
        preview = try? await KokoroRespelling.ipa(forRespelling: trimmed) { syllable in
            try? await manager.phonemes(for: syllable)
        }
    }
}
#endif
