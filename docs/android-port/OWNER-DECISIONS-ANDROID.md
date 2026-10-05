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

*2026-10-05: on Android the tab bar and the toolbar no longer show this. The new navigation bar
and buttons draw a lighter glyph on an accent-tinted ground (see question 11). What is left on
Android is the action rows in Settings and a sheet's selected tab; iOS is unchanged.*

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

## 4. iOS's folder sync was changed (T-357): keep it?

You asked for the two apps to be fully interoperable on one folder. The audit found four ways
the **iOS** app could delete another device's files from a shared folder, so iOS was changed too
(`91f3930f` on `claude/polish-loop`, `ef120853` on `integrate/cloud-redesign`, not pushed):

- An automatic upload now reads the folder first. It used to write a manifest that did not list
  what another device had added, and a later sync then deleted that device's EPUB.
- A folder with files and no manifest is no longer treated as empty.
- A manifest whose date cannot be read no longer allows deleting.
- EPUBs are found whether their name is in capitals or lowercase (the old question 4, option A).
- A manifest cut short by an interrupted write is repaired instead of failing every sync after.

Tested: the nine iOS suites that sync a folder (73 tests), lint, and a macOS build. **Not tried
on an iPhone or with a real cloud provider.**

- **A.** Keep it (my recommendation: each change only ever keeps more files).
- **B.** Revert it, and accept that a shared folder is not safe.

Until answered: the change stays on the two local branches.

## 5. Which cloud storage should a shared folder use?

The apps do not talk to any cloud service. Each one reads and writes a folder that the system's
file picker hands it, and a storage app keeps that folder in step with the cloud. Whether that
works depends on the storage app, and I could not test any: the emulators stay in airplane mode
and the phones are yours.

- **Google Drive:** from what I could find, Drive's Android app does not let another app pick a
  folder, so Kudos on Android cannot use a Drive folder directly. Not checked on a device.
- **On iOS** it depends on the storage app: some let another app pick a folder, some do not.

- **A.** You try it: pick one storage app that offers a folder on both phones, and tell me what
  the pickers allow. I then test the apps against what you find.
- **B.** Build a direct Google Drive connection into both apps. A large piece of work, with a
  Google sign-in.
- **C.** Support only folders a separate sync tool mirrors (on Android, a folder on the phone that
  another app keeps in step with the cloud).

Until answered: both apps sync a folder correctly as files; which cloud is unproven.

## 6. Two devices syncing in the same minute

Each app now stops, or declines to delete, when it sees the folder changed under it. Neither can
see a change that has not reached it yet, so two devices that sync at the same moment can still
write over each other's manifest. Nothing is deleted when that happens, and the next sync of
each device puts its records back, but for a while the folder lists less than it holds.

- **A.** Accept it (my recommendation for now): the window is seconds, and nothing is lost.
- **B.** Design a safer scheme, such as one manifest per device. That is a change to the folder's
  format, on both apps, and older versions of the apps would not understand it.

Until answered: A.

## 7. Deletions an iPhone and an Android phone do not tell each other about

Two things, both found by the audit:

- **Pairing.** A device takes another's deletions only after the two are paired. iPhones on one
  Apple account pair by themselves; an Android phone never does. Until you pair an iPhone and an
  Android phone both ways, each ignores what the other deletes, and a deleted work comes back.
  Android's page now says so. iOS's page still says only "for a different account, scan its QR
  code". **Should iOS's text mention Android?**
- **Saved links, highlights, and works taken out of a queue or collection.** When one device
  deletes a saved AO3 link or a highlight, or takes a work out of a queue or a collection, the
  other device keeps its copy and puts it back in the folder. The first device ignores it, so
  the two disagree for good. Both apps behave this way today, iPhone to iPhone as well. (A
  deleted work, queue or collection does travel; so do saved searches and reading history.)
  **Should both apps remove their copy when a paired device deletes one?** Codex has written
  the queue part for Android; it waits for this answer.

Until answered: unchanged on both.

## 8. Three places where Android is deliberately stricter or iOS would have to change

- **A later deletion of the same record.** iOS lets a later signed deletion replace the one it
  holds even when the work's AO3 number or address differs. Android (Codex's change) refuses
  then, so a paired device cannot swap a deletion for one that covers less. Keep Android
  stricter, or match iOS?
- **Dates from the future.** Android does not let a record's date be later than its backup's
  date. iOS takes the date as written, so one stale backup with a wrong date can block real
  edits on iOS for good. The fix belongs on iOS. May I make it?
- **Sizes.** iOS accepts an EPUB of up to 1 GB in a backup. Android stops at 128 MB, and reads a
  whole backup into memory. A very large library restores on iOS and fails on Android. Raising
  Android's limit needs the restore rewritten to read from disk. Worth doing now?

Until answered: Android stricter, iOS unchanged, limits unchanged.

## 9. Two things Android's Backup page has that iOS's does not

The Backup page is now drawn as iOS's. Two things on it are Android's own, and I kept both
rather than remove anything without you:

