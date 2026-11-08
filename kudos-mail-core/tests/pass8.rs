//! Eighth review pass. Bodies in AO3's real rendering: creators carry their
//! pseud URL, word counts use the real singular/plural, metadata follows the
//! template's order.
//!
//! The theme: bottom-up candidate selection was justified by "the title is
//! interpolated inside AO3's sentence, so an author's closer always comes
//! first". True of the title — and false of the SUMMARY, which AO3 prints last.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, ReadError};

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

fn read_it(body: &str, unsub: &str) -> Result<Ao3Event, ReadError> {
    read(&mail(body, unsub), &Attestor::none()).map(|r| r.event)
}

/// 1 (Critical). The work summary is terminal author text, BELOW AO3's preface,
/// so a terminator-shaped line and a URL inside it became the bottom-most
/// candidate and were tried first.
#[test]
fn a_summary_cannot_supply_the_preface() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 12\" (4679 words)\r\n\
         \r\n\
         Chapters: 12/20\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         \r\n\
         Summary:\r\n\
         \x20   \"Decoy\" (1 word):\r\n\
         https://archiveofourown.org/works/111/chapters/222"
    );
    let e = read_it(&body, "users/subscriber").expect("notification");
    assert_eq!(e.work_id, 83_701_926, "took the work id out of a summary");
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.work_title, "Honest Work");
    assert_eq!(e.words, Some(576_402));
    assert_eq!(e.chapter_title.as_deref(), Some("Chapter 12"));
}

/// 3 (High). `Series:` is the last field of `_work_info` and its value is
/// author text, so a blank line and a `Summary:` label inside a multiline
/// series title read as AO3's own work-summary label.
#[test]
fn a_series_value_cannot_forge_the_summary() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"Honest Work\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 12\" (4679 words)\r\n\
         \r\n\
         Chapters: 12/20\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n\
         Series: Part 1 of Safe\r\n\
         \r\n\
         Summary:\r\n\
         \x20   FORGED FROM SERIES"
    );
    let e = read_it(&body, "works/83701926").expect("notification");
    // Not fixed, and deliberately so. A series title holding a blank line and a
    // `Summary:` label renders identically to AO3's own summary label, indent
    // included, so no rule separates them. Refusing a summary whenever a series
    // is present was tried and costs every work in a series its summary. What
    // must hold is that nothing else moves: the text at stake is the author's
    // own, in their own work's summary slot.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(12) });
    assert_eq!(e.rating.as_deref(), Some("Teen And Up Audiences"));
    assert_eq!(e.series.as_deref(), Some("Part 1 of Safe"));
}

/// 4 (High). A divider inside a title split the region before AO3's terminator,
/// so the first region had the phrase but no terminator — and the message was
/// refused outright, dropping every later creation with it.
#[test]
fn a_split_first_region_does_not_refuse_the_batch() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"Safe\r\n\
         --------------------\r\n\
         x posted a new work:\r\n\
         Rest\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 12\" (4679 words)\r\n\
         \r\n\
         Chapters: 12/20\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    match read_it(&body, "works/83701926") {
        Ok(e) => assert_eq!(e.work_id, 83_701_926),
        Err(e) => panic!("one author's title suppressed the whole message: {e:?}"),
    }
}

/// 5 (Medium). The candidate cap returned early, so AO3's own terminator — the
/// last one — was never recorded once a title held more than the cap.
#[test]
fn many_fake_closers_do_not_hide_ao3s_own() {
    let fakes = (0..40).map(|n| format!("f{n}\" (1 word):\r\n")).collect::<String>();
    let body = format!(
        "{CREATOR} posted a new chapter of \"{fakes}Rest\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 12\" (4679 words)\r\n\
         \r\n\
         Chapters: 12/20\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );
    let e = read_it(&body, "works/83701926").expect("notification");
    // Forty closers inside one title are forty disputed preface boundaries, so
    // the message is contested and no count is reported. The original point of
    // this test — that a fake closer must not SUPPLY the word count — holds in
    // the stronger form: nothing supplies it.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.kind, Ao3EventKind::Contested);
    assert_eq!(e.words, None, "never a fake closer's count");
}

/// 2 (Critical) — the part that parsing cannot settle, so the event says so.
///
/// An author can split their own notification with a divider inside a title and
/// make the leading fragment satisfy every test for a creation: an agreeing
/// link, a creation-title line, and a single fandom-carrying metadata block.
/// They control all three. No rule separates that fragment from AO3's own
/// layout, so the event reports how far its identity actually goes.
#[test]
fn a_forged_fragment_is_reported_as_unanchored() {
    let body = format!(
        "{CREATOR} posted a new chapter of \"X\" (1 word):\r\n\
         https://archiveofourown.org/works/111/chapters/222\r\n\
         \r\n\
         \"Y\" (1 word)\r\n\
         \r\n\
         Chapters: 1/1\r\n\
         Fandom: X\r\n\
         Rating: Explicit\r\n\
         --------------------\r\n\
         x posted a new chapter of \"Z\" (576402 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 12\" (4679 words)\r\n\
         \r\n\
         Chapters: 12/20\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen And Up Audiences\r\n"
    );

    // A work subscription pins the work, so the fragment cannot substitute
    // another one — it can still move the chapter and metadata within it.
    let e = read_it(&body, "works/83701926").expect("notification");
    assert_eq!(e.identity, kudos_mail_core::Identity::Work);
    assert_eq!(e.work_id, 83_701_926, "the footer's work id is AO3's");

    // An author subscription pins nothing, and the event does not pretend it
    // does. This is the value of the flag: the host must confirm against AO3
    // rather than act on it.
    let e = read_it(&body, "users/subscriber").expect("notification");
    assert_eq!(e.identity, kudos_mail_core::Identity::Body);
}
