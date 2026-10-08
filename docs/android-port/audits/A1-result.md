# A1 result — bugs in Android landings 2026-10-05 to 2026-10-08

Read-only audit of `84520dad^..HEAD` under `android/app/src/main/`, checked against
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. No source was edited, no build, no
AO3 contact. Branch `android/agent-grok-a1` left as it was.

## Findings

| id | severity | location | statement |
|---|---|---|---|
| A1-1 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkForm.kt:179` | Work-form comma lists are split with Kotlin `trim` (`char <= ' '`). iOS strips Foundation whitespaces/newlines. Loaded tags can keep NBSP/ZWSP/U+3000; the tags editor then treats the Foundation-trimmed spelling as a new chip. |

## A1-1 — parser split uses Kotlin trim; iOS and the tags encoder use Foundation trim

### Android

`splitWorkList` is the only splitter the work-form parser uses for fandoms, relationships,
characters, additional tags, collection names and gifts:

```179:188:android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkForm.kt
internal fun splitWorkList(raw: String): List<String> = raw.split(',').map(String::trim).filter(String::isNotEmpty)
internal fun joinWorkList(names: List<String>): String = names.map(String::trim).filter(String::isNotEmpty).joinToString(", ")

/** Foundation whitespacesAndNewlines, rather than Kotlin's extra C0 separators. */
internal fun trimWritingTag(name: String): String = name.trim { char ->
    char in '\u0009'..'\u000d' || char == '\u0020' || char == '\u0085' || char == '\u00a0' ||
        char == '\u1680' || char in '\u2000'..'\u200b' || char == '\u2028' || char == '\u2029' ||
        char == '\u202f' || char == '\u205f' || char == '\u3000'
}
internal fun joinWritingTags(names: List<String>): String = names.map(::trimWritingTag).filter(String::isNotEmpty).joinToString(", ")
```

```122:129:android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/AO3WorkFormParser.kt
            fandoms = splitWorkList(input(AO3WorkFormField.fandoms).orEmpty()),
            relationships = splitWorkList(input(AO3WorkFormField.relationships).orEmpty()),
            characters = splitWorkList(input(AO3WorkFormField.characters).orEmpty()),
            additionalTags = splitWorkList(input(AO3WorkFormField.additionalTags).orEmpty()),
            languageID = selected(AO3WorkFormField.languageID), languageOptions = select(AO3WorkFormField.languageID),
            summary = textarea(AO3WorkFormField.summary), notes = textarea(AO3WorkFormField.notes), endnotes = textarea(AO3WorkFormField.endnotes),
            collectionNames = splitWorkList(input(AO3WorkFormField.collectionNames).orEmpty()),
            gifts = splitWorkList(input(AO3WorkFormField.recipients).orEmpty()),
```

Kotlin `String.trim()` without a predicate drops only `char <= '\u0020'`. U+00A0, U+0085,
U+2000–U+200B and U+3000 stay on the chip. Brief 3bh already switched the tags editor and the
four-tag encoder to `trimWritingTag`; it did not switch this splitter. Collection/gift
*encoding* staying on `joinWorkList` is recorded in `docs/android-port/briefs/3bh-result.md`
and is not this finding.

The tags editor then compares the new Foundation-trimmed name to the stored chip with exact
equality, and excludes suggestions against the stored chip the same way:

```36:39:android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTagsEditorState.kt
internal fun excludesWritingSuggestion(name: String, chosen: List<String>): Boolean {
    val trimmed = trimWritingTag(name)
    return trimmed.isNotEmpty() && chosen.any { it.equals(trimmed, ignoreCase = true) }
}
```

```101:106:android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTagsEditorState.kt
    fun add(name: String = state.value.term) {
        if (!active) return
        val trimmed = trimWritingTag(name)
        val chosen = values()
        if (trimmed.isEmpty() || trimmed in chosen) return // Exact uniqueness; no-op keeps the field.
        onValues(chosen + trimmed)
```

The form row prints that list's size (`WritingWorkFormScreen.kt:136` `workFormCount(form.fandoms)`).

This is not in `docs/android-port/DECISIONS.md` (the 2026-10-05 textarea-wholeText entry is a
different field). 3bh records Foundation trim for the editor and for encoding the four tag
fields, not for parse.

### iOS

```246:250:kudos-ao3-reader/Models/AO3WritingModels.swift
    static func split(_ raw: String) -> [String] {
        raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
```

`parseWorkForm` feeds every comma list through that splitter, including collections and gifts:

```240:261:kudos-ao3-reader/Services/AO3Client+Works.swift
            fandoms: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.fandoms) ?? ""
            ),
            languageID: language.selected,
            languageOptions: language.options,
            categories: categories.selected,
            categoryOptions: categories.options,
            relationships: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.relationships) ?? ""
            ),
            characters: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.characters) ?? ""
            ),
            additionalTags: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.additionalTags) ?? ""
            ),
            collectionNames: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.collectionNames) ?? ""
            ),
            gifts: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.recipients) ?? ""
            ).map { AO3GiftRecipient(name: $0) },
