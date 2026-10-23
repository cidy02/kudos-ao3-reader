# Duo2 — research: Apple's guidance for iPhone Duo

**Agent:** Gemini 4 Argon, agy account 2. **Web research only.**

## Context

Kudos is a native SwiftUI reader for Archive of Our Own (iPhone, iPad and Mac). Once the Android port
reaches parity, the team will optimise the app for **iPhone Duo**. Xcode 27.1 on this Mac lists an
"iPhone Duo" simulator device type (`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`) with the iOS 27.1
runtime. Find what Apple, and reliable developer sources, say about designing and building for it.

## Rules

- Web research only. Create or change no file except `Duo2-result.md` in this folder. Run no terminal
  commands. Sign in to nothing.
- Cite only pages you actually opened. For every finding give: the exact URL, the page title, its
  publication or last-updated date, and the exact sentence(s) you are relying on, quoted.
- **Do not fill gaps from memory.** If no page you opened supports something, write "no source found".
- Prefer developer.apple.com (Human Interface Guidelines, documentation, WWDC session pages and
  transcripts, developer news), then apple.com (newsroom, tech specs, support). Label anything else
  "secondary".

## Questions

1. **The device.** What is iPhone Duo: its form factor; each display's size in points and pixels and
   its scale; its states or postures (for example folded and unfolded, or one screen and two); any
   hinge or fold region; safe areas; orientations; the iOS version it shipped with; its release date.
2. **Human Interface Guidelines.** Every HIG page or section that mentions iPhone Duo or its form
   factor, and what it says about layout, size classes, navigation (split views, sidebars, tab bars),
   windows and multitasking, the hinge or fold, continuity when the device changes state, typography
   and reading, app icons and launch screens.
3. **APIs.** The UIKit and SwiftUI APIs, size-class or trait changes, scene and window behaviour, and
   Info.plist keys for the device: how an app learns the device's state or the fold's position, and how
   it opts in or out. WWDC 2026 sessions about it, with titles and numbers.
4. **Compatibility and testing.** What an app that does nothing gets on iPhone Duo (letterboxing,
   scaling, the iPhone or the iPad layout); App Store requirements or deadlines; how to test in the
   Simulator (the device states it can switch between and the menu commands for that).
5. **Reading apps.** Any guidance or examples for reading, books, long text, or two-page layouts on the
   device.

## Output

`Duo2-result.md` in this folder:
- one section per question, each finding a bullet with the claim, the quote, the URL and the date;
- then **Not found**: each question, or part of one, with no source;
- then **Sources**: every URL you opened.
