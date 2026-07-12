# Adversarial review: `account-page-redesign-refinement`

**Date:** 2026-07-12  
**Branch:** `account-page-redesign-refinement`  
**Base:** `origin/account-page-redesign`  
**Committed tip reviewed:** `3d7cfea` — *Refine Account hub: job tabs, native preferences, durable session restore.*

**Also reviewed (working tree, not necessarily committed at review time):**

- `kudos-ao3-reader/App/AppRouter.swift`
- `kudos-ao3-reader/App/ContentView.swift`
- `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift`
- `kudos-ao3-reader/Features/Account/AccountView.swift` (incl. “Marked for Later” rename)

**Method:** Tree + diffs + call-site greps + docs/policy cross-check + existing tests. No full `Scripts/verify.sh` run in this pass (see caveats).

**Principles:** Review the tree, not summaries. Try to refute. Findings need file + concrete failure scenario + severity.

---

## Executive summary

Account IA (Overview / Reading / Writing / Activity) and native Preferences are directionally solid. Several issues are **merge-blocking** or **production-security sensitive**, especially session dual-write and router changes that **break `AppRouterTests`**. Preferences write path is plausible but **not live-verified** (same class as other AO3 writes).

| Severity | Count |
|---|---|
| Blocker | 3 |
| Real bug | 6 |
| Minor | 7 |

---

## Files in scope (committed)

| Path |
|---|
| `KudosTests/AO3AuthTests.swift` |
| `KudosTests/AO3PreferencesParseTests.swift` |
| `KudosTests/Fixtures/ao3_help_preferences_privacy.html` |
| `KudosTests/Fixtures/ao3_preferences.html` |
| `docs/AO3Authentication.md` |
| `docs/ARCHITECTURE_MAP.md` |
| `kudos-ao3-reader/Features/Account/*` (AccountView, Components, Preferences, More on AO3, inbox comments) |
| `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift` |
| `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift` |
| `kudos-ao3-reader/Models/AO3PreferencesModels.swift` |
| `kudos-ao3-reader/Services/AO3AuthService.swift` |
| `kudos-ao3-reader/Services/AO3Client+Preferences.swift` |
| `kudos-ao3-reader/Services/AO3PreferencesActions.swift` |
| `kudos-ao3-reader/Services/AO3SessionVault.swift` |

---

## Blockers

### B1. Uncommitted `open()` change falsifies `AppRouterTests`

**Files:** `AppRouter.swift` (uncommitted), `KudosTests/AppRouterTests.swift` (~65–72)

```swift
// Test still expects:
#expect(router.selection == .browse)
// open() now only sets isPresentingWebBrowser; selection stays unchanged
```

**Scenario:** CI / `Scripts/test.sh` after including the web-return fix → `nonAuthorUserPageFallsBackToWeb` fails.

**Fix:** Update test to expect `isPresentingWebBrowser == true` and `selection` unchanged; add coverage for `openWebsite()`.

---

### B2. Session cookies always written to Application Support (not just Simulator fallback)

**File:** `AO3SessionVault.swift` — `CascadingAO3SessionVault.save`

```swift
try keychain.save(session)  // may succeed on device
try file.save(session)      // ALWAYS dual-writes session JSON
```

**Scenario (signed production device):** Login succeeds → Keychain *and* `Application Support/KudosAuth/ao3-session.json` hold full `_otwarchive_session` (and related cookies). Expands the session steal surface beyond the documented Keychain model (backups, device sharing, forensic access to container).

Docs still frame the file as a sim/unsigned backstop, but code always mirrors.

**Contrast:** `docs/AO3Authentication.md` still contains language that cookie values are not a custom plaintext fallback, while also describing the cascading vault — **internal contradiction**.

**Fix:** File write **only** on `errSecMissingEntitlement` (or `#if DEBUG` / simulator), never dual-write on successful Keychain save. Align docs.

---

### B3. Working tree ≠ commit; merge of `3d7cfea` alone ships incomplete web UX

**Scenario:** Push/merge only the commit → “Done returns to Account” fix is missing; Series/Drafts/More still jump to Browse and strand the user. Rename “Marked for Later” may also be only in the working tree depending on commit state.

**Fix:** Commit router / ContentView / Browse / Account rename before any merge claim of “done.”

---

## Real bugs

### R1. Overview always activates Inbox → extra authenticated AO3 fetch

**File:** `AccountView.swift` — `activateVisibleContent`

```swift
case .overview:
    profileModel?.activate(auth: auth)
    inboxModel.activate(auth: auth)  // network for unread shortcut
```

**Scenario:** User opens Account (default Overview) every time → inbox page fetch even if they never open Inbox. Tensions with “no background bulk” spirit and burns rate-limit budget for a badge that is often unavailable until first successful parse.

**Fix:** Lazy-load unread once per session, drop badge until Activity › Inbox, or use cached counts only.

---

### R2. Reading › Collections pull-to-refresh is a no-op

**File:** `AccountView.swift` — `refreshCurrentTab`

```swift
case .collections:
    listReloadToken += 1  // nothing observes this for collections
```

**Scenario:** User on Collections, pull to refresh → token bumps, UI unchanged (only a “Browse Collections” nav card).

**Fix:** No-op intentionally with comment, or embed reloadable collection rows.

---

### R3. Preferences save success criteria too loose

**File:** `AO3PreferencesActions.swift` — `savePreferences`

```swift
if (200 ... 399).contains(status), writeErrorMessage == nil {
    return notice ?? "Preferences updated."
}
```

**Scenario:** AO3 returns 200 login page or generic OK HTML without errorlist (session half-dead, soft fail) → UI shows success, preferences not saved. Same class as other writes; higher impact because the user trusts “Preferences updated.”

