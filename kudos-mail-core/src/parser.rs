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

use mail_parser::{Message, MessageParser};

/// Links we will read ids out of. Anything else is not AO3's and is ignored.
const WORKS_PREFIX: &str = "https://archiveofourown.org/works/";

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

/// Which relationship produced this message, from AO3's own "because you've
/// subscribed to …" line. Not inferred — stated.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Subscription {
    Work(String),
    Author(String),
    Series(String),
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ao3Event {
    pub kind: Ao3EventKind,
    /// Unix seconds, from the `Date` header.
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

/// Parse one message. The caller must have run [`crate::gate::check`] first.
pub fn parse(raw: &[u8]) -> Result<Ao3Event, ParseError> {
    if raw.len() > MAX_MESSAGE_BYTES {
        return Err(ParseError::TooLarge);
    }
    let message = MessageParser::default().parse(raw).ok_or(ParseError::NotMail)?;
    parse_message(&message)
}

pub fn parse_message(message: &Message<'_>) -> Result<Ao3Event, ParseError> {
    // text/plain only. The HTML alternative says the same thing and parsing it
    // would mean running markup from a stranger through another parser.
    let body = message.body_text(0).ok_or(ParseError::NoTextBody)?;
    let body = body.as_ref();

    let kind = if body.contains("posted a new chapter of") {
        Ao3EventKind::NewChapter { number: chapter_number(message.subject().unwrap_or("")) }
    } else if body.contains("posted a new work") {
        Ao3EventKind::NewWork
    } else {
        // Kudos notifications, comment replies and abuse reports all arrive from
        // the same address. They are not subscription events and are dropped.
        return Err(ParseError::NotASubscriptionEvent);
    };

    let (work_id, chapter_id) = work_and_chapter_ids(body).ok_or(ParseError::NoWorkLink)?;

    Ok(Ao3Event {
        kind,
        at: message.date().map_or(0, |d| d.to_timestamp()),
        work_id,
        chapter_id,
        work_title: quoted_after(body, "of \"").unwrap_or_default(),
        author: author(body).unwrap_or_default(),
        via: subscription(body),
        chapters_posted: chapters(body).0,
        chapters_total: chapters(body).1,
        words: parenthesised_words(body),
        chapter_title: chapter_title(body),
        chapter_words: chapter_words(body),
        rating: field(body, "Rating").map(|v| capped(&v, MAX_TAG)),
        warnings: list(body, "Warning"),
        fandoms: list(body, "Fandom"),
        relationships: list(body, "Relationships"),
        characters: list(body, "Characters"),
        additional_tags: list(body, "Additional Tags"),
        series: field(body, "Series").map(|v| capped(&v, MAX_TITLE)),
        summary: summary(body),
    })
}

/// "[AO3] someone posted Chapter 9 of A Work" → 9.
fn chapter_number(subject: &str) -> Option<u32> {
    let at = subject.find("Chapter ")?;
    let rest = subject.get(at + "Chapter ".len()..)?;
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok().filter(|n| *n <= MAX_CHAPTERS)
}

/// The work link, read only from a line that *begins* with it.
///
/// Not the first occurrence anywhere: an AO3 author may put a URL in their work
/// title, and the title is printed above the real link. Searching the whole body
/// let a title like `https://archiveofourown.org/works/111` decide the work id
/// of a genuine, correctly signed message — a confusion attack needing no forged
/// mail at all. AO3's template always puts the link alone on its own line, so
/// that is the only place we read it.
fn work_and_chapter_ids(body: &str) -> Option<(u64, Option<u64>)> {
    let rest = body
        .lines()
        .find_map(|line| line.trim().strip_prefix(WORKS_PREFIX))?;
    let work_id = leading_u64(rest)?;

    let after_id = rest.trim_start_matches(|c: char| c.is_ascii_digit());
    let chapter_id = after_id
        .strip_prefix("/chapters/")
        .and_then(leading_u64);
    Some((work_id, chapter_id))
}

fn leading_u64(s: &str) -> Option<u64> {
    let digits: String = s.chars().take_while(char::is_ascii_digit).collect();
    if digits.is_empty() || digits.len() > 19 {
        return None;
    }
    digits.parse().ok()
}

/// The username AO3 prints before the pseud link on its "posted a new …" line.
///
/// The line must be that one. A `/users/` URL can appear in a summary or a
/// title too, and taking the first line that merely contains one let a work's
/// own text choose the author shown beside it.
fn author(body: &str) -> Option<String> {
    let line = body.lines().find(|l| {
        l.contains("https://archiveofourown.org/users/") && l.contains("posted a new")
    })?;
    let name = line.split_whitespace().next()?;
    (!name.is_empty()).then(|| capped(name, MAX_AUTHOR))
}

/// The work title, which AO3 prints in double quotes after `of `.
///
/// The marker carries the opening quote. Without it the banner line
/// "Archive of Our Own" matches first and the title comes back empty.
fn quoted_after(body: &str, marker: &str) -> Option<String> {
    let at = body.find(marker)?;
    let inner = body.get(at + marker.len()..)?;
    let end = inner.find('"')?;
    let title = inner.get(..end)?;
    (!title.is_empty()).then(|| capped(title, MAX_TITLE))
}

/// `Chapters: 9/13` → `(Some(9), Some(13))`; `55/?` → `(Some(55), None)`.
fn chapters(body: &str) -> (Option<u32>, Option<u32>) {
    let Some(value) = field(body, "Chapters") else { return (None, None) };
    let Some((posted, total)) = value.split_once('/') else { return (None, None) };
    let posted = posted.trim().parse::<u32>().ok().filter(|n| *n <= MAX_CHAPTERS);
    let total = total.trim().parse::<u32>().ok().filter(|n| *n <= MAX_CHAPTERS);
    (posted, total)
}

/// The total word count AO3 puts in parentheses on the first line.
fn parenthesised_words(body: &str) -> Option<u64> {
    let line = body.lines().find(|l| l.contains("posted a new"))?;
    words_in_parens(line)
}

fn chapter_title(body: &str) -> Option<String> {
    // The chapter line is the quoted string that stands alone, after the link.
    let after_link = body.split_once(WORKS_PREFIX).map(|(_, rest)| rest)?;
    let line = after_link
        .lines()
        .find(|l| l.trim_start().starts_with('"') && l.contains('"'))?;
    let inner = line.trim().strip_prefix('"')?;
    let end = inner.find('"')?;
    let title = inner.get(..end)?;
    (!title.is_empty()).then(|| capped(title, MAX_TITLE))
}

fn chapter_words(body: &str) -> Option<u64> {
    let after_link = body.split_once(WORKS_PREFIX).map(|(_, rest)| rest)?;
    let line = after_link.lines().find(|l| l.trim_start().starts_with('"'))?;
    words_in_parens(line)
}

/// `… ("Chapter 9" (4679 words)` → 4679.
fn words_in_parens(line: &str) -> Option<u64> {
    let at = line.rfind('(')?;
    let inner = line.get(at + 1..)?;
    let n = leading_u64(inner)?;
    inner
        .trim_start_matches(|c: char| c.is_ascii_digit())
        .trim_start()
        .starts_with("word")
        .then_some(n)
        .filter(|n| *n <= MAX_WORDS)
}

/// A single `Name: value` line.
fn field(body: &str, name: &str) -> Option<String> {
    for line in body.lines() {
        let Some(rest) = line.strip_prefix(name) else { continue };
        let Some(value) = rest.strip_prefix(':') else { continue };
        let value = value.trim();
        if !value.is_empty() {
            return Some(value.to_owned());
        }
    }
    None
}

/// A `Name: a, b, c` line as separate, capped, non-empty values.
fn list(body: &str, name: &str) -> Vec<String> {
    let Some(value) = field(body, name) else { return Vec::new() };
    value
        .split(',')
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .take(MAX_TAGS)
        .map(|v| capped(v, MAX_TAG))
        .collect()
}

/// `Summary:` runs to the separator rule AO3 prints before the footer.
fn summary(body: &str) -> Option<String> {
    let at = body.find("Summary:")?;
    let rest = body.get(at + "Summary:".len()..)?;
    let end = rest.find("\n---").unwrap_or(rest.len());
    let text = rest.get(..end)?;
    let cleaned = text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    (!cleaned.is_empty()).then(|| capped(&cleaned, MAX_SUMMARY))
}

/// AO3 states which subscription fired: a username, or a work or series title.
fn subscription(body: &str) -> Subscription {
    const MARKER: &str = "because you've subscribed to ";
    let Some(at) = body.find(MARKER) else { return Subscription::Unknown };
    let Some(rest) = body.get(at + MARKER.len()..) else { return Subscription::Unknown };
    let end = rest.find(". Follow the link").unwrap_or(rest.len());
    let Some(name) = rest.get(..end) else { return Subscription::Unknown };
    let name = name.trim();
    if name.is_empty() {
        return Subscription::Unknown;
    }
    let name = capped(name, MAX_TITLE);
    // A username has no spaces; a work or series title almost always does. This
    // is AO3's own phrasing and it does not label the kind, so the shape is all
    // there is — but the caller also knows the work id, so a wrong guess here
    // costs attribution wording, not identity.
    if name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
        Subscription::Author(name)
    } else {
        Subscription::Work(name)
    }
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

    /// A faithful reconstruction of AO3's chapter notification. The real mail
    /// this mirrors is never committed: it carries a reader's address and their
    /// reading history, and this repository is public.
    fn chapter_mail() -> String {
        [
            "From: Archive of Our Own <do-not-reply@archiveofourown.org>",
            "To: reader@example.com",
            "Date: Thu, 29 Oct 2026 00:49:51 +0000",
            "Subject: [AO3] lamplighter posted Chapter 9 of Linger Around the Light",
            "Content-Type: text/plain; charset=UTF-8",
            "",
            "Archive of Our Own",
            "=========================================",
            "",
            "lamplighter (https://archiveofourown.org/users/lamplighter/pseuds/lamplighter) \
             posted a new chapter of \"Linger Around the Light\" (34920 words):",
            "https://archiveofourown.org/works/83701926/chapters/255464091",
            "",
            "\"Chapter 9\" (4679 words)",
            "",
            "Chapters: 9/13",
            "Fandom: Example Fandom (TV 2015)",
            "Rating: Teen And Up Audiences",
            "Warning: No Archive Warnings Apply",
            "Relationships: Ada/Maren, Wren/Isolde",
            "Characters: Ada, Maren",
            "Additional Tags: Slow Burn, Fake Dating",
            "",
            "Summary: ",
            "    A lighthouse keeper writes letters she never sends.",
            "",
            "-----------------------------------------",
            "You're receiving this email because you've subscribed to lamplighter. \
             Follow the link to unsubscribe if you no longer wish to receive updates: \
             https://archiveofourown.org/users/lamplighter",
            "",
        ]
        .join("\r\n")
    }

    #[test]
    fn reads_a_chapter_notification() {
        let e = parse(chapter_mail().as_bytes()).unwrap();
        assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
        assert_eq!(e.work_id, 83_701_926);
        assert_eq!(e.chapter_id, Some(255_464_091));
        assert_eq!(e.work_title, "Linger Around the Light");
        assert_eq!(e.author, "lamplighter");
        assert_eq!(e.via, Subscription::Author("lamplighter".into()));
        assert_eq!((e.chapters_posted, e.chapters_total), (Some(9), Some(13)));
        assert_eq!(e.words, Some(34_920));
        assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9"));
        assert_eq!(e.chapter_words, Some(4_679));
        assert_eq!(e.rating.as_deref(), Some("Teen And Up Audiences"));
        assert_eq!(e.warnings, ["No Archive Warnings Apply"]);
        assert_eq!(e.relationships, ["Ada/Maren", "Wren/Isolde"]);
        assert_eq!(e.additional_tags, ["Slow Burn", "Fake Dating"]);
        assert!(e.summary.unwrap().starts_with("A lighthouse keeper"));
        assert!(e.at > 0);
    }

    #[test]
    fn an_unknown_chapter_total_is_none_not_zero() {
        let mail = chapter_mail().replace("Chapters: 9/13", "Chapters: 55/?");
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!((e.chapters_posted, e.chapters_total), (Some(55), None));
    }

    /// 28% of real chapter mail has no `Warning:` line, 49% no `Additional Tags:`.
    #[test]
    fn every_optional_field_may_be_absent() {
        let mail = chapter_mail()
            .replace("Warning: No Archive Warnings Apply\r\n", "")
            .replace("Additional Tags: Slow Burn, Fake Dating\r\n", "")
            .replace("Relationships: Ada/Maren, Wren/Isolde\r\n", "")
            .replace("Fandom: Example Fandom (TV 2015)\r\n", "")
            .replace("Characters: Ada, Maren\r\n", "");
        let e = parse(mail.as_bytes()).unwrap();
        assert!(e.warnings.is_empty());
        assert!(e.additional_tags.is_empty());
        assert!(e.relationships.is_empty());
        assert!(e.fandoms.is_empty());
        assert!(e.characters.is_empty());
        // The identity still survives, which is the point.
        assert_eq!(e.work_id, 83_701_926);
    }

    #[test]
    fn a_work_subscription_is_told_apart_from_an_author_one() {
        let mail = chapter_mail().replace(
            "subscribed to lamplighter.",
            "subscribed to Linger Around the Light.",
        );
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.via, Subscription::Work("Linger Around the Light".into()));
    }

    #[test]
    fn kudos_and_comment_mail_is_not_a_subscription_event() {
        let mail = chapter_mail()
            .replace("posted a new chapter of", "left kudos on")
            .replace("Subject: [AO3] lamplighter posted Chapter 9 of Linger Around the Light",
                     "Subject: [AO3] You've got kudos!");
        assert_eq!(parse(mail.as_bytes()), Err(ParseError::NotASubscriptionEvent));
    }

    #[test]
    fn a_link_on_another_host_yields_no_ids() {
        let mail = chapter_mail().replace(
            "https://archiveofourown.org/works/83701926/chapters/255464091",
            "https://evil.test/works/83701926/chapters/255464091",
        );
        assert_eq!(parse(mail.as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn a_lookalike_host_yields_no_ids() {
        let mail = chapter_mail().replace(
            "https://archiveofourown.org/works/8370",
            "https://archiveofourown.org.evil.test/works/8370",
        );
        assert_eq!(parse(mail.as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn a_redirect_tacked_onto_the_link_does_not_change_the_id() {
        let mail = chapter_mail().replace(
            "/works/83701926/chapters/255464091",
            "/works/83701926?next=https://evil.test/works/999",
        );
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.work_id, 83_701_926);
        assert_eq!(e.chapter_id, None);
    }

    #[test]
    fn absurd_counts_are_refused_rather_than_shown() {
        let mail = chapter_mail().replace("Chapters: 9/13", "Chapters: 999999999/999999999");
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!((e.chapters_posted, e.chapters_total), (None, None));
    }

    #[test]
    fn an_id_too_long_for_u64_is_refused() {
        let mail = chapter_mail().replace("/works/83701926", "/works/99999999999999999999999");
        assert_eq!(parse(mail.as_bytes()), Err(ParseError::NoWorkLink));
    }

    #[test]
    fn a_very_long_title_is_capped() {
        let huge = "x".repeat(5_000);
        let mail = chapter_mail().replace("Linger Around the Light\" (34920", &format!("{huge}\" (34920"));
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.work_title.len(), MAX_TITLE);
    }

    #[test]
    fn a_flood_of_tags_is_bounded() {
        let many = (0..500).map(|i| format!("tag{i}")).collect::<Vec<_>>().join(", ");
        let mail = chapter_mail().replace("Slow Burn, Fake Dating", &many);
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.additional_tags.len(), MAX_TAGS);
    }

    #[test]
    fn capping_never_splits_a_character() {
        // 4-byte characters either side of the cap.
        let s = "🔦".repeat(400);
        let out = capped(&s, MAX_TAG);
        assert!(out.len() <= MAX_TAG);
        assert!(std::str::from_utf8(out.as_bytes()).is_ok());
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

    /// An AO3 author may put a URL in their own work title. That arrives as a
    /// genuine, correctly signed message, so the gate cannot help — the parser
    /// must not let the title decide which work the mail is about.
    #[test]
    fn a_url_in_the_title_cannot_hijack_the_work_id() {
        let mail = chapter_mail().replace(
            "\"Linger Around the Light\"",
            "\"https://archiveofourown.org/works/111 \"",
        );
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.work_id, 83_701_926, "the link line wins, not the title");
    }

    #[test]
    fn a_url_in_the_summary_cannot_hijack_the_work_id() {
        let mail = chapter_mail().replace(
            "A lighthouse keeper writes letters she never sends.",
            "Read my other fic https://archiveofourown.org/works/222",
        );
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.work_id, 83_701_926);
    }

    #[test]
    fn a_users_url_in_the_summary_cannot_rename_the_author() {
        let mail = chapter_mail().replace(
            "A lighthouse keeper writes letters she never sends.",
            "impostor (https://archiveofourown.org/users/impostor) wrote this",
        );
        let e = parse(mail.as_bytes()).unwrap();
        assert_eq!(e.author, "lamplighter");
    }

    #[test]
    fn an_oversized_message_is_refused_before_decoding() {
        let mut mail = chapter_mail().into_bytes();
        mail.extend(std::iter::repeat_n(b'x', MAX_MESSAGE_BYTES));
        assert_eq!(parse(&mail), Err(ParseError::TooLarge));
    }
}