```

Foundation `whitespacesAndNewlines` includes U+00A0, U+0085, U+2000–U+200B and U+3000 (the
set `trimWritingTag` was written to copy). iOS uniqueness then sees one chip.

### Failing case

Served `work[fandom_string]` value `\u00a0Demo Fandom` (NBSP + `Demo Fandom`), otherwise a
new-work form.

1. Android parse: `fandoms == ["\u00a0Demo Fandom"]`. iOS parse: `["Demo Fandom"]`.
2. The Fandoms row shows **1**. Open Fandoms. One chip that looks like `Demo Fandom`.
3. Type `Demo Fandom` and press Return, or tap the canonical suggestion of that name.
4. Android appends a second chip: `"Demo Fandom" in chosen` is false, and
   `excludesWritingSuggestion("Demo Fandom", chosen)` is false because it does not
   Foundation-trim the stored name. The row becomes **2**.
5. iOS already holds `Demo Fandom`; Return is an exact duplicate no-op and the field text
   stays.

The same split applies to relationships, characters, additional tags, collection names and
gifts. Collection/gift rows are display-only in this window; the four tag editors are not.
Save is not landed, so this is not yet a POST. `AO3WorkFormTest.meaning()` also uses Kotlin
`trim`, and the fixtures have no Foundation-only padding, so the suite does not catch it.

### Smallest fix

Point `splitWorkList` at the Foundation helper that 3bh already landed:

```kotlin
internal fun splitWorkList(raw: String): List<String> =
    raw.split(',').map(::trimWritingTag).filter(String::isNotEmpty)
```

Leave `joinWorkList` as 3bh left it. A vector `\u00a0Demo Fandom` → one chip, Return no-op,
belongs next to the existing Foundation-trim tests in `WritingTagsEditorStateTest`.

## Unconfirmed

- **Word count, Java `isAlphabetic` vs ICU `\p{Alphabetic}`.**
  `AO3WordCounter.kt:52-54` uses `Character.isAlphabetic` plus mark/digit/connector
  categories; iOS `AO3WordCounter.swift:52-54` uses `\p{Alphabetic}\p{M}\p{Nd}\p{Pc}`. The
  ported vectors (`Ⓐ`, `Ⅷ`, `０`, `²`, `①`, ZWNJ/ZWJ) match. minSdk 26 ships older Unicode
  data than current iOS. A BMP/supplementary character that is Alphabetic in ICU and not
  `isAlphabetic` on API 26 (or the reverse) would change the editor figure vs AO3. Confirm by
  enumerating against both, not by reading.
- **Named chapter content that is only U+200B.**
  Parser `AO3WorkFormParser.kt:95` uses `textarea(...).takeIf { it.isNotBlank() }` before the
  `textarea#content` fallback. iOS `String.ifEmpty` (`AO3Client+Works.swift:1039-1041`) treats
  Foundation-trimmed empty as empty, and U+200B is in that set; Kotlin `isNotBlank` does not
  treat ZWSP as whitespace, so Android would keep the ZWSP and skip the fallback. Needs a
  fixture with a named blank-looking chapter field and a separate `#content` textarea.
- **`WorkFormDateSheet` vs injectable `today`.**
  The sheet (`WritingWorkFormScreen.kt:360`) calls `LocalDate.now()` for bounds;
  `WritingWorkFormState.publicationDate` / `toggle(Backdate)` use the state's `today()`. In
  production both are device today. Confirm only if a test clock is supposed to drive the
  sheet.

## What was not read

- No Gradle, emulator, Robolectric, or live `archiveofourown.org` request.
- iOS only as cited: `AO3WritingModels.swift`, `AO3Client+Works.swift` (parse/select/radios/
  nested chapter/`ifEmpty`), `AO3WordCounter.swift`, `AO3ChallengeModels.swift` /
  `AO3Client+Challenges.swift` / `AO3ChallengeActions.swift` (tag-set save/reject, prompt-meme
  card, nominations), `PromptMemeView.swift`, `TagSetView.swift`, `ChallengeSettingsView.swift`.
  Not the rest of the iOS tree.
- `DemoNetwork.kt` intercept, autocomplete, and `DemoTagSetWrites`; not every
  collection-items/participants/forms helper in that file.
- Small chrome diffs in `SettingsChrome.kt`, `SubjectComponents.kt`, `SubjectForm.kt`,
  `DebugRoutes.kt`, `AO3Collection.kt` (prompt-meme Manage wiring).
- Tests were read (`AO3WorkFormTest`, `AO3WordCounterTests`, `WritingTagsEditorStateTest`,
  `WritingEditorSessionTests`, `AnnotationTombstoneTest`, `AO3ChallengeSettingsTest`, prompt-meme
  / tag-set screen tests). None were executed.
- Room, backup, search, home, library, and reader UI except `AnnotationRepository.addBookmark`.
- `docs/AO3_NETWORKING_POLICY.md` was used as the network rule; pages were not fetched.

---

## Triage (Claude, 2026-10-08)

One finding and three leads from thirty minutes' reading; exact lines, nothing invented.

- **A1-1: fixed**, at P3 rather than P2. The splitter did trim differently from the editor
  and the encoder, but Kotlin's `trim` is not Java's: it already removes a no-break space
  and U+3000, so the stated failing case (a tag served with a leading no-break space) did
  not fail. What did differ is a zero-width space and NEL, which Foundation's set holds and
  Kotlin's does not. `splitWorkList` now trims with `trimWritingTag`, as iOS's
  `AO3TagListDiff.split` does; one test.
- **Word count on old Unicode data: rejected as known.** Recorded when 3bc landed: the
  counts match on every iOS test vector; a character newer than a phone's Unicode tables
  can count differently, on iOS too.
- **A chapter text holding only a zero-width space: rejected.** It needs a named chapter
  field with only that character beside a second `textarea#content`; on AO3's form the named
  field is `#content`.
- **The date sheet reads the device clock while the form's state takes an injected one:
  rejected.** They differ only under a test clock.

Not read by Grok, so still to audit: Room, backup and sync (A3), the reader and the library
(A5), and all of iOS (A4).

Outcome: one small fix. No P1 or P2 in the code landed 10-05 to 10-08 by this audit; the
bugs found in that code so far were found by running it (the preview, the suggestions that
did not redraw, the missing top row).
