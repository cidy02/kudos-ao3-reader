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

    private let guesses = KokoroGuessedWordStore()

    @State private var entries: [Entry] = []
    @State private var guessed: [KokoroGuessedWordStore.Entry] = []
    @State private var editing: Entry?
    @State private var isAdding = false
    @State private var showingImportResult = false
    @State private var importMessage = ""

    private struct Entry: Identifiable, Equatable {
        var word: String
        var ipa: String
        var id: String { word }
    }

    var body: some View {
        List {
            if entries.isEmpty && guessed.isEmpty {
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

            if !guessed.isEmpty {
                Section {
                    ForEach(guessed, id: \.word) { guess in
                        Button {
                            editing = Entry(word: guess.word, ipa: "")
                        } label: {
                            LabeledContent(guess.word) {
                                Text("\(guess.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: dismissGuesses)
                } header: {
                    Text("Words I guessed at")
                } footer: {
                    // Say plainly what the number is, or it reads as a score.
                    Text(
                        "No dictionary had these, so their pronunciation was "
                            + "guessed — usually character names. The number is "
                            + "how often each came up. Tap one to correct it."
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
                Menu {
                    Button { isAdding = true } label: {
                        Label("Add Pronunciation", systemImage: "plus")
                    }
                    Divider()
                    // The `[word](/phonemes/)` notation is shared with
                    // Kokoro-FastAPI and MisakiSwift, so a list kept for
                    // another frontend pastes straight in, and one built here
                    // is worth sharing with someone in the same fandom.
                    Button { importFromClipboard() } label: {
                        Label("Paste Corrections", systemImage: "doc.on.clipboard")
                    }
                    Button { copyAll() } label: {
                        Label("Copy All", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Pasted Corrections", isPresented: $showingImportResult) {
            Button("OK") {}
        } message: {
            Text(importMessage)
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
        // Anything already corrected is no longer a guess — it resolves from
        // tier 1 now — so keep it out of the list even if the store still has
        // it from before the correction.
        let corrected = Set(entries.map(\.word))
        guessed = guesses.ranked().filter { !corrected.contains($0.word) }
    }

    private func save(word: String, ipa: String) {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipa = ipa.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !ipa.isEmpty else { return }
        try? store.setOverride(ipa, for: word)
        // A corrected word stops being a guess, so drop it rather than
        // leaving it to be re-offered.
        try? guesses.forget(word)
        reload()
    }

    /// Read `[word](/phonemes/)` entries from the clipboard.
    ///
    /// Reports what happened either way: a silent no-op on a paste that did
    /// not parse leaves the reader with no idea whether the app or their text
    /// was at fault.
    private func importFromClipboard() {
        let text = UIPasteboard.general.string ?? ""
        let parsed = KokoroInlinePronunciation.entries(in: text)
        guard !parsed.isEmpty else {
            importMessage = text.isEmpty
                ? "The clipboard is empty."
                : "No corrections found. The format is [word](/phonemes/)."
            showingImportResult = true
            return
        }
        // Last wins on duplicates — the parser preserves them deliberately so
        // this choice is made here rather than hidden in the parse.
        for entry in parsed {
            try? store.setOverride(entry.phonemes, for: entry.word)
            try? guesses.forget(entry.word)
        }
        importMessage = parsed.count == 1
            ? "Added 1 correction."
            : "Added \(parsed.count) corrections."
        showingImportResult = true
        reload()
    }

    /// Put every correction on the clipboard in the shared notation.
    private func copyAll() {
        let rendered = KokoroInlinePronunciation.text(
            for: entries.map { .init(word: $0.word, phonemes: $0.ipa) }
        )
        UIPasteboard.general.string = rendered
        importMessage = entries.count == 1
            ? "Copied 1 correction."
            : "Copied \(entries.count) corrections."
        showingImportResult = true
    }

    /// Swiping a guess away means "stop offering me this one".
    private func dismissGuesses(at offsets: IndexSet) {
        for index in offsets { try? guesses.forget(guessed[index].word) }
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
