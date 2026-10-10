# Brief 3ch: the writer's own totals on their Works list (audit A34-1)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle. Claude builds, tests and commits afterwards, so make what you write compile by
reading the real symbols you use, and say which claims need a test run. Write
`docs/android-port/briefs/3ch-result.md` as you go. Put every open question in your final
summary, not only the first.

**Android only.** A small missing feature, P3.

## What iOS does

On the signed-in reader's **own** profile, Works tab, the line under the title reads
"12 works · 248,400 words · 3,812 kudos" (`Features/Authors/AuthorProfileView.swift:340` to
`:358`). The words and kudos come from one read of `/users/<name>/stats`
(`Services/AO3AuthorProfileService.swift:335`, `loadOwnStats`), made after the header and the
selected tab have loaded, **only** when the route is the signed-in account's and has no pseud
(`ownsThisRoute`, `:349`), once per opening (`guard stats == nil`), through the page cache, and
**silent on failure**: the line keeps its count and name. The parser is
`Services/AO3Client+Stats.swift:55` (`dl.statistics.meta`, each `dd` by its class names; a page
with no totals block is an account with no works, not a failure).

## What to build

1. `network/ao3/author/`: the address (`/users/<name>/stats`), a parser for the totals block with
   iOS's rules, and `AO3AuthorRepository.loadOwnStats(route)` through `AO3PageCache` (add a
   `Kind`), read with the session. Only words and kudos are shown; parse what iOS parses.
2. `author/AuthorProfileScreen.kt`: read it after the header and the tab, under iOS's three
   conditions, fenced by the route and the session count as the other loads are, silent on
   failure, not repeated by a tab change, **repeated by pull to refresh** (which reads past the
   cache). Find where Android shows the own Works list's count and name today and put the two
   figures in the same line, in iOS's words and order, with thousands separators as iOS's
   `.formatted()` gives them. If Android shows no such line on that screen, say so and propose
   the smallest place for it rather than inventing a new block.
3. The demo already answers `/users/<name>/stats` (`network/ao3/DemoNetwork.kt:215`, fixtures
   `ao3_user_stats.html` and `ao3_user_stats_none.html`): check the fixture is what AO3 serves
   (compare with iOS's test fixture) and use it.
4. `docs/AO3_NETWORKING_POLICY.md`, the "Author profiles" row: add this read to the sentence
   about what the account's own page loads. It is one read of the reader's own page on an
   explicit opening.

## Tests

The parser on both fixtures; the three conditions (another author's page, a pseud route and a
signed-out reader make no stats request: count the requests); a failed stats read leaves the
line as it was and shows no error; a session change while the read is out publishes nothing;
pull to refresh reads it again.

## What the result must say

Where the line is on Android and what it says before and after, the request order for one
opening beside iOS's, and anything you saw in these files and left alone.
