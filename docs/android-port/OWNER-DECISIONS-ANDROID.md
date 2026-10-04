# Kudos Android: questions waiting for the owner

One entry per open product question: what differs, what each choice means, and what Android does
until it is answered. What Claude has already decided is in `DECISIONS.md`.

## 1. The "+" on a light queue colour (T-356)

On a queue with a light colour (Neon reread's light purple), the filled "+" at the top right has a
white glyph on iOS and a black one on Android. iOS's is a system toolbar button, and the system
forces white; two attempts to recolour it failed.

- **A.** Build a custom "+" button on iOS, so both platforms draw a dark glyph on a light fill.
- **B.** Make Android's glyph white, to match iOS as it renders today (harder to read).

Until answered: the two differ.

## 2. The default accent on dark chrome

In Dark and OLED the default accent (AO3 red, `#990000`) is hard to read wherever it is text or a
glyph on the dark page: the tab bar's selected tab, the toolbar's "+", action rows in Settings
("Customize Theme…", "Add Font…", "Check Availability…", "Pair a Device", "Import Files") and a
sheet's selected tab. It is about 2.4 to 1 against black, on both platforms. iOS's system chrome
lifts the colour slightly, to about (173, 20, 20), and draws the selected tab on a neutral pill.
Android draws the exact colour on a pill tinted with the accent, which reads a little worse.

- **A.** Leave both as they are: your colour exactly as picked (T-348).
- **B.** Android only: a neutral pill behind the selected tab, as iOS draws it.
- **C.** Both platforms: lift the accent on dark chrome only (tab bar and toolbar glyphs), keeping
  it exact everywhere else.

Until answered: unchanged.

## 3. Should the toolbar and tab bar follow the hero's colour?

Home and Library now take their accent from the hero work's colour. The toolbar and the tab bar
sit outside the page and keep the app accent, on both platforms.

- **A.** Keep it: chrome in the app accent.
- **B.** The toolbar and tab bar follow the hero's colour too, on Home and Library.

Until answered: A.

## 4. Should iOS's folder sync ignore letter case in EPUB file names?

iOS names a work's EPUB in the sync folder with the UUID in capitals, and both finds and prunes
files by that exact name. The released Android builds (0.2.1, 0.2.2) wrote lowercase names.
Android now writes iOS's names and renames its old files, but an iPhone that joins a folder
before the Android device has updated and synced would not find those EPUBs on case-sensitive
storage, and would delete them from the folder as orphans. (Each Android device still holds its
own copies and uploads them again.)

- **A.** Change iOS to compare names without regard to case, when reading and when pruning. It
  can only ever keep more files. It needs its own tests in `FolderSyncTests`.
- **B.** Leave iOS as it is, and tell Android users to update and sync before adding an iPhone to
  the folder.

**Checked with iOS's own code (2026-10-04):** a folder written by today's Android is read by iOS
in full (`CrossPlatformFolderSyncTests`). The same folder with the files renamed to lowercase,
as the released builds wrote them, reaches iOS **without its EPUBs**.

Until answered: iOS is unchanged. Details: `briefs/5a-result.md`.
