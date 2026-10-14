# 3dm: Read Aloud reads with the device's own voice (Android)

Done 2026-10-14 by Claude, alone. Gate 2,644 (+3). Pictures: `shots/3dm/`. Follows 3dl.

## What was wrong

On the iPhone, Read Aloud reads at once: "Automatic starts with an Apple voice, then uses
Kokoro … after you install its optional voice pack." On Android, tapping Read aloud showed
"High-quality voice model needed (~45MB)" and read nothing until the Kokoro pack had been
downloaded from GitHub. Settings' Play Sample was greyed out for the same reason. 3ak had
listed the missing fallback ("Engine choice / Automatic system fallback") as engine work.

## What changed

- `AutomaticTTSService`: Kokoro once its pack is installed, the device's own voice until
  then. The reader's speech controller and Settings' sample both speak through it.
- `SystemTTSService`: Android's text-to-speech **with an on-device voice only**. A voice that
  needs the network would send the work's words to the engine's server, and Kudos says it
  sends none; such voices are never chosen (`onDeviceVoice`, tested). With no on-device voice
  it is unavailable, and the reader offers the Kokoro pack, as before. Android's engine
  cannot pause: a pause stops the stretch being read and resuming reads it again (tested).
- The pack was offered only when reading was refused for want of it. It is now a row at the
  foot of the reader's Display & Themes › Read Aloud ("Download Kokoro Voice Pack (about 45
  MB)", then its progress), the same user-started download from the reader as before.
- Listening says what happens: Engine "Device voice" while a sample plays; "Read Aloud uses
  your device's own voice. For Kokoro's, download its Voice Pack in the reader, from Display &
  Themes."; and iOS's sentence, "Automatic starts with your device's own voice, then uses
  Kokoro after you install its optional voice pack. Kudos doesn't send your reading, your
  library or any usage data."
- The player's buttons were named "Pause TTS", "Play TTS" and "Stop TTS" to a screen reader;
  "Pause", "Play" and "Stop reading aloud" now, as iOS.

Seen on the emulator (Google's engine, an on-device English voice, airplane mode): Read aloud
read, and its audio track was playing; pause, play, next and stop each did what they say;
the Display sheet showed the download row; Play Sample played with Engine "Device voice".
**Not heard** (the emulator's sound was not listened to), and the Kokoro path was not run.

## Left

- iOS's player skips by chapter ("Previous chapter", "Next chapter"); Android's by paragraph.
- iOS lists installed voices under Voice; Android's device voice is the one the device's own
  Settings chose (Automatic), and it is picked by the device's language, not the work's.
- iOS's player has a "Read-aloud settings" button opening the read-aloud sheet; Android's
  long press on Read aloud opens Display & Themes.
- Listening's Pitch row (iOS) is still absent; the device voice could honour it now.
