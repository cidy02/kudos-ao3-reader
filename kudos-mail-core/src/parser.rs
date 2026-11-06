//! Turns one AO3 notification into an [`Ao3Event`], or refuses.
//!
//! Everything here treats the message as hostile. The gate ([`crate::gate`])
//! establishes that AO3 sent it, but a gate can be wrong, and the watched-folder
//! tier has no provider attestation at all — so nothing below trusts the content.
//!
//! Shapes, measured across 273 real notifications (2026-11-05):
//!
//! | kind | count |
//! |---|---|
//! | new chapter, via a work subscription | 213 |
//! | new chapter, via an author subscription | 31 |
//! | new work, via an author subscription | 14 |
//!
//! **Fields are not uniform and none may be assumed.** `Chapters:`, `Rating:`
//! and `Summary:` appeared on every one; `Warning:` on 154/213, `Relationships:`
//! on 180/213, `Additional Tags:` on 108/213, and `Fandom:` on all work-sub
//! chapter mail but only 8 of 14 new-work mails. A parser that requires any of
//! them fails on real mail, so every one of them is an `Option` or a `Vec`.

use mail_parser::Message;
#[cfg(test)]
use mail_parser::MessageParser;

/// Links we will read ids out of. Anything else is not AO3's and is ignored.
/// AO3's own origin, in both schemes it has used.
///
/// Mail from December 2024 in the corpus writes `http://archiveofourown.org/…`;
/// today's writes `https://`. Requiring the current one failed every older
/// message outright — and importing a mailbox's backlog is the whole feature,
/// so the history is not an edge case. Only parsed, never generated.
const AO3_ORIGINS: [&str; 2] =
    ["https://archiveofourown.org/", "http://archiveofourown.org/"];

/// The path after AO3's origin, whichever scheme was used.
pub(crate) fn ao3_path(url: &str) -> Option<&str> {
    AO3_ORIGINS.iter().find_map(|origin| url.strip_prefix(origin))
}

// Caps. Mail is attacker-controlled, so every string that reaches a UI is
// bounded here rather than wherever it is eventually drawn.
const MAX_TITLE: usize = 512;
const MAX_AUTHOR: usize = 128;
const MAX_SUMMARY: usize = 4_096;
const MAX_TAG: usize = 256;
const MAX_TAGS: usize = 64;
/// AO3 itself will not exceed this; a larger number means a forged message.
const MAX_CHAPTERS: u32 = 100_000;
const MAX_WORDS: u64 = 100_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ao3EventKind {
    /// The preface could not be told from an author's imitation of one, so
    /// what happened is not reported. The work id still is: AO3's unsubscribe
    /// URL fixes it. See [`Identity`].
    Contested,
    NewChapter { number: Option<u32> },
    NewWork,
}

/// Which relationship produced this message, from the unsubscribe URL in AO3's
/// footer.
///
/// `id` / `username` are AO3's: Rails builds that URL from the subscription's
/// own record. `name` is `Subscription#name`, which for a work subscription is
/// the work's title — text its author typed. Display the name; identify by the
/// id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Subscription {
    Work { id: u64, name: Option<String> },
    Series { id: u64, name: Option<String> },
    /// The login name, which AO3 restricts to letters, digits and underscores.
    Author { username: String, name: Option<String> },
    Unknown,
}

