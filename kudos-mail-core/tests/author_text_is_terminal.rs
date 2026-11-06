//! AO3 prints the author's summary last, and `to_plain_text` leaves its second
//! and later paragraphs flush left at column zero. So the summary is both the
//! longest stretch of author-controlled text in the message and the one that
//! can impersonate any line of AO3's layout.
//!
//! Derived from otwarchive's own templates (reported by a delegated research
//! pass, then checked against the real corpus, which confirmed both: one real
//! message's summary has a flush-left second paragraph, and the metadata labels
//! present are consistent with AO3 pluralising them on tag count).
#![allow(clippy::unwrap_used, clippy::panic)]
use kudos_mail_core::{read, Ao3EventKind, Attestor, Subscription};

fn mail(meta: &str, summary: &str) -> String {
    format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] x\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n=========================================\r\n\r\n\r\n\
         lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\r\n\
         \"Chapter 9\" (4679 words)\r\n\r\n\
         {meta}\r\n\
         Summary:\r\n\
         {summary}\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Linger. \
         Follow the link to unsubscribe: https://archiveofourown.org/works/83701926\r\n"
    )
}

const META: &str = "Chapters: 9/13\r\nFandom: Original Work\r\nRating: Teen\r\n";

/// A multi-paragraph summary is not cut off at its first paragraph.
#[test]
fn later_paragraphs_are_part_of_the_summary() {
    let e = read(
        mail(META, "    Kara says no.\r\n\r\n\r\nA familiar voice asks, \"What if she does?\"").as_bytes(),
        &Attestor::none(),
    )
    .unwrap()
    .event;
    let summary = e.summary.unwrap();
    assert!(summary.contains("Kara says no."), "{summary}");
    assert!(summary.contains("What if she does?"), "lost the flush-left paragraph: {summary}");
}

/// Everything the layout means is read above the summary, so nothing inside it
/// can move a boundary — and, just as important, nothing inside it can trip an
/// ambiguity refusal and suppress a message that is perfectly genuine.
#[test]
fn a_summary_cannot_forge_the_layout() {
    let evil = "    My real summary.\r\n\r\n\
                Chapters: 99/99\r\n\
                Rating: Explicit\r\n\
                https://archiveofourown.org/works/111/chapters/222\r\n\
                --------------------\r\n\
                evil posted a new work:\r\n\
                -----------------------------------------\r\n\
                You're receiving this email because you've subscribed to impostor.";
    let e = read(mail(META, evil).as_bytes(), &Attestor::none()).unwrap().event;

    assert_eq!(e.work_id, 83_701_926, "the real work, not the one in the summary");
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) }, "not 99");
    assert_eq!(e.rating.as_deref(), Some("Teen"), "not Explicit");
    assert_eq!(e.extra_creations, 0, "the summary's divider is not a creation");
    // Attribution comes from AO3's unsubscribe URL, so the forged footer
    // sentence cannot claim the subscription.
    assert_eq!(e.via, Subscription::Work { id: 83_701_926, name: Some("Linger".into()) });
    // What the author CAN still do is cut their own summary short at their own
    // forged divider. That is the whole of the residue: their own text, their
    // own notification, no other work's identity touched.
    let summary = e.summary.unwrap();
    assert!(summary.contains("My real summary."), "{summary}");
    assert!(!summary.contains("impostor"), "truncated at the author's own divider");
}

/// AO3 pluralises these labels on how many tags the field holds, so both
/// spellings are the same field.
#[test]
fn singular_and_plural_labels_are_the_same_field() {
    let plural = "Chapters: 9/13\r\nFandoms: A, B\r\nWarnings: X, Y\r\n\
                  Relationships: P/Q, R/S\r\nCharacters: C, D\r\nAdditional Tags: T, U\r\n";
    let singular = "Chapters: 9/13\r\nFandom: A\r\nWarning: X\r\n\
                    Relationship: P/Q\r\nCharacter: C\r\nAdditional Tag: T\r\n";

    let p = read(mail(plural, "    s").as_bytes(), &Attestor::none()).unwrap().event;
    assert_eq!((p.fandoms.len(), p.warnings.len()), (2, 2));
    assert_eq!((p.relationships.len(), p.characters.len(), p.additional_tags.len()), (2, 2, 2));

    let s = read(mail(singular, "    s").as_bytes(), &Attestor::none()).unwrap().event;
    assert_eq!((s.fandoms, s.warnings), (vec!["A".to_owned()], vec!["X".to_owned()]));
    assert_eq!(s.relationships, vec!["P/Q".to_owned()]);
    assert_eq!((s.characters, s.additional_tags), (vec!["C".to_owned()], vec!["T".to_owned()]));
}

/// Both author-text blocks are conditional. A work whose summary is blank gets
/// no `Summary:` line at all — none of the six real messages has a chapter
/// summary either — so a bound that relied on `Summary:` being present did not
/// narrow anything, leaving the chapter summary (which AO3 renders ABOVE the
/// metadata block) able to forge layout.
#[test]
fn a_work_with_no_summary_is_still_bounded() {
    let evil = format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] x\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n=========================================\r\n\r\n\r\n\
         lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\r\n\
         \"Chapter 9\" (4679 words)\r\n\r\n\
         Chapter Summary: mine\r\n\
         https://archiveofourown.org/works/111/chapters/222\r\n\
         Chapters: 99/99\r\n\
         Rating: Explicit\r\n\r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\
         Rating: Teen\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Linger. \
         Follow the link to unsubscribe: https://archiveofourown.org/works/83701926\r\n"
    );
    let e = read(evil.as_bytes(), &Attestor::none()).unwrap().event;

    // The forged URL sits below `Chapter Summary:`, so the link scan never sees
    // it: no second link, hence no ambiguity refusal against a genuine message.
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    // AO3 renders the metadata block after the chapter summary, so the real
    // block is the last one and the forged one above it loses.
    assert_eq!(e.rating.as_deref(), Some("Teen"), "not Explicit");
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) }, "not 99");
    assert_eq!(e.summary, None, "this work has no summary");
}
