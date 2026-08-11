# Kudos Cross-Platform UI Bridge

This bridge explains how UI agents should preserve one Kudos product across Apple
and Android without copying either platform's chrome.

## Rule

```text
Apple app = behavior, hierarchy, reader-first intent, and parity reference.
Android app = Material Design 3 and Jetpack Compose expression of that intent.
```

Do not treat the Apple app as a pixel-perfect mockup for Android. Treat it as the
source of product meaning: where screens live, which data matters, what must be
local-first, how AO3 boundaries are explained, and which reading workflows are
primary.

## Stable Product Model

Top-level Kudos destinations stay conceptually aligned:

- Home: return to reading and glance at current reading life.
- Library: manage saved/offline works and local organization.
- Browse: explore AO3 structure natively, with WebView fallback only when needed.
- Account: AO3 session, AO3 account lists, app settings, backup, and support.
- Search: global direct-finding action, not a fifth peer tab.
- Reader: quiet reading surface with settings and progress behavior matching the
  platform contracts.

## Shared UI Priorities

- Reader-first workflows beat decorative layout.
- AO3 metadata must remain visible enough for safety and discovery.
- Privacy state must be explicit: local data, AO3 session data, hidden/obscured
  mature works, and backup inclusion/exclusion.
- Library surfaces must work offline and must not fetch AO3 just to display saved
  content.
- Native platform conventions win over literal visual copying.
- Accessibility is part of parity: font scale, TalkBack/VoiceOver semantics,
  contrast, touch targets, and predictable navigation must all survive polish.

## Android Expression

Android UI work must also read:

- `docs/contracts/KUDOS_ANDROID_INTERFACE_GUIDELINES.md`
- `docs/contracts/ANDROID_MATERIAL_HIG_TRANSLATION.md`
- `docs/contracts/UI_PARITY_CHECKLIST.md`

Use Material 3 cards, chips, navigation, sheets, dialogs, app bars, and adaptive
layouts to express the shared Kudos hierarchy. Avoid generic scaffold copy,
debug-placeholder screens, sparse cards that hide AO3 meaning, and WebView-first
solutions where native surfaces already exist.
