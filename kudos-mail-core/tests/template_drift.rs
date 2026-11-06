//! AO3's notification template has changed over the years, and a mailbox being
//! imported holds every version of it. These shapes came from widening the real
//! corpus from six messages to thirty, sampled for variety rather than
//! recency — eight adversarial review passes had not found either of them,
//! because both are correctness bugs on genuine mail rather than attacks.
//!
//! Dates are from the corpus, oldest first.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, ReadError};

fn read_body(body: &str, unsub: &str) -> Result<Ao3Event, ReadError> {
    let raw = format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Sun, 08 Dec 2024 15:43:10 +0000\r\n\
         Subject: [AO3] subscription update\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n\
         =========================================\r\n\r\n\r\n\
         {body}\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Burning Air. \
         Follow the link to unsubscribe if you no longer wish to receive updates: \
         {unsub}\r\n"
    );
    read(raw.as_bytes(), &Attestor::none()).map(|r| r.event)
}

/// December 2024: the links were `http://`, and requiring `https://` failed the
/// message outright — six of the thirty sampled, all the oldest.
#[test]
fn the_older_http_scheme_still_parses() {
    let body = "\
someone (http://archiveofourown.org/users/someone/pseuds/someone) \
posted a new chapter of Burning Air (2212 words):\r\n\
http://archiveofourown.org/works/52367692/chapters/183582421\r\n\
\r\n\
Chapter 5 (5609 words)\r\n\
\r\n\
Chapters: 5/12\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n\
\r\n\
Summary:\r\n\
\x20   a real summary";
    let e = read_body(body, "http://archiveofourown.org/works/52367692").expect("notification");
    assert_eq!(e.work_id, 52_367_692);
    assert_eq!(e.chapter_id, Some(183_582_421));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(5) });
    assert_eq!(e.author, "someone", "the pseud URL is stripped in either scheme");
    assert_eq!(e.via, kudos_mail_core::Subscription::Work {
        id: 52_367_692,
        name: Some("Burning Air".into())
    });
}

/// Up to 7 October 2025 the work title was NOT quoted; from 21 October it is.
/// The quoted reader found nothing in the older shape, so twelve of thirty real
/// messages arrived with an empty work title — a whole era of a backlog.
#[test]
fn an_unquoted_preface_title_is_read() {
    let body = "\
someone (https://archiveofourown.org/users/someone/pseuds/someone) \
posted a new chapter of Burning Air (63338 words):\r\n\
https://archiveofourown.org/works/43422333/chapters/181080146\r\n\
\r\n\
Chapter 29 (2500 words)\r\n\
\r\n\
Chapters: 29/40\r\n\
Fandom: Original Work\r\n\
Rating: Mature\r\n\
\r\n\
Summary:\r\n\
\x20   a real summary";
    let e = read_body(body, "https://archiveofourown.org/works/43422333").expect("notification");
    assert_eq!(e.work_title, "Burning Air");
    assert_eq!(e.words, Some(63_338), "AO3's count, appended after the title");
    assert_eq!(e.work_id, 43_422_333);
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(29) });
}

/// A title containing its own `(N words)` must not beat the count AO3 appended
/// last, in the unquoted shape as well as the quoted one.
#[test]
fn an_unquoted_title_holding_a_count_does_not_win() {
    let body = "\
someone (https://archiveofourown.org/users/someone/pseuds/someone) \
posted a new chapter of Fake (1 word) Air (63338 words):\r\n\
https://archiveofourown.org/works/43422333/chapters/181080146\r\n\
\r\n\
Chapter 29 (2500 words)\r\n\
\r\n\
Chapters: 29/40\r\n\
Fandom: Original Work\r\n\
Rating: Mature\r\n";
    let e = read_body(body, "https://archiveofourown.org/works/43422333").expect("notification");
    assert_eq!(e.words, Some(63_338));
    assert_eq!(e.work_title, "Fake (1 word) Air");
}

/// The corpus turned up a genuine anonymous post, which no invented body had
/// covered: AO3 prints `Anonymous posted …` with no creators and no pseud URL.
#[test]
fn an_anonymous_preface_reports_no_author() {
    let body = "\
Anonymous posted a new chapter of \"Quiet\" (900 words):\r\n\
https://archiveofourown.org/works/43422333/chapters/181080146\r\n\
\r\n\
\"Chapter 2\" (450 words)\r\n\
\r\n\
Chapters: 2/2\r\n\
Fandom: Original Work\r\n\
Rating: General Audiences\r\n";
    let e = read_body(body, "https://archiveofourown.org/works/43422333").expect("notification");
    assert_eq!(e.author, "Anonymous");
    assert_eq!(e.work_title, "Quiet");
    assert_eq!(e.work_id, 43_422_333);
}