**Fix:** Require flash notice **or** re-GET and diff key fields; treat login redirect as auth failure; prefer validating response URL/path.

---

### R4. Preferences form may omit non-checkbox defaults / hidden fields

**Files:** `AO3Client+Preferences.swift` parser + `AO3PreferencesSnapshot.preferenceParameters()`

Only checkboxes, selects, and text inputs named `preference[...]` are submitted. Rails forms often include extra hiddens.

**Scenario:** Future AO3 markup adds required hidden `preference[something]` → native save strips it → unexpected server defaults.

**Fix:** Parse all `input[type=hidden][name^=preference]` and include unless overridden by UI.

---

### R5. `looksLikeAO3Page` can still mis-classify ambiguous HTML as AO3

**File:** `AO3AuthService.swift` — `LiveAO3SessionValidator.looksLikeAO3Page`

**Scenario:** CDN error or interstitial that still has `#main` → treated as AO3; `isLoggedIn` false → **`.expired` → `clearStoredSession()`** wipes file + Keychain + cookies. Narrower than before (pure CF walls better), but still a wipe path on ambiguous HTML.

**Fix:** Require `body.logged-in` / `body.logged-out` **or** a stronger AO3 fingerprint; on ambiguous HTML throw (keep session), never expire.

---

### R6. Stale docs / comments contradict implementation

| Location | Issue |
|---|---|
| `AO3InboxModel.swift` header | Still says “Overview Recent Comments preview” — section removed |
| `AO3Authentication.md` | “No custom plaintext cookie file” vs cascading file vault |
| Uncommitted router | Mental model / tests still partly Browse-centric |

**Scenario:** Next agent trusts inbox comment and re-adds Overview inbox patterns; security review trusts “no cookie file.”

---

## Minor

### M1. Nested sheets (Preferences help + root web)

Help sheet inside Preferences; “Open on AO3” from failed help calls `router.open` → root web sheet over Preferences. Usually OK; watch iOS nested presentation glitches (known login-sheet scar tissue).

### M2. `AccountScopeMenu` label always “Show”

Fine for hierarchy; VoiceOver is OK. Long raw value “Marked for Later” may feel wide in the menu label on small phones—acceptable.

### M3. Profile card session popover vs macOS

`presentationCompactAdaptation(.popover)` is iOS-oriented; macOS may differ. Low risk.

### M4. Writing › Drafts / More paths are best-effort

Paths match otwarchive routes; no automated check that they still exist after AO3 deploys.

### M5. `hasEdits` sticky after undo

Toggle on then off still enables Save → harmless extra POST.

### M6. Series empty copy is author-profile generic

“no visible series for this author scope” when viewing self—slightly odd copy.

### M7. Limited file-vault integration tests

Unit tests cover empty-Keychain path with temp file; no integration that logout deletes real `KudosAuth/ao3-session.json` under Application Support.

---

## Cross-cutting critic

| Concern | Result |
|---|---|
| Scope creep | Session vault + full Preferences + Account IA + web presentation model — large but coherent for “Account hub” |
| Stage conflicts | Uncommitted router work may be **absent** from `3d7cfea` → split brain between commit and tree |
| Shared API breakage | `AppRouter.open` semantics changed (no tab switch) — UX win; **tests must be updated** |
| Policy (`AO3_NETWORKING_POLICY`) | Overview inbox prefetch is the main tension; Preferences GET+POST is user-initiated |
| Persistence | Dual-write session file is the main **security/product** risk if shipped as-is to production |
| Platform | Preferences UI uses `#if os(iOS)` where needed; file vault has macOS branch |
| pbxproj | No churn (synced groups) — good |

---

## Claim checks

| Claim | Verdict |
|---|---|
| Session survives sim reinstall better | **PLAUSIBLE** — file vault + restore fallthrough; dual-write helps sim; not proven after logout + clean container |
| Native Preferences equals AO3 form | **PLAUSIBLE** for checkboxes/selects/text; **unproven** live; save success heuristic weak (R3) |
| Overview / Reading / Writing / Activity is wired | **CONFIRMED** in `AccountView` |
| Secondary scopes are dropdowns not peer tabs | **CONFIRMED** (`AccountScopeMenu`) |
| Dismiss web returns to prior tab | **PLAUSIBLE** only with root sheet change present; **REFUTED** for commit-only tree without that change |
| “Later” renamed to “Marked for Later” | Confirm against current tree / commit state |

---

## Ordered fix list (before merge)

1. **Commit** router / ContentView / Browse + rename; **update `AppRouterTests`**.
2. **Stop always dual-writing** session JSON; file only on Keychain entitlement failure (or debug-only).
3. **Reconcile `AO3Authentication.md`** (remove false “no cookie file” statement; document file vault threat model).
4. **Tighten preference save success** detection.
5. **Revisit Overview inbox activate** (lazy or remove).
6. Fix stale `AO3InboxModel` comment; collections refresh no-op.
7. Run `Scripts/verify.sh` + full iOS tests after 1–3.

---

## Caveats

- Did not run live AO3 preference save or full `Scripts/verify.sh` / lint in this review.
- Sheet environment inheritance for `AO3WebBrowserView` assumed OK (`.environment` wraps the view that owns `.sheet`) — not runtime-validated on macOS multi-window.
- Nested help-sheet + web-sheet ordering not exercised on device.

---

## Bottom line

Do not merge on product/security grounds until **(B2)** dual-write is narrowed and **(B1/B3)** router work is committed with green tests. Treat Preferences write path as **same risk class as other AO3 writes** until a live session proves save. Account IA structure itself is the strongest part of the branch.
