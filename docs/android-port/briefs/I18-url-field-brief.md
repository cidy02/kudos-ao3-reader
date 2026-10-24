# I18 — the iPhone's URL field: paste, undo, VoiceOver, Dynamic Type

**Agent:** Sonnet 5.5 (agy account 2). **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-i18`
(from the iOS lane's `f24572c2`). One file to change, one test file.

## Context

`kudos-ao3-reader/UIComponents/URLTextField.swift` is the parent work's URL field: a `UITextView` that
wraps a long address at any character, drops line breaks, and ends editing on Return. Gemini's review
(A95) found four small faults, confirmed from the code:

1. **A paste that contains a line break ends editing.** `shouldChangeTextIn` (`:120-133`) treats any
   replacement with a line break like Return: it inserts the cleaned text, then calls
   `resignFirstResponder()` (`:131`). Only a Return should end editing. A pasted address that ends in
   a line break, which many apps copy, should be inserted without it and editing should continue.
2. **That paste clears undo.** It goes through `show(_:in:)` (`:106-114`), which sets `attributedText`
   and so clears the undo stack. Insert it in a way that registers with undo, for example UITextInput's
   `replace(_:withText:)` on a `UITextRange` built from `range`. That also calls `textViewDidChange`,
   which updates the binding. The typing attributes (no hyphenation, char wrapping) must still apply to
   the inserted text.
3. **VoiceOver never hears the placeholder.** The placeholder `Text` is `.accessibilityHidden(true)`
   (`:31`), so an empty field reads only "URL". Expose the placeholder to VoiceOver on the text view,
   for example as its `accessibilityHint`. Pass it into `URLTextView`.
4. **A Dynamic Type change keeps the old paragraph attributes.** `updateUIView` (`:70-73`) re-applies
   the attributes only when the text changes, so after a text-size change the stored font in
   `attributes` is stale until the next edit. Re-apply them when the content size changes (track the
   last `context.environment.dynamicTypeSize` in the coordinator, or compare the view's font).

## Tests

Add to `KudosTests/URLTextFieldWrappingTests.swift` (Swift Testing, inside its `#if os(iOS)`), so each
test fails with its change reverted:
- Extract the decision in item 1 into a small pure function (for example, given the replacement text,
  return the text to insert and whether editing ends) and test: a lone "\n" ends editing and inserts
  nothing; "https://a.org/works/1\n" inserts "https://a.org/works/1" and does not end editing;
  "\r\n" alone ends editing.
- Item 3: build the `UITextView` the representable makes (make a static factory the representable uses,
  if needed) and check that its accessibility hint is the placeholder.
- Items 2 and 4 need a window or a live Dynamic Type change: no test is required, but say in the result
  how Claude should check them on the simulator.

## Rules

- Change only `URLTextField.swift`, `WorkAssociationPickers.swift` if a call site must pass the
  placeholder (it already does), and the test file.
- Keep the field's existing behaviour: wraps at any character with no hyphen, at most four lines then
  scrolls, trailing alignment, Return ends editing, typed line breaks dropped.
- Do not commit, push, build, run tests or the simulator (Claude does), sign in, or contact
  archiveofourown.org. Do not edit `TASKS.md`. SwiftLint stays at its current level.

## Output

Write `docs/android-port/briefs/I18-result.md` **first**, then keep it current: per item, `path:line`
and what changed; per test, what it checks and how it fails with its change reverted; how to check items
2 and 4 on the simulator.
