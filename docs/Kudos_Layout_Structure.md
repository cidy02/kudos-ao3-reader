# Kudos Layout & Navigation Structure

This document defines the current navigation and layout model for the Kudos app. It is a living document meant to be iterated on as the app grows.

---

## Design Philosophy Reminder

Kudos follows a blended philosophy:

- **Simple by Design, powerful when needed** (KDE influence)
- **Native Apple feel** with strong emphasis on clarity, consistency, and progressive disclosure (Apple HIG influence)

Key relevant layout principles:
- Use clear visual hierarchy and grouping.
- Respect system spacing, margins, and safe areas.
- Prefer progressive disclosure over showing everything at once.
- Keep the default experience simple while allowing depth for power users.

---

## Current Navigation Model (June 2026)

### Core Decision: Mostly Global Search + Contextual Filters

After evaluating options, we are going with the following approach:

- **Search is mostly global** by default.
- Each screen can provide **contextual filters** relevant to its content.
- We are **not** implementing fully contextual search behavior per tab at this time (can be revisited later).

This decision prioritizes **simplicity and predictability** while still allowing power through filters.

---

## Proposed Tab Structure

We are targeting a **4-tab model** (with Settings living inside the Account tab):

| Tab       | Icon          | Primary Purpose                     | Key Contents |
|-----------|---------------|-------------------------------------|--------------|
| **Home**     | House         | Personal dashboard                  | Continue Reading, Recommendations, Quick access |
| **Library**  | Books         | User's saved content                | Saved/Downloaded works, Reading progress, Filters |
| **Browse**   | Search        | Discovery surface                   | Search + Browse by fandom/media categories + Filters |
| **Account**  | Person        | Account & personal features         | Profile/Login state, Bookmarks, History, Subscriptions, Settings |

### Rationale

- **Home** gives users an immediate personal entry point.
- **Library** focuses on content the user owns or has saved.
- **Browse** combines search and category browsing into one clear discovery destination.
- **Account** centralizes all account-related functionality (including Settings). This reduces tab bar clutter and scales better as auth features grow.

---

## Search Behavior

### Current Model

- Tapping the Search icon triggers **global search** across the app by default.
- Each screen can surface **contextual filters** relevant to that section (e.g., "Downloaded only" in Library, media type filters in Browse).
- Search results can be further refined using filters.

### Contextual Behavior (Current Plan)

| Tab       | Search Behavior                              | Contextual Filters Available |
|-----------|----------------------------------------------|------------------------------|
| **Home**     | Global search + suggestions                  | Light / none initially |
| **Library**  | Global search (results can be filtered)      | Downloaded, In Progress, Finished, etc. |
| **Browse**   | Global search (primary discovery tool)       | Media type, Fandom categories, etc. |
| **Account**  | Global search                                | Bookmarks, History, Subscriptions (future) |

---

## Screen Responsibilities (Draft)

### Home

**Purpose**: The Home tab is the user’s personal starting point. It focuses on their current and recent reading activity.

**Sections** (in this exact order):

1. **Reading Now**
   - Works the user is currently reading.
   - Shows progress.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

2. **Recently Updated**
   - Works/series that have received new updates (especially relevant for subscribed content).
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

3. **Subscriptions**
   - Works and series the user is subscribed to.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.
   - (Will become more useful once authentication + subscriptions are implemented.)

4. **Favorites**
   - Works the user has marked as favorites.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

5. **Recently Opened**
   - Works the user has recently opened.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

**Layout Pattern**:
- All sections use **horizontal scrolling cards**.
- Each section header includes a **">"** chevron next to the title. Tapping it opens the full vertical card list for that section.
- Sections are **collapsible** so users can hide content they don’t frequently use.
- This pattern keeps the Home tab scannable while allowing deeper exploration when desired.

**Empty States** (for each section):

