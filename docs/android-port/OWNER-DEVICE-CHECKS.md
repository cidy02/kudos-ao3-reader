# Device checks only you can do

*Draft, 2026-10-22. The owner summary points here.*

These are the checks no emulator or simulator run can make. The emulators run in airplane mode and have no speakers. Claude never signs in to AO3 and has no second phone, no cloud account and no Mac reading session. Everything below was built and tested against saved pages and fixtures only.

Do them in any order. Each says why it needs you, the steps, what passing looks like, and what to write down if it fails.

## Before you start (5 minutes, once)

1. **Builds.** Ask Claude to build and install the newest of each.
   - **Android:** the debug APK from `android/redesign-parity` (`android/app/build/outputs/apk/debug/app-debug.apk`), installed with `adb install -r`.
   - **iPhone:** the build from `integrate/cloud-redesign`. Yours has `e989fd84` from 10-14, which lacks most of the sprint.
   - **Mac:** the Mac app from the same branch (only for check 5).
2. **Back up first.** On every device that holds your real library, export a backup before you begin: Settings › Backup › **Export Backup…**. Keep the file off the phone.
3. **Launch the apps normally,** from the home screen. Never use the debug launch extras (`kudosDemoLibrary`, `kudosDebugRoute`, `-KudosDebugRoute`) on a device with your real library. They switch on the demo data, and one of them (`shot:revokedevice`) writes a fake trusted device.
4. **When something fails, write down:**
   - the device and build;
   - the screen and what you tapped;
   - the exact message;
   - the time;
   - for AO3 actions, whether the change shows on archiveofourown.org.

   Shaking either phone opens **Report a Bug** with a screenshot attached.

## 1. Read Aloud, actually heard

**Why you:** an emulator has no speaker, so Read Aloud on Android has never been heard. It was only checked by its controls and tests.

**Android:**
1. Open a downloaded work and start reading. Open the reader's menu (the fan button) and tap **Read Aloud**.
2. Listen for a minute.
   - Tap the page so the controls hide: a small player should stay on screen.
   - Try Previous and Next: each should move by a chapter.
   - Lock the phone: the notification's controls should work too.
3. In Settings › **Listening**:
   - Set **Engine** to **Device voice** and tap **Play Sample**.
   - Tap **Download Voice Pack** (about 45 MB; use Wi-Fi). Set the Engine to **Kokoro** and play the sample again.
   - Move **Pitch** and the speed, and play again each time.
   - Try "Read author's notes" on a work that has notes.
4. Settings › Listening › **Pronunciations**: add a word you can hear wrongly, with a fix. On Android **the fix is not played yet**: the voice pack ignores it, and the page says so. Pass here means the word is saved and the page tells you that.

**iPhone:** the same, from the reader's fan (a long press opens the speech settings) and Settings › Listening (**Download Kokoro (Neural Engine)** shows only where the iPhone supports it). On the iPhone, a pronunciation fix should be heard.

**Pass:**
- Clear speech from the right place in the text.
- Controls that do what they say.
- No skipped or repeated passages at a chapter change.
- Speed tops out at 1.5×, as on the iPhone.

**If it fails, note:** the engine, the voice, the work, and where in the text it went wrong.

## 2. Signing in, and the AO3 writes

**Why you:** Claude never signs in, so no write has ever reached the real site.

**Safety:** these are real, public actions on your AO3 account.
- Use a throwaway draft for the writing steps, with a title like "Kudos test, please ignore".
- Delete everything you create when you are done.
- **Kudos cannot be taken back on AO3**, so give it only to a work you would anyway.

### Sign in, on both apps
- **Android:** Account › **Log In to AO3**, with your username and password. If it fails, **Use alternative method** opens AO3's own sign-in page in the app; try that and note which one worked.
- **iPhone:** Account › Log In.
- **Pass:** Account shows you signed in and your Works, Bookmarks and Inbox load.

### Then each write

Do these on Android first, then the same on the iPhone. After each one, check archiveofourown.org in a browser.

