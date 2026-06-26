# Settings Contract

Status: Phase 0 skeleton. Android storage can use DataStore, but backup field
names and meanings must match the Apple reference.

## Reference Files

- `kudos-ao3-reader/Services/KudosBackup.swift`
- `kudos-ao3-reader/App/ThemeManager.swift`
- `kudos-ao3-reader/Features/Reader/ReaderStyle.swift`
- `kudos-ao3-reader/Features/Privacy/MatureContent.swift`
- `kudos-ao3-reader/Settings/SettingsView.swift`

## Backup Settings Fields

Current backup settings fields:

- `readerFontID`
- `readerMode`
- `readerTwoPage`
- `readerCustomize`
- `readerBoldText`
- `readerFontPt`
- `readerLineHeight`
- `readerLetterSpacing`
- `readerWordSpacing`
- `readerMargin`
- `readerJustify`
- `confirmBeforeDelete`
- `hideMatureContent`
- `matureContentMode`
- `requireBiometricToReveal`
- `appTheme`
- `readerTheme`
- `matchAppReaderTheme`
- `accentColorHex`

## Current Defaults

| Field | Current Apple default |
|---|---|
| `readerFontID` | `system` |
| `readerMode` | `scroll` |
| `readerTwoPage` | `false` |
| `readerCustomize` | `false` |
| `readerBoldText` | `false` |
| `readerFontPt` | `18` |
| `readerLineHeight` | `1.65` |
| `readerLetterSpacing` | `0` |
| `readerWordSpacing` | `0` |
| `readerMargin` | `28` |
| `readerJustify` | `false` |
| `confirmBeforeDelete` | `true` |
| `hideMatureContent` | `true` |
| `matureContentMode` | `obscure` |
| `requireBiometricToReveal` | `false` |
| `appTheme` | existing reader theme or `light` |
| `readerTheme` | `light` |
| `matchAppReaderTheme` | `true` |
| `accentColorHex` | `#990000` |

## Theme Values

Current Apple reader/app theme values:

- `light`
- `sepia`
- `dark`

Android may support a platform `system` theme internally, but must not write
`system` to a v1 backup unless Apple supports it.

## Privacy Values

Current Apple mature-content modes:

- `obscure`
- `hide`

`show` is not a current Apple `MaturePrivacyMode` value. Android should not write
`show` into backups unless the cross-platform contract is updated.

## Custom Fonts

Custom font selections use:

```text
custom:<fileName>
```

If a restored custom font file is missing, the selection falls back to `system`.
Font file names are untrusted and must be sanitized.
