# Batch 9 — Challenges polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html` (artboards extracted by script; px = pt). Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree. No build, no simulator, no AO3 traffic. iPhone / iPad / macOS layout, keyboard avoidance, Dynamic Type clipping, Reduce Motion, and how `Color.white` fills look in light or sepia were not seen on a running screen. Anything that needs one is called out as unverified.

Where `docs/REDESIGN_DECISIONS.md` or `docs/REDESIGN_PLAN.md` already supersedes an artboard, that is under the screen’s checked list, not filed as a defect to revert.

Shared chrome, once, so it is not six findings. All six screens use `SubjectHeaderBlock` (title 32 bold, tracking −0.6, subtitle 15.5 scaled — `SubjectSurface.swift:467–468`) rather than the artboards’ 12.5px subtitle. Section labels go through `SectionRuleHeader`. Segments are `SubjectSegmentedControl` (glass, 13pt), not the artboards’ accent-filled 30px tray. Date and count values that pass `isMonospaced: true` render as 11pt medium mono (`SubjectForm.swift:322–339`, the component’s own “500 11px” rule), while these artboards draw those values at 400 15px. Panels use `subjectPanel` radius 14 (`SubjectForm.swift:47`). Bottom bars are the same pattern: 14 semibold, height 44, radius 12, gap 9, padding 12×16×26. `subjectScreenWash` (`SubjectScreen.swift:98–108`) is the staged form: it keeps the system back chevron and does not install 34pt glass circles. None of these six add a `…` menu. The artboard `…` buttons have no items drawn, and these are not works lists, so `WorkListMoreMenu` order does not apply. `REDESIGN_DECISIONS` **1j** says keep text Cancel/Create, not a round check — 1ca’s **Submit sign-up** and 1cf’s **Save changes** follow that.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1by | Challenge settings, read | `ChallengeSettingsView.swift` |
| 1bz | Sign-ups | `ChallengeSignUpsView.swift`, detail in the same file |
| 1ca | Your sign-up | `ChallengeSignUpView.swift`, `PromptTagsEditorView.swift` |
| 1cb | Assignments | `ChallengeAssignmentsView.swift` |
| 1cc | Prompts | `PromptMemeView.swift` |
| 1cf | Challenge settings, edit | `ChallengeSettingsEditView.swift`, `ChallengeSettingsEditSections.swift` |

Entry from the collection is `AO3CollectionDetailView.swift:348–387`: Sign-ups and Assignments when the dashboard URL exists and the viewer maintains the collection; Prompts for anyone when the prompts URL exists; Your Sign-up when signed in; Challenge Settings for owners only.

---

## Findings

### batch-9-1 — P1 — 1bz / 1cc — `ChallengeSignUpsView.swift:269` / `PromptMemeView.swift:358`

**Artboard / convention:** an empty list names the thing that is missing and offers the action that fills it. Checklist E: empty state with an action, nothing blank. The segments are **All | Matched | Unmatched** and **All | Unclaimed | Yours**.

**Code:** the title interpolates the segment’s raw value. All becomes **No all sign-ups** and **No all prompts**. Yours becomes **No yours prompts**. The body says the page does not match the **“All”** filter when the list is simply empty. Neither card has a button. Create sign-up, Your sign-up, and New prompt sit on the bottom bar (New prompt is hidden when signed out — batch-9-15).

**Smallest fix:** if the segment is All, title **No sign-ups yet** / **No prompts yet** and name the existing create action in the card. Keep **No matched sign-ups**, **No unmatched sign-ups**, **No unclaimed prompts**. For Yours, **No prompts of yours**.

---

### batch-9-2 — P1 — 1cb — `ChallengeAssignmentsView.swift:384`

**Artboard:** on the unmatched card, two pills, height 34, radius 99, 600 12.5: **Send pinch-hit request** (accent) and **Open on AO3** (neutral). Caption: reporting a default and claiming a pinch hit are the writes; matching is not exposed; the escape hatch is Open on AO3 rather than a disabled control. Footnote: “The app can read them, report a default and send a pinch-hit request.”

**Plan:** `docs/REDESIGN_PLAN.md` (2026-09-12, ~1756): **“Send pinch-hit request” is Open on AO3 — there is no moderator-side request-a-pinch-hit write.** The file header (`ChallengeAssignmentsView.swift:9–14`) says the same. The bottom bar’s real writes are **Report a default** and **Claim a pinch hit** (`:654–688`), and `REDESIGN_DECISIONS` says build those.

**Code:** both card buttons call `openOnAO3Button`, and both open `AO3ChallengeURL.assignments(slug:list:.pinchHits)` (`:402–405`). Both are `Label(..., systemImage: "safari")` `.buttonStyle(.bordered)`. The accent one still says **Send pinch-hit request**. The same false verb survives on the read screen’s footnote: “The app can show sign-ups and assignments and send a pinch-hit request” (`ChallengeSettingsView.swift:441–442`), which is the artboard sentence copied through after the plan retired the write.

**Smallest fix:** one button, **Open on AO3**, neutral. Drop **Send**. Keep Report a default and Claim a pinch hit on the bottom bar. Change the 1by footnote to the sentence 1cb already uses at `:416–418` (a pinch-hit request opens AO3).

---

