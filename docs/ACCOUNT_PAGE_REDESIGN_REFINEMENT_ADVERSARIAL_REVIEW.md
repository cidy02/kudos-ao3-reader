# Adversarial review: `account-page-redesign-refinement`

**Date:** 2026-07-12 (updated after fix pass)  
**Branch:** `account-page-redesign-refinement`  
**Base:** `origin/account-page-redesign`

**Method:** Tree + diffs + call-site greps + docs/policy cross-check + existing tests.

---

## Status after fix pass

| ID | Finding | Status |
|---|---|---|
| **B1** | `AppRouterTests` vs `open()` | **Fixed** — tests expect `isPresentingWebBrowser`, no Browse steal |
| **B2** | Session always dual-written to Application Support | **Fixed** — file only on `errSecMissingEntitlement`; Keychain success deletes file |
| **B3** | Uncommitted web-return / rename | **Fixed** — committed in later tips |
| **R1** | Overview always activates Inbox | **Fixed** — Overview only activates profile; Inbox shortcut has no live badge fetch |
| **R2** | Collections pull-to-refresh no-op | **Fixed** — explicit `break` + comment |
| **R3** | Preferences save success too loose | **Fixed** — require flash / “successfully updated” / 3xx; no bare 200 success |
| **R4** | Hidden `preference[...]` fields dropped | **Fixed** — parse + include on save (checkbox companions skipped) |
| **R5** | Ambiguous HTML wipes session | **Fixed** — `looksLikeAO3Page` requires `body.logged-in` / `body.logged-out` only |
| **R6** | Stale docs/comments | **Fixed** — auth docs + inbox model header aligned |

Remaining residual risk (not blockers):

- Live AO3 preference save still **unverified** against a real session (same class as other write actions).
- Preference success if AO3 changes flash copy without “successfully updated” may force a retry message — safer than false success.

---

## Original executive summary (historical)

Account IA and native Preferences are directionally solid. The merge-blocking items above were dual-write of session cookies, router test drift, and incomplete web-dismiss UX.

---

## Caveats

- Full `Scripts/verify.sh` may still need a local run after this fix pass.
- Nested help-sheet + web-sheet ordering not re-exercised on device in this pass.
