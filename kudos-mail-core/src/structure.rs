//! Locating the parts of AO3's notification, from its template rather than by
//! searching the body for phrases.
//!
//! The template is `app/views/user_mailer/batch_subscription_notification.text.erb`
//! inside the layout `app/views/layouts/mailer.text.erb` (otwarchive master,
//! read 2026-11-05). Its shape, for one creation:
//!
//! ```text
//! Archive of Our Own
//! =========================================
//!
//! <creators> posted a new chapter of "<work title>" (N words):   <- preface, ends in ':'
//! https://archiveofourown.org/works/<id>/chapters/<id>            <- the only trusted link
//!
//! "<chapter title>" (M words)
//! by <creators>                                                   <- only if pseuds differ
//!
//! Chapter Summary: <author text>                                  <- author-controlled
//!
//! Chapters: 9/13                                                  <- _work_info starts here
//! Fandom: …
//! Rating: …
//! Warning: …
//!
//! Summary:
//!     <author text>                                               <- author-controlled
//!
//! --------------------                                            <- between creations only
//! …
//! -----------------------------------------                       <- layout rule, 41 hyphens
//! You're receiving this email because you've subscribed to <name>. Follow the link…
//! ```
//!
//! Everything an AO3 author can type — titles, summaries, pseuds — lands inside a
//! genuine signed message, so position in this structure is the only thing that
//! separates AO3's words from theirs.

/// A notification split into the regions the template defines.
pub(crate) struct Layout<'a> {
    /// Creations, in order. A batch mail has several; the first is the subject.
    pub creations: Vec<&'a str>,
    /// Everything below the layout's hyphen rule. AO3's words only.
    pub footer: &'a str,
}

/// The layout rule is 41 hyphens; the batch divider is 20. Anything at least
/// this long is treated as the rule.
const RULE_MIN: usize = 30;
/// The batch divider, exactly.
const DIVIDER: usize = 20;

/// Byte offset just past the layout's `=====` rule, if present.
fn equals_rule(body: &str) -> Option<usize> {
    let mut offset = 0usize;
    for line in body.split_inclusive('\n') {
        let t = line.trim();
        if t.len() >= 8 && t.bytes().all(|b| b == b'=') {
            return Some(offset + line.len());
        }
        offset += line.len();
    }
    None
}

fn hyphen_run(line: &str) -> Option<usize> {
    let t = line.trim();
    (!t.is_empty() && t.bytes().all(|b| b == b'-')).then_some(t.len())
}

impl<'a> Layout<'a> {
    pub(crate) fn of(body: &'a str) -> Self {
        // The footer is below the LAST long rule. An author can print hyphens in
        // a summary, but only above AO3's own, so taking the last is safe where
        // taking the first was not.
        let (body, _) = match equals_rule(body) {
            // The layout opens with "Archive of Our Own" over a rule of '='.
            // Everything above it is chrome, and the preface is the first thing
            // after it — so it has to go before any line is read as AO3's.
            Some(end) => (body.get(end..).unwrap_or(""), ()),
            None => (body, ()),
        };

        let mut rule_at = None;
        let mut offset = 0usize;
        for line in body.split_inclusive('\n') {
            if hyphen_run(line).is_some_and(|n| n >= RULE_MIN) {
                rule_at = Some((offset, offset + line.len()));
            }
            offset += line.len();
        }

        let (message, footer) = match rule_at {
            Some((start, end)) => (
                body.get(..start).unwrap_or(""),
                body.get(end..).unwrap_or(""),
            ),
            None => (body, ""),
        };

        // Creations are separated by a line of exactly 20 hyphens — but a work
        // title may contain such a line, and splitting on every one of them let
        // an author cut their own notification in half, so its preface lost the
        // colon that ends it, or invent extra creations. It also dropped the
        // notification of any work whose title or summary legitimately rules off
        // with twenty hyphens. AO3 prints the divider only BETWEEN creations, so
        // a divider is only a divider when a preface follows it.
        let mut creations = Vec::new();
        let mut current_start = 0usize;
        let mut offset = 0usize;
        for line in message.split_inclusive('\n') {
            let next = offset + line.len();
            let divides = hyphen_run(line) == Some(DIVIDER)
                && opens_with_preface(message.get(next..).unwrap_or(""));
            if divides {
                if let Some(piece) = message.get(current_start..offset) {
                    creations.push(piece);
                }
                current_start = next;
            }
            offset = next;
        }
        if let Some(piece) = message.get(current_start..) {
            creations.push(piece);
        }

        // Every creation AO3 prints carries its own work link. A region with
        // none is a fragment, not a creation — which is what a divider and a
        // preface phrase written inside an author's own summary produce. The
        // first region is always kept: it is the one this message is about, and
        // whether it has a link is the parser's question, not the layout's.
        let mut i = 0usize;
        creations.retain(|region| {
            let keep = i == 0
                || region
                    .split_whitespace()
                    .any(|t| crate::parser::ao3_path(t).is_some_and(|p| p.starts_with("works/")));
            i += 1;
            keep
        });
        Self { creations, footer }
    }
}

