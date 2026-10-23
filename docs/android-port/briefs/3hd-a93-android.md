# Brief 3hd (Android): A93's five P3s on 3hb

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3hd`, from
the lane's `6c002b44`, which holds your 3hb with three test fixes of Claude's). Do not commit, push, switch
branches, sign in, contact archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit
`TASKS.md`. Write `docs/android-port/briefs/3hd-result.md` first; per item `path:line`, what changed, and per
test what it does with its change reverted. iOS is the reference
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`); read it for each item. The review is
`docs/android-port/audits/A93-result.md` (Claude-CLI). Shots: `/Users/cidy02/kudos-tools/pairs/shots/`
(`i_` iPhone, `a_` Android; `_dark _light _sepia _oled _big`).

Three test fixes landed in 3hb's `Brief3hbContentTest`, worth knowing for new tests:
- **A palette is read from `LocalKudosTokens` inside the content.** A plain variable doesn't recompose
  on a theme change.
- **`compose.waitForIdle()` before reading a value the composition sets.** Kotlin evaluates the
  arguments before the assertion syncs.
- **Check "one line, not ellipsized", not `hasVisualOverflow`.** Robolectric reports sub-pixel overflow.

1. **iOS doesn't pin the field.**
   - The tags editor's field (`GlassFieldBar`) and the collections search are ordinary list rows that
     scroll away under one wash (`Features/Writing/WritingTagsEditor.swift:110`, `:162`;
     `Features/Writing/WorkAssociationPickers.swift:132`).
   - Make Android's the same: no `stickyHeader` for these two (`writing/WritingTagsEditorScreen.kt`,
     `writing/WritingAssociationPickers.kt`), and delete `writing/WritingPinnedFieldGround.kt` if it's
     no longer used.
   - The two wash tests should then check one continuous wash with the list scrolled as well.
2. **Four more pagers miss the page's palette.** iOS passes one, Android passes none:
   - Search results: `SearchView.swift:604` `resultsPalette` → `search/SearchScreen.kt:1073` and
     `:1142` (the palette is at `:296`).
   - An AO3 collection's page: `AO3CollectionDetailView.swift:535` → `AO3CollectionDetailScreen.kt:310`
     (palette `:127`).
   - Moderation: `CollectionModerationView.swift:210` → `AO3CollectionModerationScreen.kt:181` (palette
     `:67`).
   - Prompt meme: `PromptMemeView.swift:454` is title-hued, but `AO3PromptMemeScreen.kt:73` uses the
     app's `scopePalette` for the whole page. Read iOS and match the page's palette, not only the
     pager's.
3. **The reader controls' ink outside Sepia.** 3hb's Sepia uses `theme.appTint`, which is right. In
   Light, Dark and OLED the controls keep `scopePalette.accent`, a derived shade, where iOS uses
   `accentInk(effectiveTint)`. Use `tokens.accentInk` in all four themes
   (`reader/ReaderContentsSheet.kt:104`, `reader/ReaderScreen.kt:1104`, `:1121`).
4. **The reader sheets' cards in Light.**
   - On the iPhone the reader's sheets are glass in Light: their cards are a shade darker than the sheet
     (sampled 195–206 on 226). 3hb's form-ground provider made Android's white in Light, the wrong way.
   - Apply the form ground in Sepia only (cream on tan is right there) for Display
     (`reader/ReaderScreen.kt:1080`), Note (`reader/ReaderNoteEditor.kt:82`) and the Read Aloud sheet
     (`reader/ReaderSpeechSettingsSheet.kt`, which has the same mismatch in Light).
   - For Dark and OLED, sample `i_readerdisplay_dark.png`, `i_readernote_dark.png` and
     `i_readerspeech_dark.png` against the Android shots, and keep whichever ground matches. Write what
     you sampled.
   - Keep the segmented control's white pill in Light: it matches iOS.
   - Pronunciations and backup import stay as they are (opaque on iOS).
   - Update the Light halves of the display and note tests.
5. **Customize Theme's cards** are darker than its sheet (Light #E6E6EA on #F2F2F7, Sepia #E0D3B7 on
   #ECDEC1). The iPhone's are white and cream, an opaque sheet like Pronunciations. Wrap
   `CustomizeThemeContent` in the form-ground provider.

Tests for every behaviour change, each failing with its change reverted.