- **Reading Now**: “You’re not reading anything right now. Start exploring in Browse or open something from your Library.”
- **Recently Updated**: “No recent updates from your subscriptions yet.”
- **Subscriptions**: “You’re not subscribed to anything yet. Subscribe to works or series to see updates here.”
- **Favorites**: “No favorites yet. Mark works as favorites to see them here.”
- **Recently Opened**: “Nothing opened recently. Start reading to see your history here.”

**Current Status**: Structure agreed. Implementation details (how many cards to show horizontally, loading behavior, etc.) still need to be defined.

### Library

**Purpose**: The Library tab organizes the user’s saved and downloaded content with clear sections and strong but non-intrusive filtering.

**Sections** (in this exact order, all visible by default and **collapsible**):

1. **Reading Now**
   - Works the user is currently reading.
   - Shows progress.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

2. **Saved for Later**
   - Works marked as "Saved for Later" (Marked for Later).
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

3. **Finished**
   - Works the user has marked as completed.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

4. **Collections**
   - User-created or synced collections.
   - Starts simple (horizontal list of collection cards).
   - Expandable following the same pattern as other sections.
   - ">" chevron opens the full collections view.

5. **Downloaded**
   - Works that exist locally on the device (offline content).
   - Placed at the bottom as it represents local-only content.
   - Horizontal scrolling cards.
   - ">" chevron opens the full vertical list.

**Layout Pattern**:
- All sections use **horizontal scrolling cards** by default.
- Each section header includes a **">"** chevron next to the title. Tapping it opens the full vertical card list for that section.
- Sections are **collapsible** so users can hide content they don’t frequently use.

**Empty States** (for each section):

- **Reading Now**: “You’re not currently reading anything. Works you open will appear here.”
- **Saved for Later**: “Nothing saved for later yet. Use ‘Save for Later’ on works you want to come back to.”
- **Finished**: “No finished works yet. Mark works as finished to track your progress.”
- **Collections**: “No collections yet. Create collections to organize your reading.”
- **Downloaded**: “No downloaded works yet. Download works to read offline.”

**Synced vs Local Content**:
- A subtle **badge** or icon on each work card indicates whether the content is **Synced** (cloud) or **Local/Downloaded** (device).
- The **Downloaded** section is explicitly local-only.
- Other sections can contain a mix of synced and local items, with the badge providing clarity without forcing visual separation.

**Filtering**:
- Light, always-visible filter chips for common options (e.g., status).
- Advanced filters available behind a **"Filters"** button (following "Simple by Design, powerful when needed").
- Filtering can temporarily flatten the sectioned view into a single list when active.

### Browse (Discovery)
- Main place for finding new works.
- Combines free-text search with category browsing (fandoms, media types).
- Should feel like the primary exploration surface.

### Account
- Central place for everything related to the logged-in user.
- Will grow to include: Profile, Bookmarks (synced), History, Marked for Later, Subscriptions, Statistics, and Settings.
- Settings should live here rather than as a separate top-level tab.

---

## Open Questions & Decisions to Revisit

| Topic                        | Current Status          | Notes / To Do |
|-----------------------------|-------------------------|---------------|
| Home tab content            | Partially defined       | Need to flesh out recommendations and quick actions |
| Search vs Browse distinction | Needs clarification    | How different should the Browse tab feel from just using Search? |
| Old AO3 WebView fallback    | Demoted to fallback     | Decide where users can access it (Settings? Inside Browse?) |
| Fully contextual search     | Deferred                | Revisit later if global + filters proves insufficient |
| iPad / Mac layout           | Not yet addressed       | Will likely use sidebar + detail view pattern |
| Reader navigation           | Separate from main tabs | Should the reader feel fully immersive? |

---

## Next Steps

1. Finalize the **Home** tab content and layout.
2. Define clear responsibilities and visual treatment for the **Browse** tab.
3. Decide where the full AO3 website fallback lives.
4. Begin applying consistent card layouts, spacing, and materials across Home, Library, and Browse.
5. Revisit this document as authentication features are implemented and the Account tab expands.

---

*This document should be updated whenever major navigation or layout decisions are made.*