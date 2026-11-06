//! Tenth review pass. Bodies in AO3's real rendering.
//!
//! The pass-nine fix ranked preface candidates in tiers, and `anchored` — "AO3's
//! phrase is on the region's first line" — turned out to be nearly vacuous: the
//! first line IS AO3's, so every candidate in a genuine region inherited it.
//! Three of these five findings come from that.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, Identity, ReadError};

const C: &str = "skydarius11 (https://archiveofourown.org/users/skydarius11/pseuds/skydarius11)";

fn ev(body: &str) -> Result<Ao3Event, ReadError> {
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
         Follow the link to unsubscribe: \
         https://archiveofourown.org/works/83701926\r\n"
    );
    read(raw.as_bytes(), &Attestor::none()).map(|r| r.event)
}

/// 1 (High). `Fandom:` comes BEFORE `Rating:` in `_work_info`, and a multiline
/// fandom value can therefore inject a `Rating:` of its own that `field` reads
/// first — then a blank line ends the run early so an injected `Summary:` is
/// the first one below the block. Worse than the documented `Series:` limit:
/// fandom is mandatory, and a forged rating defeats content filtering.
#[test]
fn a_multiline_fandom_cannot_supply_the_rating() {
    let body = format!(
        "{C} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: General Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   FORGED FROM FANDOM\r\n\
         \r\n\
         Rating: Explicit\r\n\
         Warning: No Archive Warnings Apply\r\n\
         \r\n\
         Summary:\r\n\
         \x20   REAL WORK SUMMARY"
    );
    let e = ev(&body).expect("notification");
    assert_ne!(e.rating.as_deref(), Some("General Audiences"), "forged rating won");
    assert_ne!(
        e.summary.as_deref().map(|s| s.contains("FORGED")),
        Some(true),
        "forged summary won"
    );
}

/// 2 (High). A work-only link under a NewWork terminator inside the title, plus
/// a second chapter link that makes AO3's own candidate ambiguous, let the
/// forged lower-tier candidate win.
#[test]
fn ambiguity_cannot_demote_to_a_forged_kind() {
    let body = format!(
        "{C} posted a new chapter of \"Prelude posted a new work:\r\n\
         https://archiveofourown.org/works/83701926\r\n\
         tail\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         Tail\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = ev(&body).expect("notification");
    assert_eq!(e.identity, Identity::Work);
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.author, "skydarius11");
    assert_eq!(e.words, Some(576_402));
}

/// 3 (High). `anchored` was inherited from the region's genuine first line, so
/// a chapter-summary paragraph ending `" (1 word):` had both tier-(a)
/// properties and, being lower, sorted ahead of AO3's own candidate.
#[test]
fn a_quoted_chapter_summary_cannot_reach_the_top_tier() {
    let body = format!(
        "{C} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         Chapter Summary: setup\r\n\
         \r\n\
         \"Ghost\" (1 word):\r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = ev(&body).expect("notification");
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.work_title, "Honest Work");
    assert_eq!(e.words, Some(576_402));
    assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9: The Door"));
}

/// 4 (Medium). A closing quote alone cannot identify the era: an old unquoted
/// title that ends in a quote of its own made `closer_is_quoted` report the
/// pre-October-2025 template as quoted, and the quoted reader took a fragment.
#[test]
fn an_old_title_ending_in_a_quote_keeps_its_prefix() {
    let body = format!(
        "{C} posted a new chapter of Burning \"Air\" (63338 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 5\" (5609 words)\r\n\
         \r\n\
         Chapters: 5/10\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = ev(&body).expect("notification");
    assert_eq!(e.work_title, "Burning \"Air\"");
    assert_eq!(e.words, Some(63_338));
}

/// 5 (Medium). Two fandom-carrying runs make the block ambiguous, and the bound
/// then fell back to the first bare `Summary:` — which can be inside the work
/// title, above AO3's terminator. That removed every candidate and denied the
/// update entirely.
#[test]
fn a_title_summary_plus_two_blocks_does_not_deny_the_update() {
    let body = format!(
        "{C} posted a new chapter of \"Safe\r\n\
         Summary:\r\n\
         Rest\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\" (4679 words)\r\n\
         Chapter Summary: setup\r\n\
         \r\n\
         Chapters: 1/1\r\n\
         Fandom: Forged\r\n\
         Rating: General Audiences\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   REAL WORK SUMMARY"
    );
    let e = ev(&body).expect("the real chapter must survive");
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
}