| Action | Where | Then undo it |
|---|---|---|
| Kudos | a work page (or the reader's fan › Give kudos) | can't be undone |
| Bookmark (tick Private) | a work page › **Bookmark on AO3**; then edit its notes | delete the bookmark |
| Subscribe | a work page, or an author's page | Subscriptions › Unsubscribe |
| A draft work | Account › Drafts (or your own Works) › **New Work** (the "+"). Fill Title, Rating "Not Rated", Fandom "Original Work", the warning "Creator Chose Not To Use Archive Warnings", and a line of text. Save, edit and save again, then **Preview on AO3** | **Delete draft** |
| Post the draft (optional, **public**) | the same form › **Post**. If AO3 offers it, choose "only show to registered users" | **Delete work on AO3** |
| Comment and reply (on your posted test work) | the work's Comments › **Write a comment**; then **Reply** to it; edit one | delete both |
| Add a chapter, Edit tags (optional) | the posted test work's form | deleted with the work |

**Pass:** each one shows on AO3's site as you made it, with nothing missing. Check co-creators, tags and summary. Owner question 17 is about fields a save might drop, so a co-authored draft is the test that settles it.

**Optional, only if you own a test collection:** a collection's settings, Moderation, Maintainers and a challenge sign-up (questions 13–16). Skip these on a real collection.

**If it fails, note:** the action, the app's exact words, and what AO3's site shows. In particular, note any write the app says failed but AO3 shows as done, or the other way round.

## 3. Sync between two real phones through a cloud folder

**Why you:** this needs two real phones and a cloud storage app. Both apps sync a folder correctly as files in tests, both ways, but which cloud works is unproven (question 5). From what Claude could find, Google Drive's Android app does not let another app pick a folder.

**Safety:**
- Back up both phones first.
- Don't press Sync Now on both phones in the same minute (question 6). Nothing is lost if you do, but the folder can list less for a while.

**Steps:**
1. **Pick a storage app** that shows a folder in the system's folder picker on both phones, then make one empty folder in it. Note which app you used and what each picker allowed.
2. **Connect the folder.**
   - **iPhone:** Settings › Sync Folder, choose the folder.
   - **Android:** Settings › Sync Folder › **Choose Sync Folder**, the same folder.
   - Leave **Auto Sync** on.
3. **Pair the phones both ways.** Deletions from a phone that isn't paired are ignored.
   - **iPhone trusts Android:** on Android, Sync Folder › **Pair a Device** › **Show My QR Code**; on the iPhone, Pair a Device › **Scan a QR Code**.
   - **Android trusts the iPhone:** on the iPhone, Pair a Device › **Copy My Key**, then send it to the Android phone (Notes, a message); on Android, Pair a Device › **Advanced: paste a key manually**.
4. **iPhone → Android.**
   - On the iPhone, add a work, read part of it, and highlight a line.
   - Sync Now, wait for the storage app to upload, then Sync Now on Android.
   - **Pass:** the work, its place and the highlight are all on Android.
5. **Android → iPhone:** the same, the other way.
6. **A deletion.**
   - Delete that work on Android and sync both phones.
   - **Pass:** it goes to Recently Deleted on the iPhone too, and does not come back after another sync each way.
   - Repeat with a deletion made on the iPhone.
7. **Known limits, so don't count them as failures** (questions 7 and 21): a highlight, a saved link, or a work taken out of a queue that each phone made on its own may come back. Only note it if something that came by sync comes back.

**If it fails, note:**
- the storage app;
- which phone made the change;
- what each phone's Sync Folder page says (Android shows the last error);
- whether the files appear in the storage app.

## 4. A backup round trip on real devices

**Why you:** the round trip is proven only in tests, with each app reading the other's archives.

**Safety:**
- Use **Merge**, not Replace. Replace swaps the whole library; it has its own review step and keeps an undo copy, but don't use it on your real library for this check.
- Keep the backup you made in "Before you start".

**Steps:**
1. **iPhone:** Settings › Backup › **Export Backup…**. Move the file to the Android phone (cloud folder, email or USB).
2. **Android:** Settings › Backup › **Import Backup…**. Choose the file; the sheet lists what it holds (five counts). Tap **Merge**.
3. **Compare** the Library, queues, collections, a work's reading place, highlights, reading history, fonts and pronunciations.
4. Do the same from Android to the iPhone.

**Pass:** everything arrives once, nothing is duplicated, and places and highlights are where you left them.

**If it fails, note:** the five counts the import sheet showed, and what is missing or doubled.

## 5. The Mac reading-position check

**Why you:** it needs a Mac and an iPhone reading the same work. This is the one open line of the iOS list (Living Prompt §5c item 6b(b), audit A12-1).

**What we know:**
- After the iPhone reads, the Mac opens where the iPhone stopped (fixed in T-364).
- After the **Mac** reads further, the iPhone may still open at its own older place.
- The fix changes where a book opens, so it waits for you to see it first.

**Steps:**
1. The iPhone and the Mac use the same sync folder (Settings › Sync Folder).
2. On the iPhone, read a work to some chapter, then Sync Now. On the Mac, Sync Now and open the work: it should open at the iPhone's place.
3. On the Mac, read on to a later chapter, then Sync Now. On the iPhone, Sync Now and open the work.

**Pass:** the iPhone opens at the Mac's later place.

**If it fails:** if the iPhone opens at its own older place, that is the known fault. Note both chapters, and tell Claude to go ahead with the fix.

## 6. The immersive reader and predictive back on a real Android phone

**Why you:** both are seen only on the emulator. Gesture navigation, a real display cut-out and the system's back animations differ on hardware.

**The immersive reader:**
1. Open a work and read. The status bar and navigation bar should hide.
2. Tap the page: the reader's controls appear and the system bars come back with them.
3. Swipe in from the top or bottom edge: the bars show for a moment and the page does not move.
4. Open Contents or another sheet, or leave the reader: the bars come back.

**Predictive back:**
1. From a pushed screen (a work page opened from the Library), start a back swipe from the screen's edge and hold it. The screen underneath should peek in.
   - Release, and you go back.
   - Swipe back the other way to cancel, and you stay.
2. Try it in the reader, on a sheet (it should close), and on a work form.
   - A work form leaves **without asking** (question 32). The long text comes back from its recovery copy; the short fields don't.
3. If no peek shows on Android 13 or 14, turn on Developer options › **Predictive back animations** and try again.

**Pass:**
- The bars hide and return as described.
- The text never jumps.
- Back always lands on the right screen.
- Nothing is lost except what question 32 describes.

**If it fails, note:** the phone model, the Android version, and gesture or three-button navigation.

## What to send back

One line per check: **pass** or **fail**, with the notes asked for. Also include your answers to whichever owner questions the checks settle: 5 (which cloud), 17 (a co-authored save), 32 (the leave question), 12 (the reader's controls, once you have used them on a phone).