/// Does this region open with one of AO3's preface phrases?
///
/// Every genuine creation does; a fragment cut out of a work title by a forged
/// divider does not. An author who prints both a divider and a preface phrase
/// can still split their own notification, but only their own: the result is a
/// refusal, never another work's identity.
fn opens_with_preface(region: &str) -> bool {
    region
        .lines()
        .find(|l| !l.trim().is_empty())
        .is_some_and(|l| PHRASES.iter().any(|(phrase, _)| l.contains(phrase)))
}

/// What AO3's preface says happened. These are the only six, from
/// `config/locales/mailers/en.yml` under
/// `batch_subscription_notification.preface`.
#[derive(Clone, Copy)]
pub(crate) struct Preface<'a> {
    pub kind: PrefaceKind,
    /// `%{creators}`, or `None` when the creation is anonymous.
    pub creators: Option<&'a str>,
    /// Byte offset just past the preface, where the URL line begins.
    pub ends_at: usize,
    /// Byte offset just past AO3's phrase, where the work title begins. Needed
    /// because AO3 did not always put the title in quotes.
    pub title_from: usize,
    /// Whether this terminator's closer reads `" (<N> word[s]):` — AO3's
    /// quoted form, used since October 2025.
    pub quoted_closer: bool,
    /// Whether AO3's own creators block precedes this terminator's phrase on
    /// the region's first line — the block ends with the paren closing a pseud
    /// URL, which is how `creators_before` identifies it.
    ///
    /// Not merely "the phrase is on the first line": the first line IS AO3's,
    /// so every candidate in a genuine region inherited that and the test was
    /// nearly vacuous.
    pub anchored: bool,
    /// Whether this terminator is followed by AO3's own layout: its link line,
    /// then the creation title it always prints.
    ///
    /// This replaced a weaker test — "no works URL appears above this
    /// terminator" — which was backwards in effect. A work title may contain a
    /// URL, because titles are NOT run through `to_plain_text`:
    /// `sanitize_value` strips tags and keeps a literal newline, and
    /// `clean_and_validate_title` only trims the ends. So a title's URL made
    /// AO3's own closer look "broken" and demoted it below a forged terminator
    /// placed above that URL.
    pub ao3_shaped: bool,
}

#[derive(PartialEq, Eq, Clone, Copy, Debug)]
pub(crate) enum PrefaceKind {
    NewChapter,
    NewWork,
    BackdatedWork,
}

const PHRASES: [(&str, PrefaceKind); 3] = [
    ("posted a new chapter of ", PrefaceKind::NewChapter),
    ("posted a new work:", PrefaceKind::NewWork),
    ("posted a backdated work:", PrefaceKind::BackdatedWork),
];

/// How AO3 CLOSES a preface, which is the only part of it an author cannot
/// supply the shape of.
///
/// A chapter preface ends `… "<title>" (<N> words):` — AO3 appends the word
/// count itself, so the line ends in `words):` whatever the title says. A work
/// preface has no title at all and ends with its phrase.
///
/// Which terminator closed the preface is also what says *what happened*. The
/// phrase alone cannot say: a work titled `x posted a new work:` put that
/// phrase on a genuine chapter preface line, and reading the kind from it
/// turned a chapter notification into a new-work one, took the author's name
/// from the middle of AO3's own sentence, and reported the chapter's word count
/// as the work's.
/// AO3's word count is pluralised — `mailer.general.creation.word_count` has
/// `one: "%{count} word"` — so a ONE-WORD work's chapter preface ends
/// `(1 word):`. Requiring the plural rejected every such notification outright.
const TERMINATORS: [(&str, PrefaceKind); 4] = [
    ("words):", PrefaceKind::NewChapter),
    ("word):", PrefaceKind::NewChapter),
    ("posted a new work:", PrefaceKind::NewWork),
    ("posted a backdated work:", PrefaceKind::BackdatedWork),
];