- **Two blocks of technical notes** under the footer ("Export writes ZIP packages at manifest
  v8…", "AO3 cookies, CSRF tokens, and session files are excluded…"). iOS shows one plain
  paragraph.
- **The pairing section** ("Deletion signing"). iOS has it only on the Sync Folder page; Android
  shows the same section on both pages.

- **A.** Remove both from the Backup page, to match iOS.
- **B.** Keep them.

Until answered: kept.

## 10. An emptied section on the Library's front page (both apps)

Turn on a filter that hides every work in a section, and the Library's front page says, for
that section, "You haven't saved any works for later. Add a work to Saved for Later to see it
here." That is not true: the works are there, hidden by the filter. **iOS says the same**, so
Android was left saying it too. Inside a section's own list both apps now show the proper card
("Nothing matches this filter", how many works are hidden, which filter to drop).

- **A.** On both apps, an emptied section on the front page says its works are hidden by the
  filters.
- **B.** Leave both as they are.

Until answered: B.

## 11. Which design rule governs Android: the June Material documents, or the iOS redesign?

Two sets of instructions in the repository pull in different directions.

- **The June documents** (`docs/contracts/KUDOS_ANDROID_INTERFACE_GUIDELINES.md`,
  `ANDROID_MATERIAL_HIG_TRANSLATION.md`, `CROSS_PLATFORM_UI_BRIDGE.md`, all dated 2026-06-27):
  keep iOS's behaviour and order of information, but draw it with Material 3's own parts: a
  standard bottom navigation bar, standard top app bars, Material cards and chips, Material
  text sizes. They list "literal iOS visual clones", "Apple tab bar visuals" and
  "Apple-specific translucency" as things to avoid. They do not mention Material You by name,
  or colours taken from the wallpaper.
- **This lane's mission** (October): complete redesign parity with iOS, each screen checked
  against the iOS screen and its artboard.

What the app does today follows the mission, not the June documents: a floating glass tab bar
with a separate Search circle, no Material top app bar anywhere (29 files use the redesign's
header instead), the redesign's panels in 31 files against Material cards in 8, no colours from
the wallpaper, and most text set to explicit sizes. Screens "still in the old Material design"
have been treated as faults and converted. The June documents also ask for a line in every
Android brief telling the agent to read them; this lane's briefs have not carried it.

Where the two agree, the lane already complies: Search is a separate action and not a fifth
tab, filters and sorts open as bottom sheets, confirmations are dialogs, AO3's rating and
warnings stay visible on cards, system Back and text size are honoured.

- **A.** The redesign governs (as now). The June documents get a note at the top saying the
  redesign replaced their visual rules, and their behaviour rules stay.
- **B.** The June documents govern. The redesigned chrome (tab bar, headers, panels) goes back
  to Material 3 parts, keeping the redesign's layout and content. This is a large change to
  work already landed.
- **C.** A mix you name: for example Material's bottom bar and top bars, the redesign's
  everything else; or colours from the wallpaper as an option in Appearance.

**Answered 2026-10-04: a mix.** "while i want the Kudos app to feel like one cohesive product
across platforms, i also don't want android to look like an attempt to clone iOS. let's give
Android native feeling tab bar and chrome buttons". Done on 2026-10-05: a Material navigation
bar and Material icon buttons; everything else as the redesign has it. A picture of before and
after is at `~/kudos-tools/out/android-native-chrome-before-after.png`. Question 12 holds what
that left open.

## 12. After the native tab bar and buttons: three things to say yes or no to

- **The reader's controls** (the round back and menu buttons, the title capsule, the page card)
  are still drawn as glass, iOS's way. Make them Android's too? Until answered: left as they
  are.
- **Search is the fifth tab**, and its page now keeps the bar like the other four. The June
  documents wanted Search as a separate action instead (a floating button, or an icon at the
  top of each tab). Until answered: a tab.
- **The bar stays in place when a list scrolls.** iOS's shrinks to one button to give the list
  room; Material allows a bar that slides away on the way down and returns on the way up. Until
  answered: it stays.

## 13. The collection moderation screen: three things

Built on 2026-10-05 to match iOS's (Account › Collections › a collection you maintain › Manage ›
Moderation). It has never been run against AO3 on either app.

- **A question before sending.** iOS sends the staged changes when Submit is tapped. Android
  first asks "Submit N staged changes to AO3?". The staged changes can remove a work from a
  collection, and Android's Submit is a small tick in the top corner. Keep the question on
  Android, add it to iOS too, or drop it? Until answered: Android asks, iOS does not.
- **One request per item.** Both apps send one request for each item you changed, one after
  another. AO3's own page sends them all in one. One would be lighter on AO3 and either all or
  none would go through. Change both apps to send one? Until answered: one per item, as iOS.
- **After AO3 refuses one.** Android reads the list again so it shows what AO3 took before the
  refusal; iOS leaves the list as it was until you refresh. Make iOS do the same? Until
  answered: they differ.
