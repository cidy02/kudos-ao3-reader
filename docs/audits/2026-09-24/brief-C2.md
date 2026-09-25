# Brief — C2: collections moderation + account-settings collections (partial, blocked)

**Status: not a full brief.** The handoff builds C2 from
`collections-moderation.json`, `account-settings-collections.json` and
`critic-wave2.json` ("the critic's WRONG/UNSURE corrections win"). None of
those files was on origin when this was written (`origin/review/codex-item12`
= `c4ce1e2`). Writing C2 without them would mean either guessing what wave 2
found or re-auditing screens two Mac rows are rebuilding:

- **T-240** (Collections screens bound to their session, `b11d179a`, unpushed)
  rewrites `AO3CollectionsList` and `AO3CollectionItemsView`.
- **T-253** (in flight) owns `Features/Challenges/*`. That is where every
  moderation file lives: `CollectionModerationView`, `RejectReasonSheet`,
  `ModeratedItemsView`, `TagSetView`, `CollectionMaintainersView`.

So this file records only what could be verified here from source and
otwarchive, and what the next writer needs.

## To finish C2 (Mac side, or a later cloud session with the files pushed)

1. Push `review/codex-item12` with `docs/audits/2026-09-24/` (at least the two
   C2 JSONs, `critic-wave2.json`, `AUDIT_METHOD.md` and
   `otwarchive-facts.json`).
2. Build the brief from those, applying `critic-wave2.json`'s corrections.
   Then check each item below against it and drop duplicates.
3. Cap it at about 12 items, as the other briefs are.

## Verified here (for the C2 writer to merge)

### C2-1 — The reject sheet promises a reason AO3 never receives (1ce) — bug, already on the handoff's owner list

- **Files:** `Features/Challenges/RejectReasonSheet.swift:5`, `:46`, `:104`,
  `:148`; `Services/AO3CollectionActions.swift:115-135`.
- **On screen:** "AO3 emails your reason to <creator>. It cannot be edited
  afterwards", a "Required" reason field, and a "Reject and send" button.
- **In code:** `rejectCollectionItem` validates the reason locally and posts
  only the approval status. Its own doc says AO3's
  `collection_items_controller` permits only
  approval/unrevealed/anonymous/remove, and the otwarchive controller at
  `update_multiple` / `update_multiple_with_params` (`:164-230`) agrees. The
  moderator writes a reason that goes nowhere, told that it will be emailed.
- **Why it waits:** the copy (and whether to keep a reason field at all) is on
  the handoff's owner list ("1ce reject copy: AO3 sends no reason (Q6)"), and
  the file is T-253's until that lands. The smallest honest fix is to drop
  "emails your reason", make the field optional or remove it, and rename the
  button "Reject".

### C2-2 — `ModeratedItemsView` has no route (owner, per handoff)

- `Features/Challenges/ModeratedItemsView.swift` is never instantiated. The
  only other mentions are doc comments in `CollectionModerationView.swift`
  (:204, :206, :289) that point at its card and button as the pattern they
  copy. Wire it or delete it. This is on the handoff's owner list.

### C2-3 — Collection delete and icon upload (1bl) (owner, per handoff)

- Delete is an AO3 DELETE write (handoff Q10). An icon upload needs multipart
  support the client does not have. The owner decides both.

### C2-4 — Stored toggles with no effect (1bk) (owner, per handoff)

- Local collection "Keep downloads", "Show on Home" and colour: see
  `docs/REDESIGN_PLAN.md` §3b "1bk local collections". "Keep downloads" changes
  the cache sweep, and that is persistence behaviour.

## Not re-audited here, on purpose

1r, 1s, 1bk, 1bl, 1bm, 1cd, 1ce, 1cg, 1ch, 1ci. Wave 2 covered them, and T-240
and T-253 are changing their files.