/// How AO3 renders each creator: `text_pseud` is `pseud.byline + " (<url>)"`,
/// and `creator_text` joins them with `to_sentence`. Every real message in the
/// corpus opens
/// `skydarius11 (https://archiveofourown.org/users/skydarius11/pseuds/skydarius11) posted a new chapter of …`.
pub(crate) const PSEUD_URLS: [&str; 2] = [
    "(https://archiveofourown.org/users/",
    "(http://archiveofourown.org/users/",
];

/// Byte offset of the first pseud-URL opening paren on this line, either scheme.
pub(crate) fn pseud_url_at(line: &str) -> Option<usize> {
    PSEUD_URLS.iter().filter_map(|u| line.find(u)).min()
}

/// Length of the pseud-URL prefix that starts at `at`.
pub(crate) fn pseud_url_len(line: &str, at: usize) -> usize {
    PSEUD_URLS
        .iter()
        .find(|u| line.get(at..).is_some_and(|r| r.starts_with(*u)))
        .map_or(0, |u| u.len())
}

/// Is this terminator followed by AO3's own layout?
///
/// AO3 emits, invariably:
///
/// ```text
/// <preface, ending in a terminator>
/// <works URL, the whole line>
/// (blank)
/// "<creation title>" (<N> word[s])
/// ```
///
/// `creation_title_with_word_count` is unconditional, so the pair is always
/// there. A URL inside a work title is followed by more of the title instead,
/// which is what separates the two — and the only thing that does, now that a
/// title is known to carry literal newlines.
fn followed_by_ao3_layout(below: &str) -> bool {
    let mut lines = below.lines().filter(|l| !l.trim().is_empty());
    let link = lines.next().unwrap_or("");
    if !crate::parser::ao3_path(link.trim()).is_some_and(|p| p.starts_with("works/")) {
        return false;
    }
    let title = lines.next().unwrap_or("").trim_end();
    // AO3's creation title closes without a colon; a preface terminator has one.
    title.ends_with("words)") || title.ends_with("word)")
}

/// Does AO3's own closer on this line read `" (<N> word[s]):`?
///
/// AO3 began quoting the work title in October 2025; before that the same line
/// reads `Title (<N> words):`. So the quote is how AO3's closer is told apart
/// from a count an author wrote: a chapter summary rendering as `(1 word):` has
/// the count and the colon but no closing quote, and it was being preferred
/// over AO3's own line.
fn closer_is_quoted(line: &str) -> bool {
    let Some(at) = line.rfind('(') else { return false };
    line.get(..at).is_some_and(|head| head.trim_end().ends_with('"'))
}

/// The creators that precede AO3's own `phrase` on this line.
///
/// A pseud cannot contain a terminator — `pseud.rb` allows only `[\p{Word} -]+`
/// — but it CAN contain a phrase, and so can a work title. Taking the last
/// occurrence read the author out of the middle of AO3's sentence when a title
/// held the phrase; taking the first did the same when a pseud did.
///
/// Neither is needed: AO3's phrase is the first occurrence that follows the
/// creators block, and that block ends with the paren closing a pseud URL. A
/// title's copy sits inside the quotes, after it. Where there is no pseud URL at
/// all the first occurrence is used, which is the best available guess.
fn creators_before<'a>(line: &'a str, phrase: &str) -> Option<(&'a str, bool)> {
    let mut from = 0usize;
    while let Some(rel) = line.get(from..).and_then(|r| r.find(phrase)) {
        let at = from + rel;
        let head = line.get(..at)?;
        if head.trim_end().ends_with(')') && pseud_url_at(head).is_some() {
            return Some((head, true));
        }
        from = at + phrase.len();
    }
    // No creators block before any occurrence. Still usable — anonymous posts
    // have none, and so do abbreviated test fixtures — but not anchored, and a
    // title holding a phrase lands here rather than being taken for AO3's.
    line.find(phrase).and_then(|at| line.get(..at)).map(|head| (head, false))
}

