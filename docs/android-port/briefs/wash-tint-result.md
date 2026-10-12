# The tab bar and chrome buttons take the colour of the screen on top (both apps)

Owner, 2026-10-11, in three messages:
1. "on iOS, make the tab bar accent color and any chrome button accent color follow the
   current wash for the current screen"
2. "and then port that change to Android"
3. "on Library, the accent color for the chips at the top should also follow the wash"

Done 2026-10-12 by Claude. Pictures: `shots/wash-tint/`.

## iOS (T-399; polish `c3969aa6`, integrate `ee3596ab`, both pushed)

A screen already tinted its own content with its wash (`screenTint`). Three things sat
outside that: the tab bar and toolbar buttons took the app accent from `ContentView`, and
the Library's chips asked for the app's palette by name.

- `ScreenWashRegistry` (`UIComponents/SubjectSurface.swift`): a washed screen reports its
  tint while it is showing (`SubjectWash`, and Home's and Library's `HeroWash`). The
  screen that appeared last and is still showing is the current one: a push takes the
  colour, a pop or a tab switch gives it back, a screen with no wash leaves the app accent.
- `ContentView` tints the app and its window with the current wash, else the app accent.
- `LibraryView.washPalette`: the chips at the Library's top take the palette of the work
  the page's wash comes from.

Suite 2,341 with the one known `KokoroCastDiscoveryTests` failure; `ScreenWashRegistryTests`
(3); lint 125 warnings as before; macOS builds.

## Android (`MainScaffold.kt`; gate 2,618)

The shell already knew the page's wash (`LocalShellWashes`, which it repaints its top bar
with). Its own chrome and tab bar are now drawn under that palette: the selected tab's
pill, the toolbar buttons of Home and Library, the back and trailing buttons of a pushed
page. The page's content is as it was. The Library's chips already followed its wash.

## Seen

| | iOS simulator | Android emulator |
|---|---|---|
| Home, Library (Sodium Lights: purple) | Sepia, Dark | Sepia, Dark |
| A collection (green), and back | Sepia, Dark; through a push and back | Sepia; through a push and back |
| A work's page | Sepia | no |
| Browse, Account (no hue: the app's colour) | Sepia | Sepia |

**Not seen:** Light and OLED on either; iPad's sidebar; a sheet with its own wash over a
screen; the largest text sizes (nothing here is text). **The iPhone was not updated**: the
owner's install of 21:10 on 10-11 is `37e5fba5`, from before this.

## One thing to know

On iOS the whole app's tint follows the screen on top, so an alert or a sheet raised from a
purple screen has purple buttons too. That is how a screen's own content already behaved.