/// How far this event's identity could be established, which is not the same
/// question as whether the message was genuine — see [`crate::Verdict`] for
/// that. A correctly signed AO3 notification still carries author-written text
/// in the places the layout is read from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Identity {
    /// The work id is AO3's. The footer named a work through
    /// `polymorphic_url`, and only a link to that work was read, so no title
    /// can substitute a different work. The chapter id and the metadata were
    /// still read from the body: an author can split their own notification
    /// with a divider inside a title and present a complete-looking fragment,
    /// which moves the chapter and the metadata within that one work.
    Work,
    /// Everything was read from the body, including which work it is. An author
    /// subscription names a user and a series subscription names a series, so
    /// neither pins the work — and any author whose creation appears in the
    /// message can craft a title that makes their fragment look like AO3's
    /// layout. Treat the identity as a hint: confirm against AO3 before
    /// presenting it as fact or acting on it.
    Body,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ao3Event {
    /// How far the identity below could be established.
    pub identity: Identity,
    pub kind: Ao3EventKind,
    /// Unix seconds, from the `Date` header.
    ///
    /// **Not authenticated, even when the verdict is `Trusted`.** DKIM must sign
    /// `From`, but signing `Date` is only recommended, so a replayed message can
    /// carry a passing AO3 signature and an attacker's timestamp. Treat this as
    /// ordering information to show, never as something to make a decision on.
    pub at: i64,
    pub work_id: u64,
    pub chapter_id: Option<u64>,
    pub work_title: String,
    pub author: String,
    pub via: Subscription,
    pub chapters_posted: Option<u32>,
    /// `None` where AO3 printed `?` — the author has not said how many there are.
    pub chapters_total: Option<u32>,
    pub words: Option<u64>,
    pub chapter_title: Option<String>,
    pub chapter_words: Option<u64>,
    pub rating: Option<String>,
    pub warnings: Vec<String>,
    pub fandoms: Vec<String>,
    pub relationships: Vec<String>,
    pub characters: Vec<String>,
    pub additional_tags: Vec<String>,
    pub series: Option<String>,
    pub summary: Option<String>,
    /// Creations in the same batch mail beyond the one this event describes.
    /// They are not parsed; the count is here so a caller never believes a
    /// message held one update when it held several.
    pub extra_creations: usize,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum ParseError {
    #[error("the message could not be parsed as mail")]
    NotMail,
    #[error("no text/plain part")]
    NoTextBody,
    #[error("no AO3 work link")]
    NoWorkLink,
    #[error("not a subscription notification")]
    NotASubscriptionEvent,
    #[error("message is larger than we will decode")]
    TooLarge,
}

/// Largest message we will decode. AO3's notifications run to a few tens of
/// kilobytes; anything far larger is not one, and quoted-printable or base64
/// can expand well beyond its encoded size, so the cap is applied before the
/// MIME parser is handed the bytes.
pub const MAX_MESSAGE_BYTES: usize = 1024 * 1024;

/// Parse raw bytes directly, skipping the gate. Tests only — production code
/// goes through [`crate::read`], which cannot skip it.
#[cfg(test)]
pub(crate) fn parse(raw: &[u8]) -> Result<Ao3Event, ParseError> {
    if raw.len() > MAX_MESSAGE_BYTES {
        return Err(ParseError::TooLarge);
    }
    let message = MessageParser::default().parse(raw).ok_or(ParseError::NotMail)?;
    parse_message(&message)
}

pub(crate) fn parse_message(message: &Message<'_>) -> Result<Ao3Event, ParseError> {
    // A real text/plain part, not whatever `body_text` can produce: that helper
    // converts an HTML part when no plain alternative exists.
    let body = plain_text_part(message).ok_or(ParseError::NoTextBody)?;
    let body = body.as_ref();

    let layout = crate::structure::Layout::of(body);
    let name = subscription_name(layout.footer);
    let via = subscription_from(body, name.as_deref());

    // Is this a subscription notification at all? AO3's kudos, comment replies
    // and abuse reports share the sender and reach here, and they have no
    // preface. Asked before the link, so they are reported as what they are
    // rather than as a notification with a missing link.
    // ANY region, not the first. A divider inside a title splits the region
    // before AO3's terminator, leaving a first region with the phrase but no
    // terminator — and refusing there dropped every later creation with it, so
    // one author could suppress a whole batch.
    if !layout
        .creations
        .iter()
        .any(|c| crate::structure::Preface::of(c).is_some())
    {
        return Err(ParseError::NotASubscriptionEvent);
    }

    // Which creation this message is about, and where its link is.
    //
    // When the footer says the subscription is to a WORK, that work's id came
    // from AO3's own unsubscribe URL and the notification is necessarily about
    // it — so it names the right link line directly, wherever a title put other
    // URLs. That anchor does not exist for an author or series subscription,
    // which falls back to reading the line after the preface.
    // A work subscription names its work in the footer, and AO3 generated that
    // id, so only a link to that work may be read. Anything else means the
    // message contradicts its own footer.
    let want = match via {
        Subscription::Work { id, .. } => Some(id),
        _ => None,
    };
    let (subject, contested) = choose_subject(&layout, want).ok_or(ParseError::NoWorkLink)?;
    // Contested with no footer anchor leaves nothing trustworthy to report at
    // all: which work it is was only ever going to come from the preface.
    if contested && want.is_none() {
        return Err(ParseError::NoWorkLink);
    }
    let Subject { creation, preface, work_id, chapter_id, link_end } = subject;
    // A contested preface yields nothing preface-derived. The work id stands,
    // because AO3's own unsubscribe URL fixed it; everything else here was read
    // from lines an author can reproduce, so none of it is reported.
    let chapter_id = if contested { None } else { chapter_id };

    let found = metadata_block(creation);
    let meta = found.as_ref().map(|(m, _, _)| m.clone());
    let meta_end = found.as_ref().map_or(0, |(_, _, end)| *end);
    // The title sits between the link and AO3's metadata block, so that block
    // is what bounds it — not the first structural-looking line, which an
    // author can write inside a title.
    let title_bound = found
        .as_ref()
        .map_or(creation.len(), |(_, start, _)| line_offset(creation, *start));

    // After the link: a blank line, then `"<title>" (N words)` — the chapter's
    // for a chapter notification, the work's for a new work.
    let titled = quoted_in_region(title_region(
        creation.get(link_end..title_bound.max(link_end)).unwrap_or(""),
    ));
    // The work title is embedded in the preface sentence rather than starting a
    // line, so it is searched for within the region, not at a line start.
    // Which reader to try first is AO3's own closer, not a guess: an unquoted
    // title may still contain a quote of its own, and the quoted reader then
    // returned a fragment of it with the author's word count.
    let preface_region = creation.get(..preface.ends_at).unwrap_or("");
    let title_region_unquoted = creation.get(preface.title_from..preface.ends_at);
    let prefaced = if preface.quoted_closer {
        quoted_in_region(preface_region).or_else(|| unquoted_title(title_region_unquoted))
    } else {
        unquoted_title(title_region_unquoted).or_else(|| quoted_in_region(preface_region))
    };

    use crate::structure::PrefaceKind as P;
    let is_chapter = preface.kind == P::NewChapter;
    // For a chapter the preface carries the work's title and word count, and the
    // line after the link is the chapter's. For a work there is no title in the
    // preface at all — that shape differs, and assuming otherwise lost it.
    let (work_title, words) = if is_chapter { prefaced } else { titled.clone() }
        .unwrap_or_default();
    let (chapter_title, chapter_words) = if is_chapter {
        titled.map_or((None, None), |(t, w)| (Some(t), w))
    } else {
        (None, None)
    };

    // Read from the whole creation: the block is identified by carrying a
    // fandom, not by sitting above a cut an author can move.
    let once = |stem: &str| (label_count(creation, stem) == 1).then_some(());
    let (posted, total) = match once("Chapters") {
        Some(()) => meta.as_deref().map_or((None, None), chapters_in),
        None => (None, None),
    };

    Ok(Ao3Event {
        identity: if want.is_some() { Identity::Work } else { Identity::Body },
        kind: if contested {
            Ao3EventKind::Contested
        } else if is_chapter {
            // The index comes from the posted count, not the subject: the
            // subject puts the pseud first, and a pseud may be named "Chapter 2".
            Ao3EventKind::NewChapter { number: posted }
        } else {
            Ao3EventKind::NewWork
        },
        at: message.date().map_or(0, |d| d.to_timestamp()),
        work_id,
        chapter_id,
        author: if contested {
            String::new()
        } else {
            preface.creators.map_or_else(
                || "Anonymous".to_owned(),
                |c| capped(&without_pseud_urls(c), MAX_AUTHOR),
            )
        },
        via,
        chapters_posted: posted,
        chapters_total: total,
        words: if contested { None } else { words },
        chapter_title: if contested { None } else { chapter_title },
        chapter_words: if contested { None } else { chapter_words },
        // Each field is read only when its label occurs ONCE in the creation.
        // A second occurrence is author text out of a multiline tag value, and
        // since `Fandom:` precedes `Rating:` a multiline fandom could inject a
        // rating that `field` read first.
        rating: once("Rating")
            .and_then(|()| meta.as_deref().and_then(|m| field(m, "Rating")))
            .map(|v| capped(&v, MAX_TAG)),
        warnings: once("Warning")
            .and_then(|()| meta.as_deref().map(|m| list(m, "Warning")))
            .unwrap_or_default(),
        fandoms: once("Fandom")
            .and_then(|()| meta.as_deref().map(|m| list(m, "Fandom")))
            .unwrap_or_default(),
        relationships: once("Relationship")
            .and_then(|()| meta.as_deref().map(|m| list(m, "Relationship")))
            .unwrap_or_default(),
        characters: once("Character")
            .and_then(|()| meta.as_deref().map(|m| list(m, "Character")))
            .unwrap_or_default(),
        additional_tags: once("Additional Tag")
            .and_then(|()| meta.as_deref().map(|m| list(m, "Additional Tag")))
            .unwrap_or_default(),
        series: once("Series")
            .and_then(|()| meta.as_deref().and_then(|m| field(m, "Series")))
            .map(|v| capped(&v, MAX_TITLE)),
        // Only with an identified block: `meta_end` of zero is not a fallback
        // anchor, it reopens every `Summary:` an author wrote above AO3's own.
        //
        // One limit stands, deliberately unfixed. `Series:` is the last field
        // of `_work_info` and its value is author text that `to_plain_text` can
        // spread over flush-left lines, so a series title holding a blank line
        // and a `Summary:` label is indistinguishable from AO3's own summary
        // label — the rendering is identical, down to the four-space indent.
        // Refusing to read a summary whenever a series is present was tried and
        // costs every work in a series its summary, which is a common shape. The
        // text at stake is the author's own, in their own work's summary slot,
        // so the exchange is not worth it. No corpus message carries a series,
        // so there is nothing yet to measure the real shape against.
        summary: once("Summary")
            .and(meta.as_ref())
            .and_then(|_| work_summary(creation, meta_end)),
        work_title: if contested { String::new() } else { work_title },
        extra_creations: layout.creations.len().saturating_sub(1),
    })
}

/// The first part whose declared type really is `text/plain`.
fn plain_text_part<'a>(message: &'a Message<'a>) -> Option<std::borrow::Cow<'a, str>> {
    for part in message.text_bodies() {
        if let mail_parser::PartType::Text(text) = &part.body {
            return Some(text.clone());
        }
    }
    None
}

/// Digits at the start of `s`, refusing anything that cannot be a u64. The take
/// is bounded before collecting, so a megabyte of digits costs a comparison.
fn leading_u64(s: &str) -> Option<u64> {
    const MAX_DIGITS: usize = 19;
    let digits: String =
        s.chars().take_while(char::is_ascii_digit).take(MAX_DIGITS + 1).collect();
    if digits.is_empty() || digits.len() > MAX_DIGITS {
        return None;
    }
    digits.parse().ok()
}

/// Ids from a line that is *nothing but* an AO3 work link.
///
/// A line that merely contains one is a line somebody wrote.
/// Which creation a message is about, and where AO3 printed its link.
struct Subject<'a> {
    creation: &'a str,
    /// The candidate whose kind agrees with the link below it.
    preface: crate::structure::Preface<'a>,
    work_id: u64,
    chapter_id: Option<u64>,
    /// Byte offset just past the link line, where the title follows.
    link_end: usize,
}

