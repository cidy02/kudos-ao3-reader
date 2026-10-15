# 3ep: A37's screen-state findings F8, F9, F11, F12 (Android)

Done 2026-10-15 by Claude. Gate 2,673. Each checked against the code (and iOS) first.

- **F8 (P2, real):** on a challenge's Assignments, a list AO3 refused on Refresh kept its
  earlier rows in memory: hidden on screen, yet still offered to claim or report. Only the
  rows of lists the last load read cleanly can be written from now (`candidates`). iOS
  starts every load from nothing.
- **F9 (P2, real):** for an owner whose challenge was known closed, a timed-out due-date read
  was never asked again on Refresh, so the due date and Late badges stayed missing until the
  screen was reopened. Refresh asks again unless AO3 refused it, as iOS reads it every load.
- **F11 (P2, real):** a failed next page of a series replaced the page on screen with
  "Couldn't load series". The page on screen stays while another is asked for ("Loading page
  N…") and stays if that fails ("Couldn't load page N", Try Again), as iOS keeps its works.
  Not seen: the demo's series has one page.
- **F12 (P3, real):** the own author page's More menu and a series row's menu took Material's
  own colours (seen in OLED); they take the app's card colour and ink now. Seen on the
  emulator in OLED (`shots/3ep/`).

Left from A37: F3 (a post-write read joining a pre-write read in flight), F6 (bulk form
controls for groups AO3 did not serve; iOS the same), F7 (a partial bulk tag run reports no
progress; recorded in 3cd already).
