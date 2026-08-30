Dynamic Type and VoiceOver order are sound: lines wrap/grow, and the enclosing Button reads title → qualifier → aliases → count. [Row](/Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift:379)

One accessibility fix: `.caption` + `.tertiary` is too low-contrast for small CJK aliases on the Light, Dark, Sepia, and OLED card surfaces. Keep the third typographic tier, but make aliases `.secondary`. [Alias line](/Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift:400)

No identity, parser, search, zoom-key, or works-query behavior changed; raw `fandom.name` still drives selection and zoom. Three tiers are right—do not merge qualifier and aliases.

LAYOUT: FIX-THEN-SHIP — change aliases to `.font(.caption).foregroundStyle(.secondary)`.