/// Does this preface agree with the link AO3 printed? A chapter notification
/// links `/works/N/chapters/M`, a work one `/works/N`. AO3 generates both, so
/// the shape is the one half of the pairing an author cannot restate.
fn agrees(kind: crate::structure::PrefaceKind, chapter_id: Option<u64>) -> bool {
    (kind == crate::structure::PrefaceKind::NewChapter) == chapter_id.is_some()
}

/// The best (preface, link) pair inside one creation, or `None` when the region
/// has none or cannot be read.
///
/// `want` is the work id from AO3's footer, when the subscription names one.
///
/// Candidates are tried from the BOTTOM up, because AO3's terminator is the
/// last one in a preface: the title is interpolated inside AO3's sentence, so
/// every closer an author writes comes before AO3's own. Taking the first let a
/// title of `"Fake" (1 words):` end the preface early, which handed the line
/// below — also the author's — to the link scan, and truncated the work's title
/// and word count to the author's values.
///
/// Two links under one candidate means the region cannot be read, so it is
/// skipped. It is not fatal to the message: one author's crafted title used to
/// refuse a whole series batch and drop every other author's work with it.
fn subject_in<'a>(creation: &'a str, want: Option<u64>) -> Option<(Subject<'a>, bool)> {
    let candidates = crate::structure::Preface::candidates(creation, preface_bound(creation));
    // Four tiers, each bottom-up. The chapter title and the chapter summary are
    // author text AO3 prints between the link and the metadata, and a work
    // TITLE can hold whole lines of its own — titles are not run through
    // `to_plain_text`, so a literal newline survives. Two facts about AO3's
    // sentence separate its terminator from an author's:
    //
    //   `ao3_shaped` — this terminator is followed by AO3's own layout: its
    //                  link line, then the creation title it always prints. A
    //                  URL inside a title is followed by more of the title.
    //   `anchored`   — AO3's creators block, ending in the paren closing a
    //                  pseud URL, precedes this terminator's phrase.
    //
    //   0: AO3's layout below it and AO3's quoted closer
    //   1: AO3's layout below it
    //   2: anchored only
    //   3: neither, which is what a forged divider leaves when it splits AO3's
    //      own sentence across regions
    //
    // The previous test asked whether any works URL appeared ABOVE the
    // terminator, which was backwards: a title's URL demoted AO3's own closer
    // and promoted a forged one placed before that URL.
    let tier = |p: &&crate::structure::Preface<'_>| match (p.ao3_shaped, p.anchored, p.quoted_closer)
    {
        (true, _, true) => 0u8,
        (true, _, false) => 1,
        (false, true, _) => 2,
        (false, false, _) => 3,
    };
    let mut ordered: Vec<&crate::structure::Preface<'_>> = candidates.iter().rev().collect();
    ordered.sort_by_key(tier);
    // The parser no longer CHOOSES between candidates of the same rank.
    //
    // Twelve passes established that it cannot: every discriminator tried —
    // what precedes a terminator, what follows it, whether a link sits on the
    // next line — reads lines an AO3 author also controls. A chapter title is
    // author text and may be multiline, so AO3's own terminator can fail the
    // shape test while a forged one passes it. No textual fact authenticates
    // one author-reproducible rendering over another.
    //
    // So: take the best tier that yields anything, and if a second outcome
    // disagrees about which creation this is, the preface is CONTESTED. The
    // caller then reports what AO3 itself fixed — the work id from the footer's
    // unsubscribe URL — and nothing read out of the preface.
    let mut best: Option<(u8, Subject<'a>)> = None;
    let mut contested = false;
    for preface in ordered {
        // Every candidate is considered, not just the best tier: a forged
        // terminator that outranks AO3's own would otherwise win unopposed,
        // with nothing left to disagree with it. `ordered` is sorted by tier,
        // so the FIRST viable outcome is the best-ranked one; the rest exist
        // only to dispute it.
        let here_tier = tier(&preface);
        let below = creation.get(preface.ends_at..).unwrap_or("");
        let mut offset = 0usize;
        for line in link_region(below).split_inclusive('\n') {
            let here = offset;
            offset += line.len();
            let Some((work_id, chapter_id)) = ids_from_link(line.trim()) else { continue };
            if want.is_some_and(|w| w != work_id) || !agrees(preface.kind, chapter_id) {
                continue;
            }
            let subject = Subject {
                creation,
                preface: *preface,
                work_id,
                chapter_id,
                link_end: preface.ends_at + here + line.len(),
            };
            match &best {
                // Reading the same creation twice is not a disagreement.
                Some((_, other)) => {
                    if (other.work_id, other.chapter_id, other.preface.kind)
                        != (work_id, chapter_id, preface.kind)
                    {
                        contested = true;
                    }
                }
                None => best = Some((here_tier, subject)),
            }
            // One outcome per candidate: AO3 prints its link below its own
            // terminator, so the first usable one there is that candidate's
            // answer. Reading further would let an author add a second link
            // under AO3's OWN terminator — a URL in a chapter title does it —
            // and make the message contest itself.
            break;
        }
    }
    best.map(|(_, subject)| (subject, contested))
}

/// Where AO3's own layout resumes below a preface: its metadata block if that
/// can be identified, else the first author-text label. A preface cannot reach
/// past this, and neither can the link scan.
fn preface_bound(creation: &str) -> usize {
    if let Some((_, start, _)) = metadata_block(creation) {
        return line_offset(creation, start);
    }
    // No block, no bound. A `Summary:` fallback was tried twice and moved
    // twice: a work title can contain that line, and bounding there removed
    // AO3's own terminator and denied the update. The bound is not what keeps a
    // summary's decoy out any more — `ao3_shaped` is, because a terminator
    // inside a summary is not followed by AO3's link-and-title pair.
    creation.len()
}

/// How many lines of the creation carry this label.
///
/// AO3 prints each `_work_info` field once per creation — measured across 258
/// real messages, where `Chapters:`, `Rating:` and `Summary:` each appear
/// exactly once. So a second occurrence is author text out of a multiline tag
/// value, and the field cannot be told from it. `Fandom:` comes BEFORE
/// `Rating:`, and fandom is mandatory, so a multiline fandom could inject a
/// rating that `field` read first — which would defeat rating-based content
/// handling, a worse outcome than showing none.
fn label_count(creation: &str, stem: &str) -> usize {
    creation.lines().filter(|l| has_label(l, stem)).count()
}

/// Whether this region carries what AO3 prints for every creation: the
/// `"<title>" (<N> word[s])` line after the link, which
/// `creation_title_with_word_count` emits unconditionally, and a metadata block.
///
/// A region with neither is a fragment of somebody's title, which is what a
/// forged divider produces. Distinguishing them by whether they carried a
/// fandom was not enough — an author can write a `Fandom:` line of their own,
/// and that moved the chapter id, the index and the rating.
///
/// In a genuine batch the first creation has both; `@seen` suppresses the
/// metadata on a LATER creation of the same work, which is why the real corpus
/// batch still resolves to its first creation.
fn region_is_complete(creation: &str, link_end: usize) -> bool {
    let Some((_, start, _)) = metadata_block(creation) else { return false };
    let bound = line_offset(creation, start);
    bound > link_end
        && quoted_in_region(title_region(creation.get(link_end..bound).unwrap_or(""))).is_some()
}

/// Which creation the message is about: the first complete region, else the
/// first readable one.
fn choose_subject<'a>(
    layout: &crate::structure::Layout<'a>,
    want: Option<u64>,
) -> Option<(Subject<'a>, bool)> {
    let mut fallback = None;
    for creation in &layout.creations {
        let Some((subject, contested)) = subject_in(creation, want) else { continue };
        if region_is_complete(subject.creation, subject.link_end) {
            return Some((subject, contested));
        }
        if fallback.is_none() {
            fallback = Some((subject, contested));
        }
    }
    fallback
}

