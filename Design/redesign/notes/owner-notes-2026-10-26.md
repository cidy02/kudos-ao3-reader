# Owner notes for the Kudos redesign (2026-10-26)

Use these alongside `Design/redesign/HANDOFF.md` and `LEDGER.md`; they don't replace them. They sharpen two
steps: **Step 0** (the direction board) and **item 6d** (the rule sweep). If you've already published the
direction board, check it against section 2 and revise it before I pick.

## 1. What I want

We've put a lot of work into the current app, and it has already been through one redesign. Don't throw that
away. Evolve it. I'm chasing a polished version I can't seem to find. It should feel like a native Apple app,
polished and coherent. Right now it feels a little one-dimensional. AO3 works have no covers, and that limits
the design options.

## 2. Why the app feels like an amateur built it

I'm not imagining this. The weaknesses are specific. Each one below cites a screenshot in
`Design/redesign/shots/evidence/`. Look at them before you design.

1. **It works against iOS instead of using it.** This is the biggest giveaway. On Work Detail (17), the large
   title "Winter Garden" scrolls under the back button and the status bar, instead of shrinking into the
   navigation bar the way every Apple app does. The cause is that the app draws its own navigation: hand-made
   glass back circles and its own back swipe. Same problem elsewhere: the queue page (03) has two back buttons
   plus a "HOME › QUEUES" breadcrumb, and reader text shows through the title bar (06).
2. **Everything is at the same volume.** Work Detail (16) stacks about seven container styles in one column:
   the stats strip, the reading card, tag chips, a language box, a kudos/hits box, a button box and a "My copy"
   box. Almost every item also has a small grey all-caps label (RATING, WARNINGS, FANDOMS, KUDOS, HITS). When
   everything is boxed and labelled, nothing leads. That is the "one-dimensional" feeling.
3. **Colour has no job.** The fandom colour washes the whole screen and spills into controls. After you visit a
   green work, Home's + button stays green (18). Library (02) shows a red pill, purple, peach and green cards,
   tag chips each in a different pastel, and a gold star. Colour decorates rather than signals.
4. **The same thing looks different from screen to screen.** The four AO3 tags are drawn four ways (01, 02, 16),
   and "No warnings" is green in one place and grey in another. "Keep reading" is a green play button in one
   place and a pill in another. On Work Detail (16), "4/6" sits over the word COMPLETE, but four of six chapters
   means the work isn't finished.
5. **Small rough edges.** Together they read as "unfinished":
   - a stats row that ends a line with a stray "•" (02);
   - a line of on-page instructions, "Tags come from AO3. Tap one to…" (16), which Apple apps don't do;
   - a raw error code with no close button (15);
   - a card that lands on a square grey plate after the zoom animation (18).

**The likely cause:** the app was built task by task, by many agents, and each one tuned its own screen.
Nobody owned the shared rules. So the fix is mostly removing things and setting rules, not adding features.

## 3. What to do with this

- In the direction board, each direction should state the rules it implies:
  - at most two container styles;
  - one corner radius and one 16 pt edge margin;
  - the system's Dynamic Type styles;
  - where all-caps is allowed (only the fandom label above a title and stat captions);
  - a job for each colour.
- Let the directions differ on the colour question in LEDGER item 1: should the fandom colour reach buttons, or
  stay on identity only, with one app colour for everything tappable? Show me both instead of asking.
- At least one direction should show Work Detail with two container styles at most and a title that shrinks
  into the navigation bar.
- After I pick, item 6d applies those rules to every board, including the eleven Duo boards that are already
  written.
- Don't add features to fill the depth gap. Depth comes from what leads on the screen and what steps back.

## 4. No covers: what other fanfic apps do

I asked for a quick survey of other apps:

- **Most AO3 apps skip covers.** Their App Store listings (Fanficly, Fanfict Reader, ArchFic, Fictivity, FFS,
  Reader Pro) describe text lists: title, author, tags, stats and filters. The bar is low, and Kudos is already
  ahead of it.
- **Download tools generate a cover from the text.** FanFicFare gives every download an automatically
  generated Calibre cover (title and author on a template). FicLab makes nicer generated covers. Apple Books
  and Kindle give a cover-less EPUB a plain title cover. Fic readers already accept typographic covers. The
  `CoverCard` text variant is in that tradition. Make each one distinct and stable per work, like Apple Music's
  generated playlist art, so a shelf looks like different works instead of one shape repeated.
- **Wattpad has author-made covers.** A story without one shows a blurred image of the author's avatar. The
  idea to borrow: build the image from something the work already has.
- **FicTracker** (a browser script) colours works by reading status: finished ones are dimmed and favourites
  are highlighted. Colour shows your history with a work.
- **AO3's four-tag square is effectively AO3's cover.** Fans read it at a glance.

What only Kudos has, and can use for depth: the fandom's colour, the passage where you stopped, how far you are
into each work and how long it is, and your history with it.

Sources: [FanFicFare](https://github.com/JimmXinu/FanFicFare) ·
[FicLab](https://addons.mozilla.org/addon/ficlab/) ·
[FicTracker](https://greasyfork.org/ja/scripts/513435-ao3-fictracker) ·
[Wattpad covers](https://goodereader.com/blog/?p=86492) ·
[Fanficly](https://apps.apple.com/app/id6775897153) ·
[AO3 App Wars (Fanlore)](https://fanlore.org/wiki/AO3_App_Wars)

## 5. Budget

Credits are limited (about $99). Keep working one board at a time. I'll pick a direction before you go back to
the Duo boards.
