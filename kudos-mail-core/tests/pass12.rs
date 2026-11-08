//! Twelfth review pass (Codex). Three findings against the pass-eleven fix,
//! all from one fact: `ao3_shaped` depends on lines an author also controls.
//! A CHAPTER TITLE is author text and may be multiline, so AO3's own
//! terminator can fail the shape test — its first line after the URL is only
//! `"Chapter 9` — while a forged terminator elsewhere passes it.
//!
//! Codex's conclusion, which matches the one reached at pass eight: neither
//! bottom-up order nor the immediate-link shortcut can authenticate one
//! author-reproducible rendering over another. So the parser stops choosing.
//! When the preface is contested it emits a **footer-pinned partial event**:
//! the work id, which AO3's unsubscribe URL fixes, and nothing preface-derived.
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

/// Whatever else happens, these must hold: the work is AO3's, and no field
/// carries a value only a payload could have produced.
fn never_the_authors(e: &Ao3Event) {
    assert_eq!(e.work_id, 83_701_926, "work id moved");
    assert!(
        matches!(e.chapter_id, None | Some(255_464_091)),
        "chapter_id = {:?}",
        e.chapter_id
    );
    assert_ne!(e.words, Some(1), "word count came from a payload");
    assert_ne!(e.words, Some(4_679), "work words came from the chapter's count");
    assert!(!e.work_title.contains("Ghost"), "title from a payload: {}", e.work_title);
    assert!(!e.work_title.contains("Decoy"), "title from a payload: {}", e.work_title);
}

/// Finding 1 — a multiline chapter title makes AO3's terminator unshaped while
/// a forged `posted a new work:` in that title is shaped, so the kind, author
/// and title all move.
#[test]
fn a_multiline_chapter_title_does_not_hand_over_the_preface() {
    let body = format!(
        "{C} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\r\n\
         posted a new work:\r\n\
         https://archiveofourown.org/works/83701926\r\n\
         \"Ghost\" (5 words)\r\n\
         The Door\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   Real work summary."
    );
    let e = ev(&body, "works/83701926").expect("notification");
    never_the_authors(&e);
    assert_ne!(e.kind, Ao3EventKind::NewWork, "a chapter notification became a new work");
    assert_ne!(e.author, "Anonymous", "the author was lost to a forged preface");
}

/// Finding 2 — with the bound retired and the metadata block ambiguous, the
/// work summary itself supplied the accepted chapter link.
#[test]
fn a_summary_cannot_supply_the_accepted_link() {
    let body = format!(
        "{C} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   Real first paragraph.\r\n\
         \r\n\
         \"Ghost\" (1 word):\r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         \r\n\
         \"Decoy\" (2 words)\r\n\
         \r\n\
         Chapters: 1/1\r\n\
         Fandom: Forged\r\n"
    );
    let e = ev(&body, "works/83701926").expect("notification");
    never_the_authors(&e);
    assert_ne!(e.chapter_id, Some(1), "the summary chose the chapter");
}

/// Finding 3 — the tier-barring rule steered into a denial: a forged tier-0
/// candidate whose link is unusable, followed by two usable ones, bars every
/// lower tier and the genuine terminator is never tried.
#[test]
fn a_barred_tier_does_not_deny_the_update() {
    let body = format!(
        "{C} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\r\n\
         \"Ghost\" (1 word):\r\n\
         https://archiveofourown.org/works/999/chapters/9\r\n\
         \r\n\
         \"Decoy\" (2 words)\r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         https://archiveofourown.org/works/83701926/chapters/2\r\n\
         The Door\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   Real work summary."
    );
    let e = ev(&body, "works/83701926").expect("the subscriber must still learn the work updated");
    never_the_authors(&e);
    assert_eq!(e.identity, Identity::Work);
}