fn ids_from_link(line: &str) -> Option<(u64, Option<u64>)> {
    let rest = ao3_path(line)?.strip_prefix("works/")?;
    let work_id = leading_u64(rest)?;
    let after = rest.trim_start_matches(|c: char| c.is_ascii_digit());
    let chapter_id = after.strip_prefix("/chapters/").and_then(leading_u64);
    let tail = match chapter_id {
        Some(_) => after
            .strip_prefix("/chapters/")
            .map_or("", |t| t.trim_start_matches(|c: char| c.is_ascii_digit())),
        None => after,
    };
    tail.trim().is_empty().then_some((work_id, chapter_id))
}

/// The lines holding a title that AO3 prints on its own, after the link line:
/// from the first non-empty one to the one AO3 closes with `(N words)`.
///
/// A title may contain newlines, so it is not one line — reading only the line
/// after the link lost every multiline title. Bounding the region here stops a
/// quoted summary further down from being read as the title instead.
fn title_region(after_link: &str) -> &str {
    let (mut start, mut end) = (None, None);
    let mut offset = 0usize;
    for line in after_link.split_inclusive('\n') {
        let trimmed = line.trim_end();
        if start.is_none() {
            if trimmed.trim().is_empty() {
                offset += line.len();
                continue;
            }
            start = Some(offset);
        }
        // Only AO3's chapter-summary label, which it prints between the title
        // and the metadata block. A bare `Summary:` here is NOT AO3's — its own
        // comes below the metadata — so stopping at one let an author put
        // `Summary:` in a title and end the region before AO3's real closer,
        // leaving the author's own closer as the last one. The far end of the
        // region is bounded by the caller instead.
        if trimmed.starts_with("Chapter Summary:") {
            break;
        }
        offset += line.len();
        // The LAST closer, not the first: AO3 appends the word count itself, so
        // a title containing `" (1 words)` was otherwise able to end the region
        // early and choose the count reported for the chapter.
        // `word)` as well as `words)`: AO3 pluralises the count, so a
        // one-word creation closes with the singular.
        if trimmed.ends_with("words)") || trimmed.ends_with("word)") {
            end = Some(offset);
        }
    }
    match (start, end) {
        (Some(s), Some(e)) if e > s => after_link.get(s..e).unwrap_or(""),
        _ => "",
    }
}

/// `"Title" (N words)` within a region, across line breaks.
///
/// Anchored on AO3's own closing `" (N words)`, taken as the LAST one in the
/// region, with the title running from the first quote up to it. A title may
/// contain a quote as well as a newline, so stopping at the first closing quote
/// let its author end the title early and choose the word count reported for
/// it: `Safe" (1 words) "Rest` was read as `Safe`, 1 word.
fn quoted_in_region(region: &str) -> Option<(String, Option<u64>)> {
    let open = region.find('"')?;
    let rest = region.get(open + 1..)?;
    // One reverse scan, not a `words_in_parens` call per quote: a title holding
    // 60,000 quotes made that quadratic, and the message cap bounds the input
    // rather than the work done on it. AO3's closer is `" (<N> words)`, so find
    // the last `words)` and step back over the count to the quote before it.
    let close = last_closer(rest).or_else(|| rest.rfind('"'))?;
    let title = rest.get(..close)?;
    let words = words_in_parens(rest.get(close..).unwrap_or(""));
    (!title.is_empty()).then(|| (capped(title, MAX_TITLE), words))
}

/// Offset of the quote that opens AO3's last `" (<N> words)` closer.
fn last_closer(rest: &str) -> Option<usize> {
    let mut search = rest;
    loop {
        // Either plural form; AO3 writes `(1 word)` for a one-word creation.
        let at = match (search.rfind("words)"), search.rfind("word)")) {
            (Some(a), Some(b)) => a.max(b),
            (Some(a), None) => a,
            (None, Some(b)) => b,
            (None, None) => return None,
        };
        // Back over ` (<digits> ` to the quote that should precede it.
        let head = search.get(..at)?.trim_end();
        let head = head.trim_end_matches(|c: char| c.is_ascii_digit() || c == ',');
        if let Some(before) = head.strip_suffix('(') {
            let before = before.trim_end();
            if before.ends_with('"') {
                return Some(before.len() - 1);
            }
        }
        search = search.get(..at)?;
    }
}

