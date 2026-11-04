---
name: ao3-ground-truth
description: >-
  Use when changing anything that parses AO3's HTML, builds an AO3 request body, picks a CSS selector,
  or adds/edits a fixture in KudosTests/Fixtures — and whenever you are about to assume how an AO3 page
  is shaped. AO3 is open source, so its own source settles these questions; guessing, or trusting a
  hand-written fixture, has shipped silently broken features in this project before.
---

# AO3's source is the ground truth

AO3 runs **otwarchive**, which is open source: `https://github.com/otwcode/otwarchive`. Anything about how
a page is shaped, what a form posts, or which parameters a controller requires is a **fact you can look up**,
not something to infer from one saved page.

## The rule

Before you change a parser, a selector, a POST body, or a fixture:

1. Read the relevant otwarchive source — `app/views/**` for page shape, `app/controllers/**` for what a
   request must carry, `app/models/**` for validation.
2. **Cite the commit you read**, as `docs/COMMENTS_AO3_API_AUDIT.md` does (it pins
   `otwcode/otwarchive master 41d3878b…`, 2026-07-14). A claim about AO3 without a citation is a guess.
3. Only then write the code, and make the fixture match what the source says the page contains.

## Why this rule exists

The comments audit found that **every native reply failed for every signed-in account**, and top-level
comments failed for the common single-pseud account. The cause: the code read `comment[pseud_id]` from a
`<select>` element, but otwarchive renders a **hidden input** for single-pseud accounts, and the plain
`/comments/<parent>` page the app fetched renders **no comment form at all**. A saved fixture happened to
contain the `<select>`, so the tests passed. Reading `comments_controller#create` settled it in minutes.

The lesson generalises: **a fixture proves only what its author believed.** It is evidence about one page
at one moment, not about the site.

## What this does NOT license

Reading otwarchive's source is free. Talking to AO3 is not:

- `docs/AO3_NETWORKING_POLICY.md`'s "must not implement" list is binding, and its rules on pacing,
  user-agent and page budgets apply to every request.
- **Never hit live AO3 to find out how something behaves.** Read the source, then test against a fixture.
- No AO3 writes except against fixtures. No sign-in.

If the source and a fixture disagree, the source wins and the fixture is wrong — fix the fixture and say so
in your handback.
