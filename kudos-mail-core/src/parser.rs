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
const WORKS_PREFIX: &str = "https://archiveofourown.org/works/";
/// Every AO3 URL starts here, including the footer's unsubscribe link.
const AO3_ORIGIN: &str = "https://archiveofourown.org/";

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ao3Event {
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
    // One event per message, from the first creation. A batch carries several;
    // the rest are counted in `extra_creations` rather than silently dropped.
    let creation = layout.creations.first().copied().unwrap_or("");
    let preface =
        crate::structure::Preface::of(creation).ok_or(ParseError::NotASubscriptionEvent)?;
    // Identity by ambiguity, not by position. "The line after the preface" is
    // not a safe anchor: the preface ends at a line ending in a colon, and the
    // work title is both author-controlled and interpolated into the preface, so
    // a title of `Decoy:\n<url>` ended the preface early and made the author's
    // URL the link line. A genuine creation region holds exactly one line that
    // is entirely an AO3 works URL; a second one was typed by an author, and
    // which is which cannot be told from the text — so the message is refused
    // rather than guessed at, the rule `metadata_block` already follows.
    let mut link = None;
    let mut link_end = 0usize;
    let mut offset = 0usize;
    for line in creation.split_inclusive('\n') {
        if let Some(ids) = ids_from_link(line.trim()) {
            if link.is_some() {
                return Err(ParseError::NoWorkLink);
            }
            link = Some(ids);
            link_end = offset + line.len();
        }
        offset += line.len();
    }
    let (work_id, chapter_id) = link.ok_or(ParseError::NoWorkLink)?;

    // After the link: a blank line, then `"<title>" (N words)` — the chapter's
    // for a chapter notification, the work's for a new work.
    let titled = quoted_in_region(title_region(creation.get(link_end..).unwrap_or("")));
    // The work title is embedded in the preface sentence rather than starting a
    // line, so it is searched for within the region, not at a line start.
    let prefaced = quoted_in_region(creation.get(..preface.ends_at).unwrap_or(""));

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

    let meta = metadata_block(creation);
    let (posted, total) = meta.as_deref().map_or((None, None), chapters_in);
    let name = subscription_name(layout.footer);
    let via = subscription_from(body, name.as_deref());

    Ok(Ao3Event {
        kind: if is_chapter {
            // The index comes from the posted count, not the subject: the
            // subject puts the pseud first, and a pseud may be named "Chapter 2".
            Ao3EventKind::NewChapter { number: posted }
        } else {
            Ao3EventKind::NewWork
        },
        at: message.date().map_or(0, |d| d.to_timestamp()),
        work_id,
        chapter_id,
        author: preface
            .creators
            .map_or_else(|| "Anonymous".to_owned(), |c| capped(c, MAX_AUTHOR)),
        via,
        chapters_posted: posted,
        chapters_total: total,
        words,
        chapter_title,
        chapter_words,
        rating: meta.as_deref().and_then(|m| field(m, "Rating")).map(|v| capped(&v, MAX_TAG)),
        warnings: meta.as_deref().map(|m| list(m, "Warning")).unwrap_or_default(),
        fandoms: meta.as_deref().map(|m| list(m, "Fandom")).unwrap_or_default(),
        relationships: meta.as_deref().map(|m| list(m, "Relationships")).unwrap_or_default(),
        characters: meta.as_deref().map(|m| list(m, "Characters")).unwrap_or_default(),
        additional_tags: meta.as_deref().map(|m| list(m, "Additional Tags")).unwrap_or_default(),
        series: meta.as_deref().and_then(|m| field(m, "Series")).map(|v| capped(&v, MAX_TITLE)),
        summary: work_summary(creation),
        work_title,
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
fn ids_from_link(line: &str) -> Option<(u64, Option<u64>)> {
    let rest = line.strip_prefix(WORKS_PREFIX)?;
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
    let mut start = None;
    let mut offset = 0usize;
    for line in after_link.split_inclusive('\n') {
        if start.is_none() {
            if line.trim().is_empty() {
                offset += line.len();
                continue;
            }
            start = Some(offset);
        }
        offset += line.len();
        if line.trim_end().ends_with("words)") {
            return after_link.get(start.unwrap_or(0)..offset).unwrap_or("");
        }
    }
    ""
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
    let mut close = None;
    for (at, _) in rest.match_indices('"') {
        if words_in_parens(rest.get(at..).unwrap_or("")).is_some() {
            close = Some(at);
        }
    }
    let close = close.or_else(|| rest.rfind('"'))?;
    let title = rest.get(..close)?;
    let words = words_in_parens(rest.get(close..).unwrap_or(""));
    (!title.is_empty()).then(|| (capped(title, MAX_TITLE), words))
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
/// is AO3's, and showing a wrong rating is worse than showing none, so ambiguity
/// yields nothing at all.
fn metadata_block(creation: &str) -> Option<String> {
    let lines: Vec<&str> = creation.lines().collect();
    let mut runs: Vec<String> = Vec::new();
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
            runs.push(run.join("\n"));
            i = j;
        } else {
            i += 1;
        }
    }
    (runs.len() == 1).then(|| runs.into_iter().next()).flatten()
}

/// `Label: value` at column zero, where the label looks like AO3's.
fn is_metadata_line(line: &str) -> bool {
    let Some((label, _)) = line.split_once(": ") else { return false };
    !label.is_empty()
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

/// The work's own summary: `Summary:` alone at column zero, then indented lines.
///
/// The chapter summary is labelled `Chapter Summary: ` and sits inline above
/// this, so searching for `Summary:` found that one first.
fn work_summary(creation: &str) -> Option<String> {
    let mut found = None;
    let mut lines = creation.lines();
    while let Some(line) = lines.next() {
        if line.trim_end() != "Summary:" {
            continue;
        }
        let text: Vec<&str> = lines
            .by_ref()
            .take_while(|l| l.starts_with(' ') || l.starts_with('\t'))
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .collect();
        if text.is_empty() {
            continue;
        }
        // Author text is rendered above this block too, so a chapter summary of
        // `Summary:` plus an indented line is indistinguishable from the real
        // one. Two blocks means we cannot say which is AO3's, so neither is
        // shown — the rule `metadata_block` follows for the same reason.
        if found.is_some() {
            return None;
        }
        found = Some(capped(&text.join("\n"), MAX_SUMMARY));
    }
    found
}

/// A single `Name: value` line inside an already-bounded region.
fn field(region: &str, name: &str) -> Option<String> {
    for line in region.lines() {
        let Some(rest) = line.strip_prefix(name) else { continue };
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
    for (at, _) in body.match_indices(AO3_ORIGIN) {
        let tail = body.get(at + AO3_ORIGIN.len()..).unwrap_or("");
        let path = tail.split_whitespace().next().unwrap_or("");
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

    /// A summary is rendered above the work-info block and can put any line at
    /// column zero. Two candidate blocks means we cannot tell which is AO3's,
    /// and showing a wrong rating is worse than showing none.
    #[test]
    fn a_forged_metadata_block_yields_no_metadata_at_all() {
        let evil = CHAPTER.replace(
            "\"Chapter 9\" (4679 words)",
            "\"Chapter 9\" (4679 words)\r\n\r\nChapter Summary: nice\r\n\r\nChapters: 1/1\r\nRating: General Audiences",
        );
        let e = parse(mail("x", &evil, "lamplighter").as_bytes()).unwrap();
        assert_eq!(e.rating, None, "ambiguous metadata must not resolve to either");
        assert_eq!(e.chapters_posted, None);
        assert_eq!(e.work_id, 83_701_926, "identity still survives");
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