/// `Title (N words):` — AO3's preface before it began quoting the title.
///
/// Mail up to October 2025 in the corpus reads
/// `… posted a new chapter of Burning Air (63338 words):`, with no quotes at
/// all; from 21 October it reads `… of "Title" (N words):`. The quoted reader
/// found nothing in the older shape, so twelve of thirty real messages arrived
/// with an empty work title — a whole era of a reader's backlog.
///
/// The region starts just past AO3's phrase, so the title is everything before
/// the count AO3 appended. The LAST such count, since a title may contain one.
fn unquoted_title(region: Option<&str>) -> Option<(String, Option<u64>)> {
    let region = region?;
    let mut search = region;
    let (at, words) = loop {
        let at = search.rfind('(')?;
        if let Some(words) = words_in_parens(search.get(at..)?) {
            break (at, words);
        }
        search = search.get(..at)?;
    };
    let title = region.get(..at)?.trim();
    (!title.is_empty()).then(|| (capped(title, MAX_TITLE), Some(words)))
}

/// `… (4,679 words)` → 4679. AO3 may write the count with separators.
fn words_in_parens(tail: &str) -> Option<u64> {
    let at = tail.find('(')?;
    let inner = tail.get(at + 1..)?;
    let digits: String = inner
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == ',')
        .filter(char::is_ascii_digit)
        .take(19)
        .collect();
    if digits.is_empty() {
        return None;
    }
    let rest = inner.trim_start_matches(|c: char| c.is_ascii_digit() || c == ',');
    if !rest.trim_start().starts_with("word") {
        return None;
    }
    digits.parse().ok().filter(|n| *n <= MAX_WORDS)
}

/// The `_work_info` block: a run of `Label: value` lines beginning at `Chapters:`.
///
/// Author text is rendered both above this block (the chapter summary) and below
/// it (the work summary), and `to_plain_text` can put any line at column zero —
/// so a summary can forge a block. When two candidates exist we cannot tell which
/// is AO3's, and position cannot settle it: a run forged in a chapter summary
/// sits ABOVE the real one, while a blank line in the series value — which is
/// what `</p>` becomes — lets a forged run sit BELOW it. Neither "first" nor
/// "last" is right.
///
/// AO3's data model settles it. **Every work must have at least one fandom**,
/// so the real `_work_info` run always carries a `Fandom:` line, and all six
/// real messages do. Exactly one run with a fandom is AO3's; zero or several is
/// ambiguous, and a wrong rating is worse than none.
///
/// Read from otwarchive master (2026-11-05) rather than assumed, because the
/// whole metadata path now rests on it. `_work_info.text.erb:3` prints the
/// fandom with **no** `unless` guard, unlike Relationship, Character, Freeform
/// and Series on lines 6–18. The guard is one level down: `work_tag_metadata`
/// is `return if tags.empty?` (`mailer_helper.rb:179`). So the line is
/// unconditional only because a work cannot have zero fandom tags — "No Fandom"
/// is itself a tag. If that ever changes, metadata goes blank rather than
/// wrong, which is the direction this is built to fail in.
fn metadata_block(creation: &str) -> Option<(String, usize, usize)> {
    let lines: Vec<&str> = creation.lines().collect();
    let mut runs: Vec<(String, usize, usize)> = Vec::new();
    let mut i = 0usize;
    while i < lines.len() {
        if lines.get(i).is_some_and(|l| l.starts_with("Chapters:")) {
            let mut run: Vec<&str> = Vec::new();
            let mut j = i;
            while let Some(l) = lines.get(j) {
                if is_metadata_line(l) {
                    run.push(l);
                    j += 1;
                } else {
                    break;
                }
            }
            // Where this run ends, as a line index, so the summary below it can
            // be found without trusting the first `Summary:` in the region.
            runs.push((run.join("\n"), i, j));
            i = j;
        } else {
            i += 1;
        }
    }
    // The LABEL qualifies the run, not a non-empty value: an empty `Fandom:`
    // on AO3's own run made it not count, which left a forged run as the only
    // qualifying one and handed it the rating and the chapter index.
    runs.retain(|(run, _, _)| run.lines().any(|l| has_label(l, "Fandom")));
    (runs.len() == 1).then(|| runs.pop()).flatten()
}

/// `Label: value` at column zero, where the label looks like AO3's.
fn is_metadata_line(line: &str) -> bool {
    // A label with no value is still one of AO3's lines: a work whose fandom
    // tags render empty prints a bare `Fandom:`, and treating that as the end
    // of the run dropped it out of the block it belongs to — which left a
    // forged block as the only one carrying a fandom.
    let Some((label, rest)) = line.split_once(':') else { return false };
    (rest.is_empty() || rest.starts_with(' '))
        && !label.is_empty()
        && label.len() <= 32
        && label.starts_with(|c: char| c.is_ascii_uppercase())
        && label.chars().all(|c| c.is_ascii_alphabetic() || c == ' ')
}

fn chapters_in(meta: &str) -> (Option<u32>, Option<u32>) {
    let Some(value) = field(meta, "Chapters") else { return (None, None) };
    let Some((posted, total)) = value.split_once('/') else { return (None, None) };
    (
        posted.trim().parse::<u32>().ok().filter(|n| *n <= MAX_CHAPTERS),
        total.trim().parse::<u32>().ok().filter(|n| *n <= MAX_CHAPTERS),
    )
}

/// The work's own summary: everything after `Summary:` to the end of the
/// creation.
///
/// Only the FIRST line of the value is indented. AO3 renders the summary
/// through `to_plain_text`, which turns a paragraph break into a blank line and
/// leaves every later paragraph flush left, so reading indented lines only
/// truncated any multi-paragraph summary at its first paragraph — visible in the
/// real corpus, where one message's summary ends mid-thought before `A familiar
/// voice asks, "What if she does?"`.
///
/// Running to the end of the region is also what makes the rest of this parser
/// safe. The summary is the last thing AO3 prints for a creation, so the
/// author's free text is terminal: nothing after it needs to be read as
/// structure, and the metadata block and link scan stop short of it.
fn work_summary(creation: &str, after_line: usize) -> Option<String> {
    let after = summary_after(creation, after_line)?;
    let text: Vec<&str> = after.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    (!text.is_empty()).then(|| capped(&text.join("\n"), MAX_SUMMARY))
}

/// Everything below the first bare `Summary:` line at or after `after_line`.
///
/// The offset is not decoration. AO3 prints the chapter summary — author text,
/// with `</p>` rendered as a blank line — ABOVE the metadata block, so an
/// author can put a bare `Summary:` line of their own there and the first one
/// in the region is not AO3's. Taking the first cut the region above AO3's real
/// metadata, leaving only the author's forged copy of it to be read. Anchoring
/// below the identified block removes the choice.
fn summary_after(creation: &str, after_line: usize) -> Option<&str> {
    let mut offset = 0usize;
    for (n, line) in creation.split_inclusive('\n').enumerate() {
        if n >= after_line && line.trim_end() == "Summary:" {
            return creation.get(offset + line.len()..);
        }
        offset += line.len();
    }
    None
}

