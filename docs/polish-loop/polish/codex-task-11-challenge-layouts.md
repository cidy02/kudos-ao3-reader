
TASK 11: spec-closer layout fixes on the challenge / collection-maintainer screens. Layout and chrome only:
no new parsing, no new AO3 requests, no removed capability. Each item names its artboard (dv-opt id); take
sizes from its inline styles, colours from theme tokens. List changed files per item.

1. 1cb, ChallengeAssignmentsView (Features/Challenges/ChallengeAssignmentsView.swift ~247–275): matched
   assignments are separate cards. Draw them as ONE `.subjectPanel()` with `SubjectRowSeparator()` between
   rows (rows padding 12×14, title 600 14.5pt). No chevron and no navigation (there is no destination).
2. 1cd, CollectionModerationView (Features/Challenges/CollectionModerationView.swift):
   a. ~288–316 review card: corner radius 16, title 600 16pt (keep the fields it already has; do not add
      word count or tags — there is no data for them).
   b. ~308–389 action row: 1cd supersedes 1bx. Content-width pills in a wrapping row, gap 7: Approve,
      Reject, and "Message creator" as a TEXT pill (today an icon-only circle; keep its action). Pills
      height 34, padding 0×14, radius 99, 600 12.5pt; prominent one uses `.prominentLabel()`; 44pt tap via
      `layoutFreeHitTarget`. Keep existing confirmations exactly as they are.
   c. ~408–439 membership requests: one grouped panel with separators (rows 11×14, name 600 14.5pt) instead
      of separate cards. Keep Accept/Decline. No request date or work count (no data).
3. 1ch, TagSetView (Features/Challenges/TagSetView.swift ~142–174, 300–320): the Tags section shows only the
   four count rows. Move the four inline tag editor panels + "Save tags" behind a disclosure: the four count
   rows get `showsDisclosure: true` and push (subjectRowNavigation) ONE editor screen holding the existing
   four fields and the Save button, unchanged in behaviour. Reuse the existing editor views/state; if the
   state must be shared, pass bindings — do not duplicate the save logic.
4. 1s, AO3CollectionItemsView (Features/Account/AO3CollectionItemsView.swift):
   a. ~326–344: remove the SectionRuleHeader that sits between the filter rail and the cards.
   b. ~538–557 item card: padding 16 vertical × 18 horizontal, inner gap 12, radius 16, title 600 19pt.
   c. ~585–681: the card nests a second rounded SubjectForm panel. Replace it with unboxed rows inside the
      card (gap 12, padding 9×0, label 400 13.5pt); keep every control and its behaviour (the three-way
      approval choice may stay a segmented control, sized to the row).

Do not touch SubjectForm.swift (Claude changed it in T-326). Screens are reachable in the simulator with
`-KudosDebugRoute acct:ao3collection:winter_exchange -KudosDebugManageRow "<row label>"` (Claude will
screenshot; you cannot run the simulator).
