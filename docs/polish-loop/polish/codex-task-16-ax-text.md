
TASK 16: Dynamic Type for fixed-size body text on the challenge and AO3-collection screens. At the largest accessibility
size (AX5) these screens' headers grow but the text inside their cards and rows stays at a fixed point size, so the page
reads as two different apps. Make the body text scale WITHOUT changing the default-size look (pixel-identical at the
default "Large" size): replace each `.font(.system(size: N…))` on titles, row labels, meta lines and card copy with a
`@ScaledMetric` of the same base size (relativeTo: .body / .subheadline / .footnote / .caption as fits), declared on the
enclosing struct. Do NOT scale: SF Symbol glyph sizes already scaled elsewhere, the small uppercase status badges
("UNMATCHED", "WORK"), or fixed decorative sizes. Where a scaled line would now break mid-word or overflow at AX5, let it
wrap (`.fixedSize(horizontal: false, vertical: true)`) rather than capping it. Keep pills/chips single-line
(`.lineLimit(1).fixedSize()`).

Files (the fixed sizes a grep found; cover every body-text size in each file, not only these lines):
- Features/Challenges/CollectionModerationView.swift (review cards ~298, membership rows ~459)
- Features/Challenges/CollectionMaintainersView.swift (~222 participant rows)
- Features/Challenges/ChallengeAssignmentsView.swift (~261 assignment rows, ~597 pinch-hit cards)
- Features/Challenges/ChallengeSignUpsView.swift (~568 rows)
- Features/Challenges/PromptMemeView.swift (~268 prompt title, ~273 body)
- Features/Challenges/TagSetView.swift (~463 nomination rows)
- Features/Challenges/ChallengeSettingsView.swift (the Type rows' title/subtitle)
- Features/Account/AO3CollectionItemsView.swift (~562 card title, ~731 settingsLabel)
- Features/Account/AO3CollectionsList.swift (~713 card title)
- Features/Account/AO3CollectionDetailView.swift (~627 maintainer row label)

Do not touch SubjectForm.swift, SubjectSurface.swift, NativeBrowseView.swift, SearchResultsHero.swift (changed today).
Claude builds and screenshots each screen at default size and AX5.