### batch-9-3 — P1 — 1ca — `ChallengeSignUpView.swift:635`

**Artboard / owner goal:** Add is in the bar (**Add request**, **Add an offer**). Checklist B: delete is a trailing swipe plus Select, through `destructiveConfirmation`. The caption’s point is that a sign-up AO3 would reject never leaves the device.

**Code:** **Add request** (`:635–638`) and **Add an offer** (`:641–644`) only append. `ensureMinimumPrompts` (`:624–632`) always inserts one request and, for a gift exchange, one offer. Live rows are `requests.filter { !$0.destroy }` (`:63–67`). `validated()` counts only prompts with `destroy == false` (`AO3ChallengeModels.swift:504–505`). The POST writes `_destroy` (`AO3Client+Challenges.swift:767`). Nothing in `ChallengeSignUpView` sets `destroy`. A third request that fails the tag check cannot be taken off the form. There is no swipe and no Select.

**Smallest fix:** trailing swipe **Remove**. A never-saved prompt (negative id, `AO3ChallengeModels.swift:481–483`) is dropped. A prompt AO3 already has sets `destroy = true` after `destructiveConfirmation`. Do not let Remove go below the challenge’s required count without the existing validation error.

---

### batch-9-4 — P2 — 1ca — `ChallengeSignUpView.swift:275`

**Artboard:** under the four tag rows, toggle **Any of these is fine**, caption **“Matches on any chosen tag rather than all of them.”** On.

**Code:** the switch is labelled **Any of these is fine** and the hint is **“Any relationship matches, not only the ones chosen”** (`:277–289`). The binding is `anyRelationship` only (`:275`). `validated()` enforces “Choose X or Any, not both” for every tag type (`AO3ChallengeModels.swift:537–545`), and `anyFandom` / `anyCharacter` / `anyFreeform` are posted (`AO3Client+Challenges.swift` writes the `any_*` fields). `PromptTagsEditorView` (`:32–58`) is four comma-separated fields and a **Done** button. It has no Any control. Existing flags round-trip; the user cannot turn them on. The switch sits under Fandoms, Relationships, Characters, and Additional tags, so it reads as applying to all four.

**Smallest fix:** rename this switch **Any relationship is fine** and add one Any control per tag type on the editor (or four switches on the request). Do not leave validation able to demand an Any the form cannot set.

---

### batch-9-5 — P2 — 1ca — `ChallengeSignUpView.swift:239`

**Artboard:** empty-or-unset tag rows read as a count of what was chosen (**2 chosen**, **3 chosen**, **4 chosen**). Fandoms show the names.

**Code:** Fandoms empty is **None chosen** (`:232`). Relationships, Characters, and Additional tags empty are the word **Optional** (`:242`, `:253`, `:264`), including when the challenge’s range requires them. **Optional** is also the 1by value for “this challenge allows the type” (`ChallengeSettingsView.swift:347`), so the same word means two different facts.

**Smallest fix:** **None chosen** for every empty type. Reserve **Optional** for a type whose upper bound is 0 or that the challenge marks optional.

---

### batch-9-6 — P2 — 1ca — `ChallengeSignUpView.swift:120`

**Artboard footnote:** **“Sign-ups can be edited until they close and withdrawn after, which AO3 treats as two different writes.”** The board itself has no withdraw section; the footnote and the caption are why the row exists.

**Code:** the row is **Withdraw sign-up** (`:440`). The dialog button is **Withdraw Sign-up** (`:125`). The message is always **“Withdrawing removes your requests and offers from \(title).”** (`:132`). `performWithdraw` (`:670–675`) always calls `withdrawSignUp`, the open-sign-up DELETE (`AO3ChallengeActions.swift:74–86`). `withdrawSignUpAfterClose` (`:89–96`) exists, is the giver’s own default, and is never called. The comment at `:89–90` says that after close AO3 refuses destroy. The form has no `signupOpen` flag (`signupOpen` lives on settings, `AO3ChallengeModels.swift:241`, and is read only for the sign-ups subtitle). The offers footnote repeats the two-writes sentence (`ChallengeSignUpView.swift:420–422`) while the dialog promises removal. Confirms are a raw `.confirmationDialog`, not `destructiveConfirmation` (`DeleteConfirmation.swift:51`).

**Smallest fix:** while sign-ups are open, confirm removal with `destructiveConfirmation` and call `withdrawSignUp`. After close, either call `withdrawSignUpAfterClose` and say it defaults the assignment, or hide Withdraw and say AO3 only removes a sign-up while sign-ups are open. Sentence-case the button to match the row: **Withdraw sign-up**.

---

### batch-9-7 — P2 — 1by — `ChallengeSettingsView.swift:416`

**Artboard:** Assignments rows all disclose: **Sign-ups · 31**, **Assignments · “29 matched, 2 unmatched”**, **Defaults and pinch hits · 1**.

**Code:** Sign-ups discloses into `ChallengeSignUpsView` (`:400–411`). Assignments (`:416–419`) and Defaults and pinch hits (`:423–427`) are plain values. Both screens exist, and collection Manage already links them (`AO3CollectionDetailView.swift:353–360`). `REDESIGN_PLAN` (~3649) removed dead chevrons on rows AO3 cannot edit. These two are not dead: the destination is in the app. `ChallengeAssignmentsView` has no initial-segment argument; it opens on `.unmatched` (`:33`).

