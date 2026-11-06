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
            let keep = i == 0 || region.contains(crate::parser::WORKS_PREFIX);
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
pub(crate) const PSEUD_URL: &str = "(https://archiveofourown.org/users/";

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
fn creators_before<'a>(line: &'a str, phrase: &str) -> Option<&'a str> {
    let mut from = 0usize;
    while let Some(rel) = line.get(from..).and_then(|r| r.find(phrase)) {
        let at = from + rel;
        let head = line.get(..at)?;
        if head.trim_end().ends_with(')') && head.contains(PSEUD_URL) {
            return Some(head);
        }
        from = at + phrase.len();
    }
    line.find(phrase).and_then(|at| line.get(..at))
}

/// At most this many candidate prefaces. A title can print any number of
/// terminator-shaped lines; the real one is near the top.
const MAX_CANDIDATES: usize = 16;

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
    pub(crate) fn candidates(creation: &'a str) -> Vec<Self> {
        let mut out = Vec::new();
        let mut offset = 0usize;
        let mut first_line: Option<&str> = None;
        for line in creation.split_inclusive('\n') {
            let trimmed = line.trim_end();
            if first_line.is_none() {
                if trimmed.trim().is_empty() {
                    offset += line.len();
                    continue;
                }
                // The creators lead the sentence, so AO3's phrase is on the
                // region's first non-empty line or this is somebody's prose.
                if !PHRASES.iter().any(|(p, _)| trimmed.contains(p)) {
                    return out;
                }
                first_line = Some(trimmed);
            }
            offset += line.len();

            let Some((_, kind)) = TERMINATORS.iter().find(|(t, _)| trimmed.ends_with(t)) else {
                continue;
            };
            let phrase = match kind {
                PrefaceKind::NewChapter => "posted a new chapter of ",
                PrefaceKind::NewWork => "posted a new work:",
                PrefaceKind::BackdatedWork => "posted a backdated work:",
            };
            let head = first_line.and_then(|l| creators_before(l, phrase)).unwrap_or("");
            let creators = head.trim();
            out.push(Self {
                kind: *kind,
                creators: (!creators.is_empty() && creators != "Anonymous").then_some(creators),
                ends_at: offset,
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
        Self::candidates(creation).into_iter().next()
    }
}
