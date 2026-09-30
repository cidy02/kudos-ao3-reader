# Polish loop (owner request 2026-09-28)

Owner: "audit all the redesigned screens for similar issues ... one cohesive design language,
every page has appropriate actions (delete, reorder, add, etc) in appropriate places ...
very thorough and anal about every tiny detail. Ask in every screen: Does this fit the app,
does this empower the user, is it one cohesive design philosophy consistent with the rest of
the app, and is this something Apple would be proud to ship?"

Spec: docs/design/Final_Redesign_Spec.dc.html (artboards by id="1x"). Integrate branch:
integrate/cloud-redesign. Never contact AO3, never sign in, never push.

## Checklist (every screen)
A. Fidelity to its artboard: layout, order, spacing (18 between blocks, 10 rule->content),
   type sizes/weights, colours, radii, copy (exact words, case), icons.
B. Actions: every list that holds user things has the actions it should, in the app's places:
   - Add: "+" glass button in the toolbar (primary), never buried.
   - "..." menu (WorkListMoreMenu), in this order when present: Show/Hide mature (whenever
     Hide Mature is on, on every works screen) · Select · Reorder (a mode, Done ends it; off
     under filters with a reason) · display mode picker · Expand/Collapse all · page items
     (Details, Rename, Share, Open on AO3) · destructive last.
   - Delete: trailing swipe on rows + Select mode bulk bar; destructive confirmation shared
     (destructiveConfirmation); Recently Deleted where the data model soft-deletes.
   - No always-on drag handles; no "Drag to reorder" hints.
C. Consistency with the rest of the app: same components for the same job (SubjectHeaderBlock,
   SectionRuleHeader, SubjectChip, SubjectPillRail, cardRow tint, WorkLedgerRow, FilterButton,
   ActionToolbar, SearchPaginationBar, ContentUnavailableView copy style).
D. Data display: counts > 999 compact (1.2K) on chips/cards/stat strips (exact where exactness
   matters: pagination, AO3 totals in prose); fandom names without disambiguation where the
   artboard shows bare names (FandomFamily / FandomDisplayName); no raw "0%" claims.
E. States: loading skeleton shaped like content, empty state with an action, error with retry,
   signed-out prompt; nothing blank.
F. Accessibility: 44pt targets, labels/values, VoiceOver order, Dynamic Type not clipping,
   Reduce Motion.
G. Platform polish: iPhone + iPad + macOS builds, safe areas, tab bar/floating chrome overlap,
   keyboard avoidance, pull to refresh where it fetches.

## Batches (status)
1. Home: 1b 1ad 1ae 1af 1ag (+1a Home entry points)            — Claude
2. Library: 1c 1d 1ah 1ai 1aj 1ak 1bc 1bd 1bi 1bj 1ay 1az       — Grok
3. Queues: 1h 1h.1-4 1i 1j 1bg 1bh                              — Codex
4. Collections: 1bk 1r 1s 1bl 1bm 1ci 1cd 1ce 1cg 1ch 1bx       —
5. Browse/Search: 1g 1al 1am 1an 1k 1ao-1ax                     —
6. Work detail + comments: 1a 1f 1ba 1be 1bf                    —
7. Account hub: 1m 1n 1o 1q 1t 1p 1l 1y 1z 1ab 1ac 1aa 1bb      —
8. Writing: 1u 1v 1w 1x 1bn-1bw 1bt                             —
9. Challenges: 1by 1bz 1ca 1cb 1cc 1cf                          —
Then pass 2: cross-screen consistency sweep of B/C/D across all.

## Output format for auditors
Per finding: id (batch-N-k), severity (P1 wrong/broken, P2 visible inconsistency, P3 polish),
artboard + file:line, what the artboard/app convention says, what the code does, smallest fix.
Findings go to .claude-overnight/polish/batch-N-<auditor>.md.