**Smallest fix:** disclosure on both. Assignments opens 1cb on Matched. Defaults and pinch hits opens it on Unmatched or Pinch hits — that needs an initial segment, which the view does not take today.

---

### batch-9-8 — P2 — 1by — `ChallengeSettingsView.swift:347`

**Artboard:** **Additional tags · Optional**, with a disclosure chevron. The chevron is a dead control on a read-only row; `REDESIGN_PLAN` (~3649) already removed those. The value is the remaining defect.

**Code:** `optionalTagsAllowed ? "Optional" : "Required"`. When the flag is false the challenge does not allow the type. **Required** is the opposite word. The edit screen’s switch is correctly labelled **Optional tags allowed** (`ChallengeSettingsEditView.swift:440`).

**Smallest fix:** **Allowed** / **Not allowed**.

---

### batch-9-9 — P2 — 1cb — `ChallengeAssignmentsView.swift:255` / `:715`

**Artboard:** matched row **“kestrelmoon → nine_of_swords”** (recipient toward giver, from the sample names) and secondary **“Assigned 2 Oct · due 1 Dec”**.

**Code:** the row is `requestPseud → giver` (`:255`), 15 medium. The default picker is the reverse: `giver → requestPseud` (`:715–716`). The confirm sentence does name both roles (“mark \(giver)'s assignment for \(recipient)”, `:722–724`), so the alert is honest. The menu the moderator picks from is not the order they just read. A gift exchange’s whole job is not mixing those two people up.

**Smallest fix:** one direction on the row and the picker, with the words giver and recipient rather than a bare arrow.

---

### batch-9-10 — P2 — 1cb — `ChallengeAssignmentsView.swift:151`

**Artboard:** subtitle **“29 matched · 2 unmatched · works due 1 Dec 2026”**. The unmatched card’s artboard prose (“Two sign-ups did not match… share no fandom”) is stale: the list is AO3’s defaults queue, not potential matches. The rewrite at `:372–396` is the honest one. Do not restore the artboard sentence.

**Code:** after load, the subtitle is `"\(matched.count) matched · \(unmatched.count) unmatched"` (`:154–155`), including **0 matched · 0 unmatched**. The read screen already special-cases that as **None sent yet** (`ChallengeSettingsView.swift:436`). The tab is titled **Unmatched** (`:60`) and the section **Unmatched sign-ups** (`:229`), while the empty card says **“No defaulted assignments are waiting for a pinch hitter.”** (`:234`) and the loader fetches `[.defaults]` (`:454`). `potential_matches` is unparsed (comment `:353–358`). Before anyone has matched, the tab reads as a finished match with zero left over.

**Smallest fix:** when both counts are 0, use **None sent yet**, matching 1by. Name the tab and the count **Defaulted** (or **Needs a pinch hit**) so the word matches the list.

---

### batch-9-11 — P2 — 1cb — `ChallengeAssignmentsView.swift:244`

**Artboard:** matched rows are one radius-14 group. Chips are **delivered** (accent fill `.18`, text `#E39B9B`) and **late** (white `.1` / white `.6`), 700 8.5px, tracking `.07em`, padding 3×7, radius 5 — the same chip as 1bz. A second row has no chip. No chevron: there is no assignment detail screen, and dead chevrons were removed on purpose.

**Code:** each assignment is its own `subjectCard` in a `VStack(spacing: 9)` (`:244–273`). Badges are **DELIVERED** / **LATE** / **DEFAULTED**, 9pt bold capsules in `.green`, `.secondary`, and `.orange` (`:288–308`). Defaulted is a real third state; keep the state. System green and orange ignore the four themes. The open pinch-hit chip in the same file already uses accent `.18` and radius 5 (`:595–604`).

**Smallest fix:** one grouped panel, and the 8.5pt radius-5 chip. Delivered uses the accent. Late and Defaulted use the theme’s neutral glass, with the word carrying the difference. Do not add a chevron.

---

### batch-9-12 — P2 — 1cb — `ChallengeAssignmentsView.swift:629`

**Artboard / decision:** **Claim a pinch hit** is a real write (`REDESIGN_DECISIONS`). The confirm copy is **“You'll be the pinch hitter for \(recipient)'s gift”** (`:727`).

**Code:** `claimPinchHit` posts whatever byline it is given into `cover_<id>` (`AO3ChallengeActions.swift:120–131`) and refuses an empty name. The view always passes `auth.username ?? ""` (`:630–632`). An owner cannot name a different pinch hitter. The confirm is honest about the hardcode, and wrong for the field AO3 actually has. Owner-only is correct: the comment at `AO3ChallengeActions.swift:117` says collection owners only, and the bar is gated the same way (`ChallengeAssignmentsView.swift:105–107`).

**Smallest fix:** one line for the name, defaulting to the username, before the confirm. Post that string.

---

### batch-9-13 — P2 — 1bz — `ChallengeSignUpsView.swift:254`

**Artboard:** unmatched chip fill `rgba(255,255,255,.1)`, text white `.6`. Matched is accent `.18` / `#E39B9B`. Size matches: 8.5 bold, tracking `.07em`, padding 7×3, radius 5 (`:246–255`).

**Code:** the matched fill is `palette.accent.opacity(0.18)`. The unmatched fill is `Color.white.opacity(0.10)` (`:254`). That is white-on-white in a light or sepia theme. Not seen rendered. The claimed pinch-hit chip uses `Color.secondary.opacity(0.12)` (`ChallengeAssignmentsView.swift:603`), which follows the theme.

**Smallest fix:** the secondary-opacity fill, or `theme.appTheme.glassFill`. Same chip on every challenge row.

---

### batch-9-14 — P2 — 1bz — `ChallengeSignUpsView.swift:157`

**Artboard:** section title **Sign-ups** with no count. Subtitle is the challenge total, **“31 sign-ups · open until 1 Oct 2026”**. Footnote, matched in code at `:285–287`: the segment filters what has been fetched, not the whole challenge.

**Code:** `SectionRuleHeader(title: "Sign-ups", count: filteredSignUps.count)` is the filtered loaded page. The subtitle uses `signUpTotal` (every page, `:438–440`). A 31-person exchange on page 1 of Matched can read **31 sign-ups** in the subtitle and **4** on the section. 1cc does not have this bug: its subtitle is this page’s count (`PromptMemeView.swift:170–174`) and the section count is the same filtered page (`:204`).

**Smallest fix:** drop the count, or label it **on this page**.

---

### batch-9-15 — P2 — 1by / 1bz / 1ca / 1cb / 1cf — `ChallengeAssignmentsView.swift:441`

**Convention:** signed-out collections are a `ContentUnavailableView` with **Log In to AO3…** (`AO3CollectionsList.swift:390–396`). Account works use **Log In to AO3** (`AO3AccountWorksList.swift:909`). The auth error is **“Log in to AO3 before using this feature.”** (`AO3AuthService.swift:39`).

**Code:** assignments, when signed out, sets `phase = .failed("Sign in to AO3 to view assignments.")` (`:441–443`) and the failure card offers **Retry** only (`:545` region; same Retry shape as `ChallengeSettingsView.swift:484`). Retry calls `authenticatedRequest` again and fails again. Sign-ups, the sign-up form, and both settings screens surface the auth string the same way. Prompt meme’s list is fetched anonymously when signed out (`PromptMemeView.swift:473–481`), which is right, but **New prompt** is omitted entirely when `!auth.isLoggedIn` (`:84–86`) with no login row.

**Smallest fix:** one signed-out card for the family, with **Log In to AO3**, matching collections. On Prompts, keep the public list and put **Log In to AO3** where the New prompt bar is.

---

### batch-9-16 — P2 — 1cc — `PromptMemeView.swift:257`

**Artboard:** cards radius 16, gap 9. Fandom kicker 700 9px tracking `.11em` accent, badge trailing: unclaimed is the accent chip, claimed is the neutral chip. Body 400 14px / 1.5 serif. **Posted anonymously** 400 11px. **Claim** is an accent pill, height 34, 600 12.5. The claimed card’s button is a neutral **Fill it**. Filter on the board is **Unclaimed**. Section title is **Unclaimed**.

**Plan:** `REDESIGN_PLAN.md` ~1759 says **Fill it (someone else’s claim) is Open on AO3**, because posting a fill has no client write. That audience is settled. `REDESIGN_DECISIONS` builds **New prompt** through the sign-up form, which is what the bar does (`:140–141`). Do not move New prompt back to Safari.

**Code:** status is inline lowercase **claimed** / **unclaimed**, 9 semibold, secondary, not a chip, and there is no spacer so it is not trailing (`:257–261`). Body is 14.5 sans (`:269–272`). Cards are `subjectPanel()` radius 14 in a `VStack(spacing: 9)` (`:233`, `:290`). Filter opens on **All** (`:27`). Section title is always **Prompts** (`:204`). **Fill it** is accent-tinted, with a safari icon, height 32, and it opens `AO3ChallengeURL.promptMeme` — the meme index, `/collections/:slug/prompt_meme` (`:315–320`, `AO3ChallengeModels.swift:731–732`) — only when someone else has claimed it. The claimer sees **Claimed by you** and **Release** (`:298–307`). Release fires immediately (`:506`); there is no confirm. The file header (`:14–15`) already says posting a fill is not attempted.

**Smallest fix:** keep Fill it off other people’s claims, or rename that button **Open on AO3**. On `claimedByCurrentUser`, show **Release** behind `destructiveConfirmation` and a neutral **Open on AO3** aimed at where a work is posted (the meme index is not that form). Chip and serif can follow the board; the 14pt radius is the shared panel and can stay.

---

### batch-9-17 — P2 — 1cf — `ChallengeSettingsEditView.swift:329` / `:208`

**Artboard:** **Assignments sent · “1 Nov”** when a date exists. Matching is its own group, and the footnote says matching runs on AO3. A prompt meme has no matcher (`AO3ChallengeModels.swift:263–265`: `matchSettings` is nil).

**Code:** a nil `assignmentsSentAt` displays the word **Manual** (`:329`). The read screen’s empty date is **Not set** (`ChallengeSettingsView.swift:500`). **Manual** is a stated fact the app does not have. The comment above the row (`:325–326`) says the form has no input and the value is usually unknown.

The **Matching** section is unconditional (`:208–216`). For a prompt meme, `matchSettingsPanels` draws nothing, and what remains is the fandom steppers plus **“Matching itself runs on AO3 and is not exposed to clients…”** (`:546–549`). 1by already retitles that block **Prompt requirements** (`ChallengeSettingsView.swift:140`). The fandom range still matters for a meme; the heading and the footnote do not.

**Smallest fix:** nil sent date is **Not set**. If `kind == .promptMeme`, title the section **Prompt limits**, keep the steppers, and drop the matching-runs-on-AO3 footnote.

---

### batch-9-18 — P3 — 1by — `ChallengeSettingsView.swift:352`

**Artboard:** **Allow any prompt** off, **Require a fandom match** on, the on-state drawn `#30D158`. Other challenge switches in this batch use the accent, so the green should not be copied.

**Code:** both toggles are `.constant` and `.disabled(true)` (`:352–364`). A disabled switch reads as unavailable rather than as the current value. `allowsAnyTag` is the OR of the four allow-any flags (`AO3ChallengeModels.swift:229–233`), which is the right fact, shown as a dead control. The type checkmark (`:238–242`) has no `accessibilitySelected` and no label, so VoiceOver gets a decoration.

**Smallest fix:** drop `.disabled`, or replace the switch with the words **On** / **Off**. Mark the selected type `.isSelected` and hide the checkmark from VoiceOver.

---

### batch-9-19 — P3 — 1ca — `ChallengeSignUpView.swift:387`

**Artboard:** **Add an offer** is a label and a chevron, no plus icon. Offer value **“Fandom · N tags”**. Prompt card: serif 14, **“Visible to your recipient only”**, **“218 / 1000”** mono 600 10.5. Those three match (`:311–327`, `:319`, `:325`).

**Code:** **Add an offer** adds `plus.circle` (`:387`). An offer with no fandom reads **Any Fandom** (`:413`), title case, not the tag **Any fandom**. Success is **“Sign-up submitted successfully!”** (`:661`). The **1000** counter is not a limit: `validated()` checks counts and tag ranges only (`AO3ChallengeModels.swift:500–534`), and the field does not cap. The requests footnote’s “checked here before submit” (`ChallengeSignUpView.swift:354`) is true for those ranges and false for the counter.

**Smallest fix:** drop the plus. **Any fandom**. **Sign-up submitted.** Either enforce 1000 in `validated()` or drop the “/ 1000”.

---

### batch-9-20 — P3 — 1ca — `PromptTagsEditorView.swift:32`

**Code:** the editor saves fandoms, relationships, characters, and additional tags on **Done** (`:75–79`), copying them in `onAppear` so a dismissed sheet does not write. The POST also sends `title` and `url` (`AO3Client+Challenges.swift` nested prompt fields). The editor has no fields for either. A new prompt therefore posts title `""` and url `""`. Parsed values on an existing prompt are written back unchanged — this is not a wipe. 1cf has **URL allowed in a request** (`ChallengeSettingsEditView.swift:426`). The sign-up form type does not carry that flag, so the editor is not hiding a URL it knows is allowed.

**Smallest fix:** a Title field and a URL field on the request. Show the URL row when the challenge allows it, once that flag is on the form.

---

### batch-9-21 — P3 — 1by / 1cb / 1cf — `AO3ChallengeModels.swift:168`

**Artboard:** **“1 Sep 2026”**, **“12 Oct, 09:00”**. 1cf’s footnote: dates are UTC, shown as the local equivalent, and must round-trip without drift.

**Code:** `dateText` is `Date.FormatStyle` abbreviated, time omitted, timezone GMT (`:168–170`), so en_US reads **Sep 1, 2026**. That string is what 1by, the sign-ups subtitle, and the assignments “due” half use. Edit uses a compact `DatePicker` of date plus hour and minute in a UTC environment (`ChallengeSettingsEditView.swift:286–292`), which is the round-trip, and a locked date falls back to the wire string at 13pt (`:282–283`). The schedule footnote was rewritten to the challenge’s time zone (`:344–346`), which is more accurate than the artboard’s “local equivalent” and should stay. An assignment’s **Assigned** half uses `DateFormatter` `.medium` in the device zone (`ChallengeAssignmentsView.swift:427–433`) beside a GMT `dateText` due date, so the two halves of one line can be different calendars.

**Smallest fix:** one formatter for “Assigned” and “due”. Leave the picker in the challenge zone. Do not restyle every date to 15pt regular; the 11pt mono is the shared value style (header note).

---

### batch-9-22 — P3 — 1bz / 1ca / 1cb / 1cc / 1cf

**Code:** the floating bar is padding top 12 + height 44 + padding bottom 26, about 82pt (`ChallengeSignUpsView.swift:359–361` and the same block on the other four). The list spacer under it is `minLength: 70` (`ChallengeSignUpsView.swift:104`, `ChallengeAssignmentsView.swift:94`) or `75` (`ChallengeSignUpView.swift:105`, `ChallengeSettingsEditView.swift:115`). The last row can sit under the buttons. Not seen on a device. Safe area, tab bar, and keyboard avoidance were not run; the text editors are inside a `List`, which usually scrolls, and that was not verified.

**Smallest fix:** one spacer constant equal to the bar’s height, shared by the five screens.

---

### batch-9-23 — P3 — all six

**Checklist E:** loading skeleton shaped like the content; error with retry; nothing blank.

**Code:** loading is a centered `ProgressView` plus “Loading …” on every screen (`ChallengeSettingsView.swift:464`, `ChallengeSignUpsView.swift:377`, `PromptMemeView.swift:395`, and the same block on 1ca, 1cb, 1cf). No challenge screen uses a skeleton. Failure cards have **Retry** and a message. Assignments’ empty cards are text only (`:234` and the matched/pinch empty cards beside it) with no action, which is acceptable when the list is genuinely empty and the writes live on the bar — except the All-filter sentence in batch-9-1. Pull to refresh is `.refreshable` on all six.

**Smallest fix:** one skeleton shaped like a form panel or a prompt card, used by all six. Not six one-off spinners.

---

### batch-9-24 — P3 — 1cf / 1by — `ChallengeSettingsEditSections.swift:19`

**Artboard:** Basics rows disclose separately: Name, Host byline, Tagline, Introduction **142 words**, FAQ **Set**. **Delete challenge · Opens AO3**, label 15px, not red. **Run matching · Opens AO3**.

**Code:** Name, Tagline, Introduction, and FAQ each push the same `AO3CollectionFormView` (`:16–23`). Host byline is omitted because the form has pseud ids, not names (`:27–28`); Tagline is `collection.description`, which is the label `AO3CollectionFormView` already uses. Those two are right. Introduction’s word count and FAQ **Set** / **None** match (`:33–37`). **Delete challenge** is not red and reads **Opens AO3** (`ChallengeSettingsEditView.swift:573`), which matches the board, but the URL is the edit form the user is already on (`:558–564`) because there is no confirm-delete route. **Run matching** on the edit screen goes through `router.open` (`:570`). The same row on the read screen calls `UIApplication.shared.open` / `NSWorkspace.shared.open` (`ChallengeSettingsView.swift:503–508`), so one of them leaves the app.

**Smallest fix:** route 1by’s **Run matching** through `AppRouter` like 1cf. On Delete, the value can stay **Opens AO3**; the URL should be whatever AO3 page actually offers delete, and until that route exists the row should say it opens the edit page.

---

### batch-9-25 — P3 — 1cb / 1cc — `ChallengeAssignmentsView.swift:335`

**Checklist F:** 44pt targets. `MinimumHitTarget` exists and no challenge screen uses it.

**Code:** inline **Claim** is 12pt semibold with padding 10×5 (`:335–347`), about 22pt tall, and it is the write. Prompt **Claim** / **Release** / **Fill it** are height 32 (`PromptMemeView.swift:347`). The error-dismiss **xmark** is 11pt with no hit padding (`PromptMemeView.swift:435–441`, `ChallengeAssignmentsView.swift:572–578`). `SubjectFormRow` labels are a fixed 15pt and do not scale; the header does (`@ScaledMetric`). That label size is app-wide, not a challenge bug. `subjectRowNavigation` puts an opacity-0 link in the background with its own accessibility label (`AppThemeSurface.swift:413–421`) and does not hide the row’s text. VoiceOver order was not run.

**Smallest fix:** `minimumHitTarget()` on Claim, the prompt pills, and the xmark.

---

### batch-9-26 — P3 — 1cb / 1by — `ChallengeAssignmentsView.swift:359`

**Code:** unmatched cards group defaulted names two at a time (`:359–361`) because the artboard drew two names. The comment says the list is one request per row. The title **“Two sign-ups lost their giver”** implies the two people are a pair. They are just neighbors on the page.

1by’s date block is Sign-ups open, Sign-ups close, Works due, Works revealed, Creators revealed (`ChallengeSettingsView.swift:248–289`). It does not show **Assignments sent**, which the edit screen does. The artboard’s single **Reveal** and the label **Assignments due** are the stale board: the model comment (`AO3ChallengeModels.swift:269–271`) says AO3 prints `assignments_due_at` as “Assignments Due” and mails it as the works deadline, and the two reveal rows match 1cf. Keep **Works due** and the two reveals. The missing sent row is the only gap.

**Smallest fix:** one card per defaulted sign-up. On the read, add **Assignments sent** with `dateText`, or **Not set**, in the same order as 1cf.

---

## Checked, matches

Settled divergences are listed here so they are not “fixed” back to the artboard.

### 1by — `ChallengeSettingsView`

- Kicker **AO3 Account**, title **Challenge**, subtitle **“\(title) · \(kind)”** (`:86–89`). Owners only, per `REDESIGN_DECISIONS`.
- Intro copy matches the artboard’s first sentences (`:96–98`).
- Type rows **Gift Exchange / “Sign-ups are matched into assignments”** and **Prompt Meme / “Prompts are claimed freely”** (`:209–219`).
- Dates footnote says **collection settings** rather than “1bl” (`:295–296`). Right for a user.
- **Works due** plus **Works revealed** and **Creators revealed** follow the model and 1cf, not the board’s one **Reveal** and **Assignments due**. See batch-9-26 for the missing sent row only.
- **Minimum words: 5,000** stays deleted (`REDESIGN_PLAN` ~3654: hardcoded mock).
- Requirement rows have no chevrons (`REDESIGN_PLAN` ~3649). Ranges are the live numbers.
- Prompt-meme branch exists: section **Prompt requirements**, row **Prompts · Claim and fill**, **Prompts posted anonymously** Yes/No, footnote that there is nothing to match (`:140`, `:186–201`).
- **Edit settings** (`:113`) is how a owner reaches 1cf. Not on the read board; it is the navigation.
- **At AO3 / Run matching · Opens AO3** (`:451–457`) is the escape hatch. Delete stays on 1cf. The opener is batch-9-24.
- Assignments summary **“N matched, N unmatched”** or **None sent yet** or **Couldn't load** (`:433–437`).
- Tag sets link `TagSetView` with `isModerator: true` (`:385–391`). The collection-detail comment that says no tag-set id exists (`AO3CollectionDetailView.swift:316–319`) is stale; the id is loaded here.
- Loading, failure + **Retry**, pull to refresh (`:79–80`, `:464–490`).
- Counts are exact integers, not 1.2K. Exactness matters on these screens (checklist D).

### 1bz — `ChallengeSignUpsView`

- Title **Sign-ups**. Subtitle is the plural plus **open until**, **open**, or **closed** (`:454–468`). The date comes from the owner-only settings form, so a moderator gets no date. That is a data limit, not a missing label.
- Segments **All | Matched | Unmatched**, default All. Glass control, per the header note.
- Row: 15 semibold name, request/offer counts 11.5 monospaced digit, tag summary one line (`:200–223`). Footnote matches the artboard (`:285–287`).
- Unknown match draws no chip (`:237–241`). The unknown empty copy is a separate sentence and is fine.
- Chevron and push into the sign-up detail (`:192–195`). The detail is not its own artboard.
- Bottom bar **Your sign-up** (passes the existing id when that sign-up is on a loaded page) and **Create sign-up** (`:317–357`). Creating always opens a new form; `ownChallengeSignUp` hits the new-sign-up URL and the 1cc comment says AO3 redirects a returning poster. Not filed as a second sign-up being created.
- **Load page N of M** (`:304`).
- No `…` menu. The artboard button has no items.

### 1ca — `ChallengeSignUpView`

- Title **Your sign-up**. Subtitle **Request N of M · Offer N of M** (`:160–166`).
- Fandoms, when chosen, are the joined names. Other types, when chosen, are **N chosen** (`:232–266`).
- Prompt card serif 14, placeholder **“Describe what you would love to receive…”**, **Visible to your recipient only**, mono count (`:296–331`).
- Requests footnote is generated from the live limits plus the artboard’s last sentence (`:336–354`). More accurate than a hardcoded “3 to 5”.
- Offers summary **Fandom · N tags** when there are tags (`:411–416`).
- Bottom **Add request** (disabled at the max) and **Submit sign-up**, 14 semibold, height 44, radius 12, gap 9 (`:460–503`). No toolbar check, per 1j. Submit stays enabled and runs `validated()` on tap, then shows the field error. That is a real check, not a dead accent button.
- Tag editor is comma-separated names, which is AO3’s `tagnames` fields. Format matches. Missing Any and title/URL are batch-9-4 and batch-9-20.
- Loading **Loading sign-up…**, failure + **Retry**, pull to refresh.

### 1cb — `ChallengeAssignmentsView`

- Title **Assignments**. Default segment **Unmatched** (`:33`). Tabs are exclusive. The artboard is a composite that draws all three sections with Unmatched selected; the tabs match 1bz and are correct.
- Bottom bar labels **Report a default** and **Claim a pinch hit** match the decision, owner-gated, disabled when there is nothing to act on (`:654–688`).
- Confirms exist: **Report this default?** / **Report default** (destructive) and **Claim this pinch hit?** / **Claim** (`:737–738`). Messages name the people (`:719–728`). They are raw alerts, not `destructiveConfirmation`; the copy is the part that is doing the work.
- Inline Claim on an open pinch hit uses that same confirm.
- Pinch rows **Pinch hit #N**, chips **OPEN** / **CLAIMED**, detail **Requested by** or **Claimed by … · due …** (`:588–618`). No “Open · posted · fandom” line: the model comment says maintainer rows do not carry those fields (`AO3ChallengeScreenModels.swift:75–78`).
- Empty unmatched copy is honest (`:234`). The tab title is batch-9-10.
- Matched rows omit chevrons. There is no detail screen.
- Loading spinner, per-list failure + **Retry**, pull to refresh.
- No `…` menu. Nothing on the board to put in one.

### 1cc — `PromptMemeView`

- Title **Prompts**. Kicker is the collection name. Subtitle is this page: **N prompts · N unclaimed**, plus **on page N of M**, plus **open until** when the prompt-meme edit form loads (`:170–178`, `:463–469`). The board’s challenge-wide “48 prompts” would be a lie on page 2. Section count agrees with the filtered page. Not the 1bz bug.
- Fandom kicker is 9pt bold, tracking `0.11em`, accent, with **+N** (`:244–254`). **Posted anonymously** when `isAnonymous` (`:282`); `displayedOwner` hides an anonymous poster, including from a maintainer, which is what the caption asked.
- A non-empty title is drawn at 15 semibold (`:263–267`). Not on the board; it is a real field. Keep it.
- **New prompt** opens `ChallengeSignUpView` (`:140`). That is the decision.
- Claim and release are real writes and reload the page (`:494–508`).
- Pagination is `SearchPaginationBar` (`:382`).
- The public list loads signed out (`:473–481`).
- No `…` menu.

### 1cf — `ChallengeSettingsEditView`

- Title **Challenge settings**. Kicker **Gift exchange · moderator** / **Prompt meme · moderator** (`:143–147`). The artboard also says moderator. Only owners can open it (`REDESIGN_DECISIONS`, and the Manage gate). Not filed.
- Subtitle uses the sign-up plural even for a prompt meme (`:154`). A meme’s count is still sign-ups on AO3. Left as checked.
- No toolbar check. Bottom **Save changes**, 14 semibold, height 44, radius 12 (`:582–602`), disabled when not the owner or there is no form. 1j.
- Schedule order: Sign-ups open, Sign-ups close, Assignments sent, Works due, Works revealed, Creators revealed (`:311–317`). Picker edits the wall-clock digits in UTC so they round-trip (`:275–292`).
- Extra **Time zone** row (`:335–338`) and **Sign-up instructions** editor (`:243–265`) are real AO3 fields the board omitted.
- Basics values: Name, Tagline, Introduction word count, FAQ **Set** / **None** (`ChallengeSettingsEditSections.swift:33–37`). Host byline omitted for lack of a name. Tagline = `description`, consistent with the collection form.
- Requests / Offers are **N to N** menus, not steppers (`:381–405`). Offers hidden for a prompt meme (`:386–388`).
- Toggles **URL allowed in a request**, **Description required**, **Optional tags allowed** (`:426–444`), disabled when AO3 locked them, with **“Prompts have been added so these settings can no longer be changed.”** (`:461`).
- **Allow any fandom** caption matches the artboard word for word (`:528–531`).
- Match-on summary and the per-type menus are the Q9 expansion already built (`ChallengeSettingsEditSections.swift:52–97`). Not a missing picker.
- Anonymity labels match: **Anonymous until reveal**, **Unrevealed until reveal**, **Moderated sign-ups**, **Closed to new sign-ups** (`:141–147`). Prompt meme adds **Prompts posted anonymously**.
- Reveal confirm **Reveal now?** / **Save and reveal**, and the message says works and creators cannot be hidden again (`:130–138`).
- **Run matching · Opens AO3** and **Delete challenge · Opens AO3**, label not red (`:567–575`).
- `challengeSettings` tries the gift-exchange edit URL and falls through to the prompt-meme edit URL on 404 or a failed gift-exchange parse (`AO3Client+Challenges.swift:9–25`). The edit screen requesting `giftExchangeEdit` first is not a prompt-meme 404.
- Save URLs branch on kind (`ChallengeSettingsEditView.swift:563–564`).
- Loading, failure + **Retry**, pull to refresh, save notice.

### Checklist items verified as shared, not per screen

- **A.** Header, segment, panel radius, and mono values differ from the artboard px because they use the shared components above. Filed only where a screen is inconsistent with those components or with a sibling challenge screen.
- **B.** Add sits on the bottom bar on 1bz, 1ca, 1cc. No always-on drag handles and no “Drag to reorder” hints. No works-list `…` menu to order. Delete of a sign-up prompt is the missing action (batch-9-3).
- **C.** Rows are `SubjectFormRow` / `subjectPanel` / `SectionRuleHeader`. Status chips and the prompt card are the places that invent a second style (batch-9-11, batch-9-13, batch-9-16).
- **D.** Counts are exact. Fandom names on sign-up rows are the sign-up’s own tags, one line. No raw “0%”.
- **E.** Retry exists. Skeleton does not (batch-9-23). Empty All/Yours copy is broken (batch-9-1).
- **F.** 44pt misses are batch-9-25. VoiceOver was not run. The navigation helper does not replace the row label.
- **G.** macOS sets `navigationTitle` on these screens; iOS uses the in-page header. Not seen. The spacer-vs-bar overlap is code (batch-9-22). Pull to refresh is present on all six.

---

## Three that matter most

1. **batch-9-3 (and batch-9-4).** Your sign-up can add a request or an offer and cannot remove it, even though `destroy` is on the model and on the POST. The **Any of these is fine** switch only writes relationships, while validation can demand Any for every tag type and the editor cannot set it. That is the action gap: a form the user can make invalid and cannot put back.

2. **batch-9-2.** **Send pinch-hit request** does not send anything. It opens the same AO3 page as the **Open on AO3** button beside it. The plan already decided there is no such write, and the verb is still on the card and in the 1by footnote. The real writes are the bottom bar.

3. **batch-9-16.** **Fill it** does not post a work. It is offered on someone else’s claim and opens the meme index. The person who claimed the prompt gets **Release** only, with no confirmation and no way to open AO3 to write the fill. The plan already accepted “open on AO3” for a fill; the button should say that, and the claimer is who needs it.

Close fourth, if a wrong person matters more than the prompt button: **batch-9-9**. The assignment row is recipient → giver and the default picker is giver → recipient, on the confirm that marks someone defaulted.
