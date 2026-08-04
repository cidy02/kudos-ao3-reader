# Adversarial Self-Review: Phase 7 (Home / Onboarding / Privacy / Support)

## 1. State Persistence
- **Finding**: `collapsedShelves` in `HomeScreen` uses `remember { mutableStateMapOf(...) }`.
- **Impact**: It's lost on rotation or process death.
- **Fix**: Use `rememberSaveable` with a custom saver, or move it to a ViewModel if persistence is critical. For now, it matches iOS "session-only" behavior.

## 2. Bug Report Logic
- **Finding**: `BugReportScreen` encodes the body into a URL.
- **Risk**: For extremely long descriptions, this might exceed the intent size limit or URL length limit for some browsers.
- **Mitigation**: GitHub issues have a reasonably high limit. If it fails, the browser just won't load the prefilled fields.

## 3. Privacy Gating
- **Finding**: `HomeWorkCover` now gates `onOpen` and `onOpenDetails` correctly.
- **Verification**: If `obscured` is true, both tap targets call `onReveal`. (Confirmed in code).

## 4. Onboarding
- **Finding**: "Find works to read" button in `HomeScreen` is only shown when `!state.hasSavedWorks`.
- **Verification**: This correctly triggers `onOpenBrowse`.

---

# Action Plan for Self-Review Findings:
1. (Optional) Enhance `collapsedShelves` with `rememberSaveable` if rotation churn is an issue.
2. Verify `PrivacyGate` biometric logic in a real device (Simulation not possible here, logic follows iOS implementation).