/// Where the first block of multi-line author text starts: the bare `Summary:`
/// line, or `Chapter Summary:`, whichever comes first.
///
/// Both are conditional — AO3 prints the summary `unless work.summary.blank?`,
/// and the chapter summary only when there is one; none of the six real
/// messages has a chapter summary. That matters because a work with no summary
/// has no `Summary:` line at all, so cutting only there left the chapter
/// summary — which AO3 renders ABOVE the metadata block — inside the region the
/// link is read from, where it could present a second AO3 work URL and trip the
/// two-links refusal against a perfectly genuine notification.
///
/// The work link is printed on the line after the preface, above both blocks,
/// so bounding the scan here never loses it.
fn link_region(creation: &str) -> &str {
    let mut offset = 0usize;
    for line in creation.split_inclusive('\n') {
        if line.trim_end() == "Summary:" || line.starts_with("Chapter Summary:") {
            return creation.get(..offset).unwrap_or("");
        }
        offset += line.len();
    }
    creation
}

/// Byte offset of a line, by index. Lines are counted as `str::lines` does.
fn line_offset(text: &str, line: usize) -> usize {
    let mut offset = 0usize;
    for (n, l) in text.split_inclusive('\n').enumerate() {
        if n == line {
            return offset;
        }
        offset += l.len();
    }
    text.len()
}

/// `Name (https://archiveofourown.org/users/x/pseuds/Name)` → `Name`.
///
/// AO3 appends the pseud's own URL to every creator (`text_pseud`), so the
/// author of every real message was being reported with that URL attached.
fn without_pseud_urls(creators: &str) -> String {
    let mut out = String::with_capacity(creators.len());
    let mut rest = creators;
    while let Some(at) = crate::structure::pseud_url_at(rest) {
        out.push_str(rest.get(..at).unwrap_or("").trim_end());
        let skip = at + crate::structure::pseud_url_len(rest, at);
        let after = rest.get(skip..).unwrap_or("");
        rest = after.find(')').and_then(|c| after.get(c + 1..)).unwrap_or("");
    }
    out.push_str(rest);
    out.trim().to_owned()
}

/// True when a line carries this label at all, value or no value.
fn has_label(line: &str, stem: &str) -> bool {
    let Some(rest) = line.strip_prefix(stem) else { return false };
    rest.strip_prefix('s').unwrap_or(rest).starts_with(':')
}

/// A single `Stem: value` or `Stems: value` line inside an already-bounded
/// region.
///
/// AO3's metadata labels are locale strings pluralised on how many tags the
/// field holds, so the same work prints `Fandom:` or `Fandoms:` and
/// `Relationship:` or `Relationships:` depending on its own content. Matching
/// fixed spellings read whichever half of the corpus happened to be looked at —
/// the six real messages all have one fandom and one warning but several
/// characters, which is exactly consistent with pluralisation and so could not
/// refute it. The stem is matched with an optional `s`.
fn field(region: &str, stem: &str) -> Option<String> {
    for line in region.lines() {
        let Some(rest) = line.strip_prefix(stem) else { continue };
        let rest = rest.strip_prefix('s').unwrap_or(rest);
        let Some(value) = rest.strip_prefix(':') else { continue };
        let value = value.trim();
        if !value.is_empty() {
            return Some(value.to_owned());
        }
    }
    None
}

fn list(region: &str, name: &str) -> Vec<String> {
    let Some(value) = field(region, name) else { return Vec::new() };
    value
        .split(',')
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .take(MAX_TAGS)
        .map(|v| capped(v, MAX_TAG))
        .collect()
}

/// `%{subscription_name}` out of AO3's footer sentence. Display text only: see
/// [`Subscription`].
fn subscription_name(footer: &str) -> Option<String> {
    const MARKER: &str = "because you've subscribed to ";
    // The first marker in the footer is AO3's; a copy smuggled into the name it
    // interpolates can only come after it.
    let at = footer.find(MARKER)?;
    let rest = footer.get(at + MARKER.len()..)?;
    let end = rest.find(". Follow the link").unwrap_or(rest.len());
    let name = rest.get(..end)?.trim();
    (!name.is_empty()).then(|| capped(name, MAX_TITLE))
}

/// Which relationship produced this message, read from the unsubscribe URL.
///
/// AO3's footer sentence names the subscription but carries no label saying
/// what kind it is, so the kind used to be guessed by matching that name
/// against the message's own work title and creators. That was forgeable twice
/// over: the name is the work's author-typed title, and it sits below AO3's
/// hyphen rule, so a title containing a rule and a forged sentence chose both
/// the name and the kind. It also could not tell an author named `lamplighter`
/// from a work titled `lamplighter`.
///
/// The URL beside the sentence is built by Rails from the subscribable record
/// (`polymorphic_url`), so its path says which kind it is and its id is AO3's.
/// The last such URL in the body is AO3's: the sentence puts the author's text
/// before it, so anything smuggled in appears above.
fn subscription_from(body: &str, name: Option<&str>) -> Subscription {
    let name = || name.map(|n| capped(n, MAX_TITLE));
    let mut last = Subscription::Unknown;
    // One pass over whitespace-delimited tokens. Scanning from every occurrence
    // of the origin and re-splitting the remaining text was quadratic: a summary
    // of concatenated `https://archiveofourown.org/` strings walked the rest of
    // the message once per copy.
    for token in body.split_whitespace() {
        let Some(path) = ao3_path(token) else { continue };
        let Some((kind, rest)) = path.split_once('/') else { continue };
        let ident = rest.split('/').next().unwrap_or("");
        let found = match kind {
            "works" => ident.parse().ok().map(|id| Subscription::Work { id, name: name() }),
            "series" => ident.parse().ok().map(|id| Subscription::Series { id, name: name() }),
            "users" => is_login(ident).then(|| Subscription::Author {
                username: ident.to_owned(),
                name: name(),
            }),
            _ => None,
        };
        if let Some(found) = found {
            last = found;
        }
    }
    last
}


