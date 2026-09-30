TASK (READ-ONLY AUDIT — do not edit any file): audit these screens' code against the spec and report mismatches.
Screens (Swift file → artboard ids in docs/design/Final_Redesign_Spec.dc.html, `<div class="dv-opt" id="…">`;
labels in .claude-overnight/polish/artboards.tsv):
- ChallengeSignUpsView / ChallengeSignUpView / ChallengeAssignmentsView → 1bz, 1ca, 1cb
- PromptMemeView, PromptTagsEditorView → 1cc
- CollectionModerationView, CollectionMaintainersView → 1cd, 1ce, "Collection maintainers", "Moderated items"
- ChallengeSettingsView, ChallengeSettingsEditView → 1cf, 1cg, 1by
- TagSetView → 1ch
- AO3CollectionItemsView → 1s ; AO3CollectionFormView → "AO3 collection — new/edit/delete confirmation"
- CommentComposerSheet, CommentMarkup → 1ba, 1be, 1bf
Report ONE markdown table: | # | Sev (P1 broken / P2 visible inconsistency / P3 polish) | Screen | file:line | Spec
ref (artboard id + exact CSS value) | Current | Expected | Smallest fix |. Cite real file:line and real spec values;
say "unsure" rather than guess. Skip anything the app deliberately departs from with a code comment naming an owner
decision. Also check against the app's own shared patterns: SubjectHeaderBlock headers, SectionRuleHeader groups,
SubjectFormRow panels (~42pt, no List minimum), "Try Again" failure cards, .prominentLabel() on filled buttons,
FandomDisplayName.bareTitle kickers, Int.compactCount counts, 44pt hit targets without taller rows.