/// At most this many candidate prefaces. AO3 caps a work title at 255
/// characters, so a title can hold roughly twenty terminator-shaped lines; at
/// sixteen the cap returned before AO3's own terminator — the last one — was
/// ever recorded, and a fake closer then supplied the title and word count.
const MAX_CANDIDATES: usize = 256;

impl<'a> Preface<'a> {
    /// Every line that could close this region's preface, outermost first.
    ///
    /// More than one is possible because a title may END a line with one of
    /// AO3's own terminators — `"x posted a new work:` does it — so the first
    /// terminator found is not necessarily AO3's. Taking it flipped a chapter
    /// notification to a new-work one and read the author's name out of the
    /// middle of AO3's sentence. The caller picks the candidate whose kind
    /// agrees with the link line AO3 printed, which an author cannot reshape:
    /// a chapter notification links `/works/N/chapters/M`, a work one `/works/N`.
    /// `bound` is the byte offset where AO3's own layout resumes — its metadata
    /// block, or the first author-text label. Nothing below that is part of a
    /// preface, and this is load-bearing rather than tidy: the work summary is
    /// printed LAST and is author text, so a terminator-shaped line and a URL
    /// inside it became the bottom-most candidate and, being tried first, were
    /// read as AO3's own.
    pub(crate) fn candidates(creation: &'a str, bound: usize) -> Vec<Self> {
        let mut out = Vec::new();
        let mut offset = 0usize;
        let mut first_line: Option<&str> = None;
        let mut first_start = 0usize;
        for line in creation.split_inclusive('\n') {
            let trimmed = line.trim_end();
            if first_line.is_none() {
                if trimmed.trim().is_empty() {
                    offset += line.len();
                    continue;
                }
                first_start = offset;
                // The creators lead the sentence, so AO3's phrase is on the
                // region's first non-empty line or this is somebody's prose.
                if !PHRASES.iter().any(|(p, _)| trimmed.contains(p)) {
                    return out;
                }
                first_line = Some(trimmed);
            }
            offset += line.len();
            if offset > bound {
                return out;
            }

            let Some((_, kind)) = TERMINATORS.iter().find(|(t, _)| trimmed.ends_with(t)) else {
                continue;
            };
            let phrase = match kind {
                PrefaceKind::NewChapter => "posted a new chapter of ",
                PrefaceKind::NewWork => "posted a new work:",
                PrefaceKind::BackdatedWork => "posted a backdated work:",
            };
            // AO3 prints ONE preface sentence and its phrase is on the region's
            // first line, so a terminator whose kind's phrase is missing there
            // is probably not AO3's — a chapter summary rendering as
            // `posted a new work:` turned a chapter notification into a new work
            // by Anonymous, the creators having been looked for on a line that
            // never held them. Ranked rather than discarded: a forged divider
            // can split AO3's own sentence, leaving the real terminator in a
            // region whose first line belongs to the author, and discarding it
            // refused a message that was still recoverable.
            let found = first_line.and_then(|l| creators_before(l, phrase));
            let (head, anchored) = found.unwrap_or(("", false));
            let creators = head.trim();
            // AO3 opens the quoted form immediately after its phrase. A closing
            // quote alone cannot identify the era: an older unquoted title that
            // merely ENDS in a quote was read as quoted-era mail.
            let opens_quoted = first_line
                .and_then(|l| l.get(head.len() + phrase.len()..))
                .is_some_and(|rest| rest.starts_with('"'));
            out.push(Self {
                kind: *kind,
                creators: (!creators.is_empty() && creators != "Anonymous").then_some(creators),
                ends_at: offset,
                title_from: first_start + head.len() + phrase.len(),
                quoted_closer: *kind == PrefaceKind::NewChapter
                    && opens_quoted
                    && closer_is_quoted(trimmed),
                anchored,
                ao3_shaped: followed_by_ao3_layout(creation.get(offset..).unwrap_or("")),
            });
            if out.len() >= MAX_CANDIDATES {
                return out;
            }
        }
        out
    }

    /// The outermost candidate. Enough to answer "is this a subscription
    /// notification at all"; identity needs [`Self::candidates`].
    pub(crate) fn of(creation: &'a str) -> Option<Self> {
        Self::candidates(creation, creation.len()).into_iter().next()
    }
}