/// An AO3 login: letters, digits and underscores, nothing else.
fn is_login(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= MAX_AUTHOR
        && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

/// Truncate on a char boundary, never mid-codepoint.
fn capped(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_owned();
    }
    let mut end = max;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    s.get(..end).unwrap_or_default().to_owned()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    /// AO3's real layout, from `batch_subscription_notification.text.erb` inside
    /// `layouts/mailer.text.erb` (otwarchive master, read 2026-11-05). No real
    /// message is committed: notification mail carries a reader's address and
    /// their reading history, and this repository is public.
    fn mail(subject: &str, message: &str, footer_name: &str) -> String {
        format!(
            "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
             To: reader@example.com\r\n\
             Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
             Subject: [AO3] {subject}\r\n\
             Content-Type: text/plain; charset=UTF-8\r\n\
             \r\n\
             Archive of Our Own\r\n\
             =========================================\r\n\r\n\r\n\
             {message}\r\n\r\n\
             -----------------------------------------\r\n\
             You're receiving this email because you've subscribed to {footer_name}. \
             Follow the link to unsubscribe if you no longer wish to receive updates: \
             https://archiveofourown.org/users/lamplighter\r\n\r\n\r\n\
             If you don't understand why you received this email, please contact \
             Support: https://archiveofourown.org/support.\r\n"
        )
    }

    /// Point the fixture's unsubscribe link at a different subscribable, which
    /// is how AO3 says whether the subscription is to a work, series or user.
    fn unsub(mail: String, path: &str) -> String {
        mail.replace(
            "https://archiveofourown.org/users/lamplighter\r\n",
            &format!("https://archiveofourown.org/{path}\r\n"),
        )
    }

    const CHAPTER: &str = "lamplighter posted a new chapter of \"Linger Around the Light\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Example Fandom (TV 2015)\r\n\
Rating: Teen And Up Audiences\r\n\
Warning: No Archive Warnings Apply\r\n\
Relationships: Ada/Maren, Wren/Isolde\r\n\
Characters: Ada, Maren\r\n\
Additional Tags: Slow Burn, Fake Dating\r\n\
\r\n\
Summary:\r\n\
\x20\x20\x20\x20A lighthouse keeper writes letters she never sends.";

    fn chapter_mail() -> String {
        mail("lamplighter posted Chapter 9 of Linger Around the Light", CHAPTER, "lamplighter")
    }

    #[test]
    fn reads_a_chapter_notification() {
        let e = parse(chapter_mail().as_bytes()).unwrap();
        assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
        assert_eq!(e.work_id, 83_701_926);
        assert_eq!(e.chapter_id, Some(255_464_091));
        assert_eq!(e.work_title, "Linger Around the Light");
        assert_eq!(e.author, "lamplighter");
        assert_eq!(
            e.via,
            Subscription::Author {
                username: "lamplighter".into(),
                name: Some("lamplighter".into())
            }
        );
        assert_eq!((e.chapters_posted, e.chapters_total), (Some(9), Some(13)));
        assert_eq!(e.words, Some(34_920));
        assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9"));
        assert_eq!(e.chapter_words, Some(4_679));
        assert_eq!(e.rating.as_deref(), Some("Teen And Up Audiences"));
        assert_eq!(e.warnings, ["No Archive Warnings Apply"]);
        assert_eq!(e.additional_tags, ["Slow Burn", "Fake Dating"]);
        assert!(e.summary.unwrap().starts_with("A lighthouse keeper"));
        assert_eq!(e.extra_creations, 0);
        assert!(e.at > 0);
    }

    /// A new work is laid out differently: the preface carries no title, and the
    /// title with its word count sits on the line AFTER the link.
    #[test]
    fn reads_a_new_work_notification() {
        let body = "lamplighter posted a new work:\r\n\
https://archiveofourown.org/works/555\r\n\
\r\n\
\"Watson Abroad\" (3800 words)\r\n\
by lamplighter\r\n\
\r\n\
Chapters: 1/1\r\n\
Rating: General Audiences\r\n";
        let e = parse(mail("lamplighter posted Watson Abroad", body, "lamplighter").as_bytes()).unwrap();
        assert_eq!(e.kind, Ao3EventKind::NewWork);
        assert_eq!(e.work_id, 555);
        assert_eq!(e.work_title, "Watson Abroad");
        assert_eq!(e.words, Some(3_800));
    }

    /// Both were silently dropped: the anonymous preface has no /users/ URL, and
    /// "backdated" was not one of the phrases looked for.
    #[test]
    fn anonymous_and_backdated_mail_are_not_dropped() {
        let anon = CHAPTER.replace("lamplighter posted", "Anonymous posted");
        let e = parse(mail("Anonymous posted Chapter 9", &anon, "Linger Around the Light").as_bytes()).unwrap();
        assert_eq!(e.author, "Anonymous");
        assert_eq!(e.work_id, 83_701_926);

        let back = "lamplighter posted a backdated work:\r\n\
https://archiveofourown.org/works/777\r\n\r\n\"Old Thing\" (10 words)\r\n\r\nChapters: 1/1\r\n";
        let e = parse(mail("x", back, "lamplighter").as_bytes()).unwrap();
        assert_eq!(e.kind, Ao3EventKind::NewWork);
        assert_eq!(e.work_id, 777);
    }

    /// An AO3 work title may contain a newline, and the title is interpolated
    /// into the preface — so a title can put a whole URL on its own line above
    /// the real link. The preface runs to the line ending in a colon, which is
    /// what keeps that line inside it.
    #[test]
    fn a_newline_in_a_title_cannot_hijack_the_link() {
        let evil = "lamplighter posted a new chapter of \"Legit\r\n\
https://archiveofourown.org/works/111/chapters/222\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\"Chapter 9\" (4679 words)\r\n\r\nChapters: 9/13\r\nRating: Teen And Up Audiences\r\n";
        let e = parse(mail("x", evil, "lamplighter").as_bytes()).unwrap();
        assert_eq!(e.work_id, 83_701_926, "the link line is the one after the preface");
        assert_eq!(e.chapter_id, Some(255_464_091));
    }

    /// A chapter summary is rendered above the work-info block and can put any
    /// line at column zero, so it can present a whole forged block.
    ///
    /// Earlier this recovered AO3's values, because the forged run carried no
    /// fandom and so lost the block election. That is no longer relied on: a
    /// label occurring twice in one creation means two candidates for the same
    /// field, and since `Fandom:` precedes `Rating:` a MULTILINE FANDOM VALUE
    /// can inject a rating into AO3's own run, where no election separates
    /// them. A forged rating would defeat rating-based content handling, so the
    /// field is dropped instead — the same trade this parser makes everywhere:
    /// a wrong value is worse than none. Identity is unaffected.
    #[test]
    fn a_forged_metadata_block_suppresses_the_metadata() {
        let evil = CHAPTER.replace(
            "\"Chapter 9\" (4679 words)",
            "\"Chapter 9\" (4679 words)\r\n\r\nChapter Summary: nice\r\n\r\nChapters: 1/1\r\nRating: General Audiences",
        );
        let e = parse(mail("x", &evil, "lamplighter").as_bytes()).unwrap();
        assert_eq!(e.rating, None, "never the author's");
        assert_eq!((e.chapters_posted, e.chapters_total), (None, None), "never 1/1");
        assert_eq!(e.work_id, 83_701_926, "identity still survives");
        assert_eq!(e.chapter_id, Some(255_464_091));
    }

    /// The footer rule is the layout's long hyphen line; the batch divider is 20.
    /// A summary may print either, so the LAST long rule is the real one.
    #[test]
    fn hyphens_in_a_summary_cannot_move_the_footer() {
        let evil = CHAPTER.replace(
            "    A lighthouse keeper writes letters she never sends.",
            "    ---\r\n    You're receiving this email because you've subscribed to impostor. Follow the link",
        );
        let e = parse(mail("x", &evil, "lamplighter").as_bytes()).unwrap();
        assert!(matches!(e.via, Subscription::Author { .. }));
    }

    /// The subject puts the pseud before the chapter number, and a pseud may be
    /// named "Chapter 2". The count comes from the work-info block instead.
    #[test]
    fn a_pseud_named_like_a_chapter_cannot_set_the_number() {
        let e = parse(
            mail("Chapter 2 (alice) posted Chapter 9 of Linger", CHAPTER, "lamplighter").as_bytes(),
        )
        .unwrap();
        assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    }

    /// The subscription's kind comes from AO3's unsubscribe URL, so no property
    /// of the name decides it. Guessing from the characters read a work titled
    /// "Hello-World" as a username; guessing by matching the name against the
    /// message could not tell an author named `lamplighter` from a work of the
    /// same title. Neither question is asked now.
    #[test]
    fn the_unsubscribe_url_says_which_kind_it_is() {
        let body = CHAPTER.replace("Linger Around the Light", "Hello-World");
        let m = mail("x", &body, "Hello-World");
        assert_eq!(
            parse(unsub(m.clone(), "works/83701926").as_bytes()).unwrap().via,
            Subscription::Work { id: 83_701_926, name: Some("Hello-World".into()) }
        );
        assert_eq!(
            parse(unsub(m.clone(), "series/4021").as_bytes()).unwrap().via,
            Subscription::Series { id: 4021, name: Some("Hello-World".into()) }
        );
        // The name equals a creator's pseud and the kind is still the URL's.
        let m = mail("x", CHAPTER, "lamplighter");
        assert_eq!(
            parse(unsub(m, "works/83701926").as_bytes()).unwrap().via,
            Subscription::Work { id: 83_701_926, name: Some("lamplighter".into()) }
        );
    }

    /// "Chapter Summary: " contains "Summary:", and is rendered first.
    #[test]
    fn the_chapter_summary_is_not_read_as_the_works() {
        let body = CHAPTER.replace(
            "\"Chapter 9\" (4679 words)",
            "\"Chapter 9\" (4679 words)\r\n\r\nChapter Summary: the chapter's own blurb",
        );
        let e = parse(mail("x", &body, "lamplighter").as_bytes()).unwrap();
        assert!(
            e.summary.as_deref().unwrap_or("").starts_with("A lighthouse keeper"),
            "the work summary is the indented one below the block"
        );
    }

    #[test]
    fn the_author_is_the_whole_creators_string() {
        let body = CHAPTER.replace("lamplighter posted", "Jane Doe (jane) posted");
        let e = parse(mail("x", &body, "Jane Doe (jane)").as_bytes()).unwrap();
        assert_eq!(e.author, "Jane Doe (jane)");
    }

    /// A batch message holds several creations. Only the first is parsed, but
    /// the count is reported so a caller never believes there was one update.
    #[test]
    fn a_batch_message_says_how_many_it_held() {
        let two = format!("{CHAPTER}\r\n\r\n--------------------\r\n\r\n{CHAPTER}");
        let e = parse(mail("x", &two, "lamplighter").as_bytes()).unwrap();
        assert_eq!(e.extra_creations, 1);
        assert_eq!(e.work_id, 83_701_926);
    }

    #[test]
    fn an_unknown_chapter_total_is_none_not_zero() {
        let body = CHAPTER.replace("Chapters: 9/13", "Chapters: 55/?");
        let e = parse(mail("x", &body, "lamplighter").as_bytes()).unwrap();
        assert_eq!((e.chapters_posted, e.chapters_total), (Some(55), None));
    }

    /// 28% of real chapter mail has no Warning line, 49% no Additional Tags.
    #[test]
    fn every_optional_field_may_be_absent() {
        let body = CHAPTER
            .replace("Warning: No Archive Warnings Apply\r\n", "")
            .replace("Additional Tags: Slow Burn, Fake Dating\r\n", "")
            .replace("Relationships: Ada/Maren, Wren/Isolde\r\n", "")
            .replace("Fandom: Example Fandom (TV 2015)\r\n", "")
            .replace("Characters: Ada, Maren\r\n", "");
        let e = parse(mail("x", &body, "lamplighter").as_bytes()).unwrap();
        assert!(e.warnings.is_empty() && e.additional_tags.is_empty() && e.fandoms.is_empty());
        assert_eq!(e.work_id, 83_701_926);
    }

    #[test]
    fn a_link_on_another_host_yields_no_ids() {
        let body = CHAPTER.replace("https://archiveofourown.org/works/83701926", "https://evil.test/works/83701926");
        assert_eq!(parse(mail("x", &body, "l").as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn a_lookalike_host_yields_no_ids() {
        let body = CHAPTER.replace("https://archiveofourown.org/works/", "https://archiveofourown.org.evil.test/works/");
        assert_eq!(parse(mail("x", &body, "l").as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn anything_after_the_link_on_its_line_voids_it() {
        let body = CHAPTER.replace(
            "/works/83701926/chapters/255464091",
            "/works/83701926?next=https://evil.test/works/999",
        );
        assert_eq!(parse(mail("x", &body, "l").as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn an_id_too_long_for_u64_is_refused() {
        let body = CHAPTER.replace("/works/83701926", "/works/99999999999999999999999");
        assert_eq!(parse(mail("x", &body, "l").as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn absurd_counts_are_refused_rather_than_shown() {
        let body = CHAPTER.replace("Chapters: 9/13", "Chapters: 999999999/999999999");
        let e = parse(mail("x", &body, "l").as_bytes()).unwrap();
        assert_eq!((e.chapters_posted, e.chapters_total), (None, None));
    }

    #[test]
    fn a_very_long_title_is_capped() {
        let huge = "x".repeat(5_000);
        let body = CHAPTER.replace("Linger Around the Light", &huge);
        let e = parse(mail("x", &body, "l").as_bytes()).unwrap();
        assert_eq!(e.work_title.len(), MAX_TITLE);
    }

    #[test]
    fn a_flood_of_tags_is_bounded() {
        let many = (0..500).map(|i| format!("tag{i}")).collect::<Vec<_>>().join(", ");
        let body = CHAPTER.replace("Slow Burn, Fake Dating", &many);
        let e = parse(mail("x", &body, "l").as_bytes()).unwrap();
        assert_eq!(e.additional_tags.len(), MAX_TAGS);
    }

    #[test]
    fn kudos_and_comment_mail_is_not_a_subscription_event() {
        let body = "lamplighter left kudos on your work!\r\nhttps://archiveofourown.org/works/1\r\n";
        assert_eq!(
            parse(mail("You've got kudos!", body, "l").as_bytes()),
            Err(ParseError::NotASubscriptionEvent)
        );
    }

    #[test]
    fn capping_never_splits_a_character() {
        let s = "\u{1f526}".repeat(400);
        let out = capped(&s, MAX_TAG);
        assert!(out.len() <= MAX_TAG);
        assert!(std::str::from_utf8(out.as_bytes()).is_ok());
    }

    #[test]
    fn an_oversized_message_is_refused_before_decoding() {
        let mut m = chapter_mail().into_bytes();
        m.extend(std::iter::repeat_n(b'x', MAX_MESSAGE_BYTES));
        assert_eq!(parse(&m), Err(ParseError::TooLarge));
    }

    #[test]
    fn garbage_in_does_not_panic() {
        for raw in [
            &b""[..],
            &b"\x00\x01\x02"[..],
            &b"From: \xff\xfe broken"[..],
            "Subject: ".repeat(10_000).as_bytes(),
        ] {
            let _ = parse(raw);
        }
    }
}
