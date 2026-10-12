# 3dh: the Inbox and Settings' pages beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,635. Pictures: `shots/3dh/`.

## A fault found on the way: no back button

**A Settings page opened from the scrolled list of settings had no back button**, until
the page was dragged down, which a page that fits the screen gives no reason to do. The
six pages pictured from the lower half of the list (Library, Backup, Sync Folder, Import,
Privacy, About) all came up without it.

The shell hides the top row when a page is scrolled down and keeps that by route.
Settings is one route to the shell, with its pages inside it, so the list's "hidden"
passed to whichever page was opened next. Each of Settings' pages is now named to the
shell (`PushedShellChrome.scrollKey`), which keeps each one's own: a page opens with its
row, and the list is as it was left on the way back.

Seen: the list scrolled, About opened (Back is there, and its kicker is not dimmed as if
scrolled under); Back to the list; Appearance scrolled until its row hid, then Font
opened (Back is there); another route still hides and shows its row. Settings is the only
screen in the app with pages inside one route.

## Fixed

- **The list of settings said "Obscure mature works".** Its own Privacy page, and iOS,
  call the mode "Blur".

## Compared and the same

- **The Inbox**: the header and its count line, the four filters, a row (unread dot,
  name, when, what it is on, the words, Reply), the Guest and Replied badges, the pages.
- **Settings**: the list (the same rows in the same groups), and Font, Downloads,
  Preservation, Reading Queues, Library, Import, Privacy.

## Different, left

- Reader has "Bold text" and "Justified text" on Android only. Backup has "Reset settings
  to defaults" on Android only. About has Android's "Software update".
- Listening: iOS draws the three speeds as a row of buttons and "Play Sample" in the
  accent; Android lists them as lines. The engines under it differ by platform.
- Sync Folder differs as the two platforms' folders and pairing do.
- In the Inbox, Reply is a pill on iOS and a line of accent text on Android.

## Not checked

- No test for the back button: the screen needs most of the app to stand up. The steps
  above are the check.
- Appearance's lower half, Queue Storage, the Availability sweep, Privacy & Local Data.
