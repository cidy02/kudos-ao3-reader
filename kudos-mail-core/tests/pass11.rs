//! Eleventh review pass (Grok). Four findings, one root cause: `unbroken`
//! demotes AO3's own closer whenever a works URL appears above it — and a work
//! title may contain one, because **titles are not run through
//! `to_plain_text`**. `sanitize_value` strips tags and keeps a literal newline,
//! and `Work#clean_and_validate_title` only trims the ends, within `TITLE_MAX`
//! of 255. So a forged terminator placed BEFORE the title's URL stays in the
//! top tier while the real one is demoted.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, Identity, ReadError};

const C: &str = "skydarius11 (https://archiveofourown.org/users/skydarius11/pseuds/skydarius11)";

fn ev(body: &str, unsub: &str) -> Result<Ao3Event, ReadError> {
    let raw = format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] subscription update\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n\
         =========================================\r\n\r\n\r\n\
         {body}\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Honest Work. \
         Follow the link to unsubscribe: https://archiveofourown.org/{unsub}\r\n"
    );
    read(raw.as_bytes(), &Attestor::none()).map(|r| r.event)
}

/// Finding 1 — A `posted a new work:` line before the title's URL is tier 1 while AO3's
/// own `words):` closer is tier 2, so the kind, the author and the title all
/// move.
#[test]
fn a_new_work_phrase_in_a_title_cannot_change_the_kind() {
    let body = format!(
        "{C} posted a new chapter of \"x) posted a new work:\r\n\
         https://archiveofourown.org/works/83701926\r\n\
         Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = ev(&body, "works/83701926").expect("notification");
    // Pass twelve retired the tiering these assertions relied on: AO3's own
    // terminator can fail the shape test, so a forgery can outrank it and no
    // textual fact says which is which. A disagreement now makes the preface
    // contested and nothing read from it is reported. The work id stands.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.kind, Ao3EventKind::Contested);
    assert_eq!(e.chapter_id, None);
    assert!(e.author.is_empty());
    assert_eq!(e.words, None);
}

/// Finding 2 — The same demotion with a `(1 word):` closer replaces the work title and
/// its word count.
#[test]
fn a_fake_closer_above_the_titles_url_does_not_win() {
    let body = format!(
        "{C} posted a new chapter of \"Ghost\r\n\
         \" (1 word):\r\n\
         https://archiveofourown.org/works/111/chapters/9\r\n\
         Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = ev(&body, "works/83701926").expect("notification");
    assert_eq!(e.words, Some(576_402), "the author's count won");
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_ne!(e.work_title, "Ghost", "the title stopped at the fake closer");
}

/// Finding 2b — The same, on an author subscription, where nothing pins the work id —
/// the forged preface took work 111 outright.
#[test]
fn an_author_subscription_does_not_take_the_titles_work() {
    let body = format!(
        "{C} posted a new chapter of \"Ghost\r\n\
         \" (1 word):\r\n\
         https://archiveofourown.org/works/111/chapters/9\r\n\
         Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    // No footer anchor and a contested preface leaves nothing trustworthy to
    // say about which work it is, so the message is refused outright. What must
    // never happen is reporting work 111 as fact.
    match ev(&body, "users/subscriber") {
        Ok(e) => {
            assert_eq!(e.identity, Identity::Body);
            assert_eq!(e.work_id, 83_701_926, "took the work id out of a title");
        }
        Err(ReadError::Parse(_)) => {}
        Err(other) => panic!("unexpected: {other:?}"),
    }
}

/// Finding 3 — Two links under the fake closer bar every lower tier, so AO3's own
/// closer is never tried and a work subscriber loses the chapter entirely.
#[test]
fn two_links_under_a_fake_closer_do_not_drop_the_update() {
    let body = format!(
        "{C} posted a new chapter of \"Honest\r\n\
         (1 word):\r\n\
         see also\r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         https://archiveofourown.org/works/83701926/chapters/2\r\n\
         Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = ev(&body, "works/83701926").expect("the subscriber must still learn the work updated");
    // Pass twelve retired the tiering these assertions relied on: AO3's own
    // terminator can fail the shape test, so a forgery can outrank it and no
    // textual fact says which is which. A disagreement now makes the preface
    // contested and nothing read from it is reported. The work id stands.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.kind, Ao3EventKind::Contested);
    assert_eq!(e.chapter_id, None, "never the author's chapter");
}

/// Finding 4 — A title holding both a URL and a `Summary:` arms the bound's fallback
/// when two fandom runs make the metadata block ambiguous, leaving no candidate
/// inside the bound at all.
#[test]
fn a_title_url_plus_summary_does_not_deny_the_update() {
    let body = format!(
        "{C} posted a new chapter of \"Safe\r\n\
         https://archiveofourown.org/works/1/chapters/2\r\n\
         Summary:\r\n\
         Rest\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   REAL\r\n\
         \r\n\
         Chapters: 1/1\r\n\
         Fandom: Forged\r\n\
         Rating: Explicit\r\n"
    );
    let e = ev(&body, "works/83701926").expect("the real chapter must survive");
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
}
