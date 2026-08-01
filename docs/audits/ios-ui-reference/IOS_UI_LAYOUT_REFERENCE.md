# iOS Kudos UI layout reference (screenshot analysis)

**Date:** 2026-08-01  
**Source:** ~31 human-captured iPhone screenshots of the current Kudos iOS app  
**Purpose:** Visual / structural SoT for Android Material 3 parity work.  
**Policy:** Express the same **information hierarchy and navigation**, not pixel-clone SwiftUI.  
**Android branch:** `android/sync-from-hig-review`  
**Images:** organized under this directory’s category folders (see [IMAGE_INDEX.md](IMAGE_INDEX.md)).

---

## App shell (all tabs)

| Element | iOS behavior |
|---|---|
| Bottom tabs | **Home · Library · Browse · Account** (+ floating **Search** FAB/orb) |
| Large title | Root tabs use large white title (Home / Library / Browse / Account) |
| Trailing chrome | Pill of icon buttons (eye, list/select, ⋯, gear) — **not** a cluttered text app bar |
| Accent | AO3 red on selected tab, progress, primary actions |
| Background | Near-black OLED-friendly dark |

Android should keep MD3 NavigationBar + Search affordance, but **match this hierarchy**: large title feel, icon-cluster trailing actions, red accent, dense cover cards.

---

## Category A — Home

**Layout top → bottom**

1. Large title **Home** + trailing pill (privacy eye · ⋯)  
2. Section **Reading Now** — collapse chevron · see-all `>`  
3. Horizontal **cover-card carousel** (fixed card size)  
4. Section **Recently Updated** — same carousel pattern  
5. Section **Subscriptions** — remote cards (may be sparser: title + author only)  
6. Section **Favorites** — empty state with star icon + copy  
7. Section **Recently Opened** — cover carousel  

**Cover card anatomy (local)**

- Colored wash background (hue from title)  
- Title (2 lines) · ⓘ details  
- Author row (person icon)  
- Fandom row (books icon) · thin divider  
- Stats one-per-row: rating shield · chapters · complete · words  
- Footer: “Reading” + % + progress bar  

**Empty section:** icon + one-line secondary copy (e.g. Favorites).

**Android gap:** Home carousels exist; trailing privacy/overflow chrome, collapsible headers with `>`, and remote subscription card density still differ.

---

## Category B — Library

**Layout top → bottom**

1. Large title **Library** + trailing pill (**eye · list · ⋯**)  
2. **Fandom filter chips** horizontal: All (filled red) · fandom names  
3. Sections (collapsible + see-all):  
   - **Reading Now** (cards + progress)  
   - **Saved for Later**  
   - **Finished** (may show obscured “Tap to reveal” mature cards)  
   - **Reading Queues** — dashed **+ New Queue** tile  
   - **Collections** — dashed **+ New Collection** tile  
   - **Downloaded**  
   - **Reading History** (often obscured mature)  

**Overflow ⋯ menu**

- Reading Insights  
- Select  

**Long-press context menu on a cover card**

1. Read  
2. Comments  
3. Select  
4. Remove from Saved  
5. Favorite  
6. Save for Later  
7. Add to Queue  
8. Mark as Finished  
9. Add to Collection  
10. Work Details  

**Android gap:** Carousel shelves started; missing fandom chip bar, queue/collection create tiles, full context menu, collapse/see-all headers, mature “tap to reveal” cards, toolbar pill matching iOS.

---

## Category C — Browse

**Layout**

1. Large title **Browse** + trailing compass (open AO3 website)  
2. Header **Browse by fandom**  
3. Full-width category cards (tappable whole row):  
   - Icon + name  
   - Stats line: fandom count · ~works · saved count  
   - Optional **Recently read** chip row  
   - Trailing chevron  

**Android gap:** Categories exist; missing rich stats line, category icons, recently-read chips, compass-only toolbar.

---

## Category D — Account

**Not a plain Settings list.** Structure:

### Header
- Avatar · username · green verified check  
- “Posting as Account D…” pseud picker · ⋯  
- Trailing toolbar: eye · ⋯ · **gear (Settings)**  

### Segmented tabs
**Overview | Reading | Writing | Activity**

### Overview
- **Shortcuts** 2×3 grid:  
  My Dashboard · My Subscriptions · My Works  
  My Bookmarks · My Collections · My History  
- **Account** list: Preferences · More on AO3  

### Reading tab
- Dropdown selector: Marked for Later · Subscriptions · Bookmarks · Collections  
- Filters chip  
- Grid/list of **cover cards** for that list  

### Writing tab
- Dropdown: Works · Series · Drafts  
- Fandom chips (All · …)  
- Cover cards for own works  

### Activity tab
- Dropdown: History · Inbox  
- Cover cards  

