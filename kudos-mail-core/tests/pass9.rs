//! Ninth review pass. The preface bound stops at AO3's metadata block, which
//! correctly excludes the work summary below it — and leaves the CHAPTER TITLE
//! and CHAPTER SUMMARY inside it. Both are author text that AO3 prints between
//! the link and the metadata, so a terminator placed there is tried first.
//!
//! `to_plain_text` glues a summary's first paragraph to AO3's label and puts
//! each later paragraph on its own line at column zero, which is how these
//! bodies arise from ordinary `<p>` markup.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, Identity, ReadError};

const CREATOR: &str =
    "skydarius11 (https://archiveofourown.org/users/skydarius11/pseuds/skydarius11)";

fn mail(body: &str, unsub: &str) -> Vec<u8> {
    format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] subscription update\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n\
         =========================================\r\n\r\n\r\n\
         {body}\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Honest Work. \
         Follow the link to unsubscribe if you no longer wish to receive updates: \
         https://archiveofourown.org/{unsub}\r\n"
    )
    .into_bytes()
}

fn ev(body: &str, unsub: &str) -> Result<Ao3Event, ReadError> {
    read(&mail(body, unsub), &Attestor::none()).map(|r| r.event)
}

/// 1 (High). A chapter summary whose paragraphs are `posted a new work:`, a
/// bare work URL and a quoted title turns the notification into a new work by
/// Anonymous. The work id stays the footer's, so `Identity::Work` still holds —
/// which is exactly why the rest moving matters.
#[test]
fn a_chapter_summary_cannot_rewrite_the_kind_or_author() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         Chapter Summary: posted a new work:\r\n\
         \r\n\
         https://archiveofourown.org/works/83701926\r\n\
         \r\n\
         \"Ghost Work\" (5 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         Warnings: No Archive Warnings Apply\r\n\
         \r\n\
         Summary:\r\n\
         \x20   A lighthouse keeper writes letters she never sends."
    );
    let e = ev(&body, "works/83701926").expect("notification");
    // Pass twelve: AO3's own terminator can fail the shape test, so a forgery
    // can outrank it and nothing textual says which is which. A disagreement
    // between candidates is contested and nothing preface-derived is reported.
    // The work id stands, because AO3's unsubscribe URL fixes it.
    assert_eq!(e.identity, Identity::Work);
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.kind, Ao3EventKind::Contested);
    assert_eq!(e.chapter_id, None);
    assert!(e.author.is_empty());
    assert!(e.work_title.is_empty());
    assert_eq!(e.words, None);
}

/// 2 (High). Two agreeing links under that same terminator abandoned the whole
/// region, so AO3's own preface was never tried and a single-chapter
/// notification was dropped.
#[test]
fn two_links_under_a_chapter_summary_do_not_drop_the_update() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         Chapter Summary: (1 word):\r\n\
         \r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         \r\n\
         https://archiveofourown.org/works/83701926/chapters/2\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   A lighthouse keeper writes letters she never sends."
    );
    let e = ev(&body, "works/83701926").expect("the subscriber must still learn the work updated");
    // Pass twelve: AO3's own terminator can fail the shape test, so a forgery
    // can outrank it and nothing textual says which is which. A disagreement
    // between candidates is contested and nothing preface-derived is reported.
    // The work id stands, because AO3's unsubscribe URL fixes it.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.kind, Ao3EventKind::Contested);
    assert_eq!(e.chapter_id, None);
}

/// 3 (Medium). One such link keeps the author but moves the chapter id, and
/// takes the work's title and word count with it.
#[test]
fn one_link_under_a_chapter_summary_does_not_move_the_chapter() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9: The Door\" (4679 words)\r\n\
         Chapter Summary: (1 word):\r\n\
         \r\n\
         https://archiveofourown.org/works/83701926/chapters/1\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   A lighthouse keeper writes letters she never sends."
    );
    let e = ev(&body, "works/83701926").expect("notification");
    // Pass twelve: AO3's own terminator can fail the shape test, so a forgery
    // can outrank it and nothing textual says which is which. A disagreement
    // between candidates is contested and nothing preface-derived is reported.
    // The work id stands, because AO3's unsubscribe URL fixes it.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.kind, Ao3EventKind::Contested);
    assert_eq!(e.chapter_id, None, "never the author's chapter");
    assert!(e.work_title.is_empty());
}

/// 4 (Medium). Mail through 7 October 2025 does not quote the work title, so a
/// title containing a quote of its own made the quoted reader win and report
/// part of the title with the author's own word count.
#[test]
fn an_unquoted_title_with_a_quote_keeps_ao3s_count() {
    let body = "\
skydarius11 (http://archiveofourown.org/users/skydarius11/pseuds/skydarius11) \
posted a new chapter of Burning \"Fake\" (1 word) Air (63338 words):\r\n\
http://archiveofourown.org/works/43422333/chapters/181080146\r\n\
\r\n\
\"Chapter 5\" (5609 words)\r\n\
\r\n\
Chapters: 5/10\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n\
\r\n\
Summary:\r\n\
\x20   Kept.";
    let e = ev(body, "works/43422333").expect("notification");
    assert_eq!(e.work_id, 43_422_333);
    assert_eq!(e.chapter_id, Some(181_080_146));
    assert_eq!(e.work_title, "Burning \"Fake\" (1 word) Air");
    assert_eq!(e.words, Some(63_338));
}
