# 3eg: Codex's A49 review, Read Aloud findings F1 to F4 (Android)

Done 2026-10-14 by Claude. Gate 2,662. Each finding read against the code first; all four real.

- **F1 (P2):** Android 11+ shows an app only the speech engines it asks for, and the
  manifest asked for none, so a separately installed offline engine was invisible and Read
  Aloud offered the Kokoro pack instead. The manifest declares the `TTS_SERVICE` query now
  (seen in the built app's manifest). Not tried with a second engine installed.
- **F2 (P1):** the device voice checked "playing", then handed the stretch to the engine
  outside the lock that Pause and Stop take, so a Stop between the two was followed by
  speech, and a reading a newer one had replaced could still speak. The check and the
  hand-over are one step under that lock now, and a replaced reading hands nothing over. No
  test forces the timing.
- **F3 (P1):** the engine was chosen afresh for every action, so when the pack finished
  downloading mid-reading, Pause and Resume went to Kokoro while the device spoke, and the
  download's end marked the player stopped. One engine now owns a reading until Stop, and
  the download's end only readies a player that was waiting for the pack.
- **F4 (P2):** a pack that was there but would not open made Read Aloud skip silently through
  the text. Kokoro is used only when it opens; otherwise the device's voice reads, and a
  pack that failed to open is not tried again for every stretch. `SystemTTSServiceTest`
  `aPackThatWillNotOpenReadsWithTheDeviceVoice` fails without it. **Left:** a way to replace a
  broken pack (the download refuses while files are there); worth an owner question if seen.

Seen on the emulator: Read Aloud plays, pauses, resumes and stops.
