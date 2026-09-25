# Brief — account-leftovers (wave 3, cloud)

Source: `account-leftovers.json`; critic-wave3 confirmed every item. Facts:
`otwarchive-facts-wave3.json` Q16, Q17. Base `c4ce1e2`. Paths are under
`kudos-ao3-reader/` unless they start with `KudosTests/` or `docs/`.

Two items. No bugs were found in this area. One small gap, and one M item
that is worth doing because the code wrote it off on a premise AO3's own
templates contradict.

**Keep out of:** `Services/AO3Client.swift` (`parseSearchPage` lives there:
parse the draft notice in a separate function, and do not extend
`parseBlurb`), `AO3RequestCoordinator.swift`, `RequestCoalescer`, and
`project.pbxproj`.

---

## Small gap

### L1 — Blocked users and Muted users rows (1z.3)

- **Files:** `Features/Account/AO3PreferencesView.swift:577-632`.
- **Spec:** 1z's Account group ends "Blocked users", "Muted users".
- **Fact:** Q16. The pages are `/users/:login/blocked/users` and
  `/users/:login/muted/users` (index; owner or admin). The rows were left out
  because `/users/<name>/blocked` and `/muted` returned 404. Those paths are
  not routes.
- **Change:** two more `AccountExternalNavCard` rows (`pathSuffix:
  "blocked/users"`, `"muted/users"`, symbols `hand.raised` and
  `speaker.slash`). Show no counts, since the preferences page carries none
  (1z.4). Correct the doc comment at :577-588.
- **Test:** if the rows move into a static table, assert both suffixes are in
  it. Otherwise none (the routes are cited in the facts file).

## M item (optional in this batch)

### L2 — Days left and expiring this week on Drafts (1x.2)

- **Files:** `Services/AO3Client+Works.swift:119-124` (`draftsPage`),
  `Services/AO3WorkActions.swift:116`,
  `Features/Writing/WritingDraftsView.swift:14-28`, `:145-160`, and a new
  fixture.
- **Spec:** 1x: "4 drafts · 2 expiring this week", a "N days left" chip and
  "Created …" on each draft.
- **Fact:** Q17. Every unposted work's blurb carries
  `<p class="caution notice">This draft will be <strong>scheduled for
  deletion</strong> on <abbr class="day" title="Monday">Mon</abbr> <span
  class="date">05</span> <abbr class="month" title="October">Oct</abbr> <span
  class="year">2026</span>.</p>`. The date is `created_at + 29 days`, in AO3's
  zone. `WritingDraftsView`'s reason for not building this ("the drafts listing
  carries no creation date") is contradicted.
- **Change:**
  1. `static func parseDraftDeletionDates(_ html: String) -> [Int:
     DateComponents]` in `AO3Client+Works.swift` (or a new file). For each
     `li.work.blurb` with id `work_<n>`, read `p.caution.notice span.date`,
     `abbr.month[title]` and `span.year`.
  2. `draftsPage` returns the page plus that map (a small
     `AO3DraftsPage { page, deletionDates }`). `AO3WorkActions` passes it
     through.
  3. A pure `DraftExpiry.daysLeft(until: DateComponents, now: Date, calendar:
     Calendar) -> Int?` gives whole calendar days, clamped at 0. "Created" is
     that date minus 29 days.
  4. In `WritingDraftsView`, the chip is drawn only when a date parsed. The
     tally adds "· N expiring this week" (N = days left ≤ 7) on a single page;
     on several pages it says "on this page". Rewrite the doc comment's
     "What is not built" bullet.
- **Tests:** a fixture built from otwarchive's `_work_module.html.erb` markup
  (not invented) parses to 5 Oct 2026 for its work id. Test that a blurb
  without the notice is absent from the map. For `daysLeft`: same day → 0,
  tomorrow → 1, past → 0.
- **Caveat:** AO3 prints the date in its own time zone. The chip is whole days,
  so near midnight it can be one day generous. Show "Deletes on 5 Oct" beside
  the count if that matters to the owner.

---

## Needs the owner

- **1x.3 — Post and Delete as swipes.** The board draws them. The code keeps
  them in the editor, because posting notifies subscribers and cannot be
  undone, and a swipe fires easily. This is a deliberate deviation; the owner
  may overrule.

## Later

- Nothing else from this area.