**Android gap:** Flat Form sections only. Needs profile header, tabs, shortcut grid, segmented list browser.

---

## Category E — Work Detail

**Highest visual mismatch vs current Android.**

### Chrome
- Back · title · ★ favorite · ⋯  

### Sticky header card
- Title  
- Author (tappable, red)  
- Fandom (books icon)  
- Compact meta: rating · chapters · status · words  

### Segmented tabs
**Overview | Tags | Discussion | Library**

### Overview tab
1. **Summary** prose card  
2. **Quick Actions** 3-column icon grid:  
   - Continue Reading / Download & Read  
   - Open on AO3  
   - Saved (toggle state)  
   - Save for Later  
   - Add to Queue  
   - Add to Collection  
   - Mark as Finished  
   - Comments (count badge)  
3. **Publication** Labeled rows: Published · Updated · Language · Added · Source  
4. **Work** rows: Rating · Category · Status · Words · Chapters  
5. **Stats** rows: Hits · Kudos · Comments (red link)  
6. **Origin** AO3 URL  

### Tags tab
- Archive Warnings chips  
- Fandoms chips  
- Relationships chips  
- Characters chips  
- Additional Tags chips  
- Footer: tap tag → search AO3  

### Discussion tab
- All Comments (count) ›  
- Chapter Comments ›  
- Write a Comment ›  
- Note: comments load on demand  

### Library tab
- **Status** rows with checkmarks: Saved · Save for Later · Add to Queue · Add to Collection · Mark as Finished  
- Footer status string  
- **Storage**: Download · size  
- **Activity**: Added · Last Opened · Progress bar  
- **My Tags**: empty + add · suggested chips · privacy footer  

**Android gap:** Single scroll + Form action list. Needs tab shell + Quick Actions grid + structured metadata cards.

---

## Category F — Settings

Grouped Form (scroll):

| Section | Controls |
|---|---|
| AO3 Account | Signed In username · Log Out |
| Theme | Light / Sepia / Dark / OLED · Match App & Reader · Accent Color |
| Appearance | Customize Theme… |
| Text Size | A—A slider |
| Reading | Scrolled / Paged |
| Read Aloud | Voice · Speed · Pitch |
| Font | System… + custom · Add Font… |
| Library | Confirm before deleting |
| Backup | Export · Import |
| Library Sync Folder | Metadata · Folder · Auto Sync · Sync Now · Change · Details · Disconnect · timestamps *(iOS iCloud path — Android: SAF folder or omit)* |
| Import | Import Files (EPUB/HTML/txt) |
| Preservation | Check Availability… |
| Reading Queues | Queue Storage · Auto-preserve small series · Series limit · Add Saved Works… |
| Privacy | Hide mature · Blur/Hide · Face ID · Privacy & Local Data |
| Help & Project | About · Report a Bug · GitHub |

**Android gap:** Partial interactive settings; missing full section map, OLED, read-aloud, sync folder, etc.

---

## Shared components (implement once, reuse)

1. **CoverCard** — fixed size, hue wash, stats column, progress footer, ⓘ  
2. **SectionHeader** — title · collapse · see-all chevron  
3. **ToolbarPill** — clustered icon buttons  
4. **FandomChipBar** — All + fandoms  
5. **EmptySection** — icon + secondary text  
6. **ObscuredCard** — blur + “Tap to reveal”  
7. **QuickActionGrid** — 3-column icon tiles  
8. **MetaRowsCard** — labeled content list  
9. **SegmentedTabs** — 3–4 equal tabs under title  

---

## Implementation priority for Android agents

| Priority | Surface | Why |
|---|---|---|
| **P0** | Work Detail tabs + Quick Actions + Library/Tags/Discussion | Screenshots show product is unrecognizable vs Android list |
| **P0** | Account profile + Overview/Reading/Writing/Activity | Same |
| **P1** | Library fandom chips + context menu + queue/collection create tiles | Shell exists |
| **P1** | Home section chrome (collapse, trailing privacy) | Shell exists |
| **P2** | Browse category cards enrichment | Functional |
| **P2** | Settings section map (portable prefs only) | Partial |
| **Skip / later** | iCloud Library Sync Folder, Face ID, TTS | Platform-specific |

---

## Agent instructions (binding)

1. Work only under `android/` on branch `android/sync-from-hig-review`.  
2. MD3 expression — no SwiftUI APIs.  
3. Prefer reusing `WorkCoverCard`, `KudosSectionHeader`, routes, repositories.  
4. Do not claim pixel parity; claim hierarchy parity.  
5. Verify with `android/Scripts/verify.sh` or at least `compileDebugKotlin`.  
6. Read this doc + [IMAGE_INDEX.md](IMAGE_INDEX.md) before coding.
