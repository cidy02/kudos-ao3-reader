# A43: Android controls a TalkBack reader cannot name

- Matches examined: 306
- Named: 304
- Not named: 2

## Summary by Control Pattern

- `IconButton(`: 79 examined (79 named, 0 not named)
- `ToolbarCircleButton(`: 36 examined (36 named, 0 not named)
- `.clickable(`: 92 examined (90 named, 2 not named)
- `.clickable {`: 75 examined (75 named, 0 not named)
- `.combinedClickable(`: 16 examined (16 named, 0 not named)
- `.toggleable(`: 4 examined (4 named, 0 not named)
- `.selectable(`: 4 examined (4 named, 0 not named)
- `FloatingActionButton(`: 0 examined

All 494 `.kt` files in `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` were reached and examined. Zero files remained unreached.

---

## Table of Not-Named Controls (Grouped by File)

| `path:line` | Three lines starting at match | What it shows |
|---|---|---|
| `android/app/src/main/java/io/github/cidy02/kudos/library/QueueOrganizerScreen.kt:433` | <pre><code>                    SelectionBubble(selected, Modifier.clickable(onClick = onToggle))&#10;                }&#10;                if (reordering) {</code></pre> | Inside `SelectionBubble` (`android/app/src/main/java/io/github/cidy02/kudos/library/QueueChrome.kt:496-501`):<br><pre><code>        if (selected) {&#10;            androidx.compose.material3.Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))&#10;        }</code></pre>When `selected` is true, its only content is an `Icon(..., contentDescription = null)`. When `selected` is false, it contains no icon or content (empty box). |
| `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderFanMenu.kt:301` | <pre><code>                .clickable(&#10;                    interactionSource = remember { MutableInteractionSource() },&#10;                    indication = null,</code></pre> | Dismiss backdrop `Box` in `ReaderFanMenuDismissBackdrop` (`android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderFanMenu.kt:298-306`). Shows no content; contains no `Icon(` or `Image(`. |

---

## Details by File

### 1. `android/app/src/main/java/io/github/cidy02/kudos/library/QueueOrganizerScreen.kt`

- **Match**: `android/app/src/main/java/io/github/cidy02/kudos/library/QueueOrganizerScreen.kt:433`
- **Three lines starting at match**:
```kotlin
                    SelectionBubble(selected, Modifier.clickable(onClick = onToggle))
                }
                if (reordering) {
```
- **What it shows**:
Attached to `SelectionBubble(selected, ...)`, defined in `android/app/src/main/java/io/github/cidy02/kudos/library/QueueChrome.kt:488-502`:
```kotlin
@Composable
fun SelectionBubble(selected: Boolean, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier
            .size(22.dp)
            .clip(CircleShape)
            .background(if (selected) tokens.accent else Color.Transparent)
            .border(1.5.dp, if (selected) tokens.accent else tokens.secondaryInk, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        if (selected) {
            androidx.compose.material3.Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
        }
    }
}
```
When `selected` is true, its only content is an `Icon(..., contentDescription = null)`:
```kotlin
androidx.compose.material3.Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
```
When `selected` is false, it contains no `Icon`, `Image`, or `Text`. It has no `contentDescription`, no `accessibilityName`, and no accessibility semantics.

---

### 2. `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderFanMenu.kt`

- **Match**: `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderFanMenu.kt:301`
- **Three lines starting at match**:
```kotlin
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
```
- **What it shows**:
Attached to `Box` in `ReaderFanMenuDismissBackdrop` (`android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderFanMenu.kt:292-308`):
```kotlin
@Composable
fun ReaderFanMenuDismissBackdrop(
    isOpen: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (isOpen) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onDismiss
                )
        )
    }
}
```
It shows no content (an empty fullscreen scrim `Box` used to dismiss the fan menu). It contains no `Icon` or `Image` inside. It has no text, no spoken label, and no accessibility semantics.

## Triage (Claude, 2026-10-10)

306 controls examined, 2 unnamed, both real and both fixed:

- `library/QueueOrganizerScreen.kt:433`: the selection bubble on a queue's row was a bare
  clickable. It is now a checkbox that says "Select <queue's name>" and whether it is ticked.
- `reader/ReaderFanMenu.kt:301`: the page behind the reader's open menu. Its tap now has the
  label "Close menu".

Neither was tried with TalkBack on the emulator. Flash's count of the other 304 as named was
not checked; the three kinds it was asked about that are missing from its summary
(`.combinedClickable(`, `.toggleable(`, `.selectable(`, `FloatingActionButton(`) may not have
been searched.

