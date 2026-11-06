//! Sixth review pass. Each body was supplied with its finding; the assertions
//! are AO3's real values, so a failure is the finding.
//!
//! The theme of this pass is the *fallbacks*: each anchor added in pass five is
//! sound, but what happens when one cannot be applied was not — an ambiguous
//! footer anchor fell back to the positional parser it replaced, and an
//! unidentified metadata block reset the summary anchor to line zero.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, ReadError};

/// `unsub` is the footer's `polymorphic_url` path: `works/<id>` for a work
/// subscription, `users/<login>` for an author one.
fn parsed(body: &str, unsub: &str) -> Result<Ao3Event, ReadError> {
    let raw = format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] x\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n\
         =========================================\r\n\r\n\r\n\
         {body}\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Linger. \
         Follow the link to unsubscribe if you no longer wish to receive updates: \
         https://archiveofourown.org/{unsub}\r\n\r\n\
         If you don't understand why you received this email, please contact \
         Support: https://archiveofourown.org/support.\r\n"
    );
    read(raw.as_bytes(), &Attestor::none()).map(|r| r.event)
}

/// 1 (Critical). Two lines match the footer's work id, so the anchor is
/// ambiguous — and the `or_else` handed the message to the positional parser
/// the anchor exists to replace, which then chose the author's work.
#[test]
fn an_ambiguous_footer_anchor_does_not_fall_back() {
    let body = "\
lamplighter posted a new chapter of \"Decoy\" (1 words):\r\n\
https://archiveofourown.org/works/111/chapters/222\r\n\
\r\n\
\"Forged chapter\" (1 words)\r\n\
Chapter Summary: title text\r\n\
https://archiveofourown.org/works/83701926\r\n\
rest\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n";
    match parsed(body, "works/83701926") {
        // Either answer is safe. What must never happen is work 111.
        Ok(e) => assert_eq!(e.work_id, 83_701_926, "fell back to the author's work"),
        Err(ReadError::Parse(_)) => {}
        Err(other) => panic!("unexpected: {other:?}"),
    }
}

/// 2 (Critical). The same forged divider as pass five, but with an AUTHOR
/// footer, which has no work-id anchor. The split does not merely over-count
/// creations — it selects the wrong one as the subject.
#[test]
fn a_forged_divider_does_not_choose_the_subject() {
    let body = "\
lamplighter posted a new chapter of \"Decoy\" (1 words):\r\n\
https://archiveofourown.org/works/111/chapters/222\r\n\
\r\n\
--------------------\r\n\
ignored posted a new work:\r\n\
\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n";
    match parsed(body, "users/lamplighter") {
        Ok(e) => assert_eq!(e.work_id, 83_701_926, "the fragment was read as the subject"),
        Err(ReadError::Parse(_)) => {}
        Err(other) => panic!("unexpected: {other:?}"),
    }
}

/// 3 (High). A title may END a line with a work terminator, so the first
/// terminator found is not AO3's. The kind it implies contradicts the link,
/// which is `/chapters/`.
#[test]
fn a_terminator_inside_a_title_does_not_choose_the_kind() {
    let body = "\
lamplighter posted a new chapter of \"x posted a new work:\r\n\
rest\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n";
    let e = parsed(body, "works/83701926").expect("notification");
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(e.author, "lamplighter");
    assert_eq!(e.words, Some(34_920));
    assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9"));
}

/// 4 (High). A run was counted as carrying a fandom only if the VALUE was
/// non-empty, so an empty `Fandom:` on AO3's own run let a forged run become
/// the single qualifying one.
#[test]
fn an_empty_fandom_value_still_counts_as_a_fandom_line() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom:\r\n\
\r\n\
Chapters: 1/1\r\n\
Fandom: Forged\r\n\
Rating: Explicit\r\n";
    let e = parsed(body, "works/83701926").expect("notification");
    assert_ne!(e.rating.as_deref(), Some("Explicit"), "accepted the forged run");
    assert_ne!(e.kind, Ao3EventKind::NewChapter { number: Some(1) }, "accepted 1/1");
}

/// 5 (High). When the metadata block cannot be identified, `meta_end` was 0 —
/// which reopened every author-written `Summary:` above it.
#[test]
fn an_unanchored_summary_is_not_taken_from_author_text() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapter Summary: lead\r\n\
Summary:\r\n\
FAKE WORK SUMMARY\r\n\
Chapters: 1/1\r\n\
Fandom: Forged\r\n\
Rating: Explicit\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n\
\r\n\
Summary:\r\n\
    REAL WORK SUMMARY";
    let e = parsed(body, "works/83701926").expect("notification");
    let summary = e.summary.as_deref().unwrap_or("");
    assert!(!summary.contains("FAKE WORK SUMMARY"), "took author text: {summary}");
}

/// 6 (Medium). `title_region` stopped at a structural-looking line inside the
/// title, leaving the author's closer as the last one in the shortened region.
#[test]
fn a_structural_line_in_a_title_does_not_end_the_region() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Fake\" (1 words)\r\n\
Summary:\r\n\
rest of the real chapter title\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n";
    let e = parsed(body, "works/83701926").expect("notification");
    assert_ne!(e.chapter_words, Some(1), "the author chose the word count");
}

/// 7 (High availability). Both scans were quadratic on author text. The 1 MiB
/// cap bounds the input, not the work done on it.
#[test]
fn author_text_cannot_stall_the_parser() {
    let quotes = "\"".repeat(60_000);
    let urls = "https://archiveofourown.org/".repeat(20_000);
    let body = format!(
        "lamplighter posted a new chapter of \"Linger{quotes}\" (34920 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
         \r\n\
         \"Chapter 9\" (4679 words)\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen\r\n\
         \r\n\
         Summary:\r\n\
             {urls}"
    );
    let started = std::time::Instant::now();
    let _ = parsed(&body, "works/83701926");
    let elapsed = started.elapsed();
    assert!(elapsed.as_secs() < 2, "took {elapsed:?} on author-controlled text");
}

/// The corpus caught this one, not a reviewer. Making an ambiguous footer
/// anchor terminal (finding 1) refused a REAL message: a batch notification for
/// two chapters of the same work has one link line per creation, so two lines
/// legitimately name the footer's work. Ambiguity is terminal only WITHIN a
/// region; across regions the one carrying AO3's metadata block is the subject,
/// which `@seen` guarantees is the first.
#[test]
fn a_genuine_batch_of_one_works_chapters_is_not_refused() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n\
\r\n\
Summary:\r\n\
    real summary\r\n\
\r\n\
--------------------\r\n\
\r\n\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464092\r\n\
\r\n\
\"Chapter 10\" (1200 words)\r\n";
    let e = parsed(body, "works/83701926").expect("a real batch must not be refused");
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091), "the first creation is the subject");
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(e.extra_creations, 1, "the second chapter is counted, not dropped");
}
