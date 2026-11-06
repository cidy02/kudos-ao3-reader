//! Fifth review pass. Every body below was supplied with its finding; each test
//! asserts AO3's real values, so a failing test *is* the finding.
//!
//! The through-line: for a CHAPTER notification AO3 interpolates the work title
//! into the preface, which is printed ABOVE the URL. A title may contain
//! newlines, so author text can appear above AO3's own link line — which is
//! what made "bounding the scan here never loses the work link" false.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, Subscription};

fn mail(message: &str) -> Vec<u8> {
    format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] x\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\
         \r\n\
         Archive of Our Own\r\n\
         =========================================\r\n\r\n\r\n\
         {message}\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Linger. \
         Follow the link to unsubscribe if you no longer wish to receive updates: \
         https://archiveofourown.org/works/83701926\r\n\r\n\
         If you don't understand why you received this email, please contact \
         Support: https://archiveofourown.org/support.\r\n\r\n\
         The Archive of Our Own is a fan-run and fan-supported archive that relies on \
         your donations: https://www.transformativeworks.org/donate.\r\n"
    )
    .into_bytes()
}

fn event(raw: &[u8]) -> Ao3Event {
    read(raw, &Attestor::none()).expect("notification").event
}

#[test]
fn title_url_before_chapter_summary_keeps_ao3s_ids() {
    let body = "\
lamplighter posted a new chapter of \"Decoy\r\n\
https://archiveofourown.org/works/111/chapters/222\r\n\
Chapter Summary: x\r\n\
\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Rating: Teen And Up Audiences\r\n\
\r\n\
Summary:\r\n\
    real summary";
    let e = event(&mail(body));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(
        e.via,
        Subscription::Work { id: 83_701_926, name: Some("Linger".into()) }
    );
    // AO3's block is identified by carrying a fandom, which every work has and
    // all six real messages print. This body omits it, so the metadata is not
    // recovered — it degrades to nothing rather than to the author's values.
    // `real_metadata_is_recovered_when_the_block_carries_a_fandom` covers the
    // same attack against a block shaped like AO3's.
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: None });
    assert_eq!(e.rating, None);
}

/// The same attack as above against a metadata block of AO3's real shape: the
/// genuine chapter index and rating come back, still attached to AO3's ids.
#[test]
fn real_metadata_is_recovered_when_the_block_carries_a_fandom() {
    let body = "\
lamplighter posted a new chapter of \"Decoy\r\n\
https://archiveofourown.org/works/111/chapters/222\r\n\
Chapter Summary: x\r\n\
\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n\
\r\n\
Summary:\r\n\
    real summary";
    let e = event(&mail(body));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(e.rating.as_deref(), Some("Teen And Up Audiences"));
    assert_eq!(e.summary.as_deref(), Some("real summary"));
    assert_eq!(e.work_title, "Decoy\r\nhttps://archiveofourown.org/works/111/chapters/222\r\nChapter Summary: x\r\n");
}

#[test]
fn divider_inside_the_title_does_not_replace_the_work() {
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
Rating: Teen And Up Audiences\r\n";
    let e = event(&mail(body));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    // The forged divider still splits the region, so the fragment it creates is
    // counted. Identity — which work and which chapter — is what had to be
    // right; an over-count of creations shows the reader "1 more" that is not
    // there, which is cosmetic and self-inflicted.
    assert_eq!(e.extra_creations, 1);
}

#[test]
fn chapter_summary_cannot_replace_the_metadata_block() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapter Summary: x\r\n\
Chapters: 1/1\r\n\
Rating: Explicit\r\n\
Summary:\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n\
\r\n\
Summary:\r\n\
    the real work summary";
    let e = event(&mail(body));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    // A label occurring twice in one creation means two candidates for the same
    // field, and a multiline FANDOM value — fandom being mandatory — can inject
    // one into AO3's own run, where no election separates them. So the field is
    // dropped rather than chosen between: a wrong rating is worse than none.
    // Identity is what had to survive, and does.
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: None });
    assert_eq!(e.rating, None);
    assert_eq!(e.summary, None);
}

#[test]
fn series_title_cannot_start_a_later_chapters_run() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n\
Series: Part 1 of Nice\r\n\
\r\n\
Chapters: 1/1\r\n\
Rating: Explicit\r\n\
\r\n\
Summary:\r\n\
    the real work summary";
    let e = event(&mail(body));
    // A label occurring twice in one creation means two candidates for the same
    // field, and a multiline FANDOM value — fandom being mandatory — can inject
    // one into AO3's own run, where no election separates them. So the field is
    // dropped rather than chosen between: a wrong rating is worse than none.
    // Identity is what had to survive, and does.
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: None });
    assert_eq!(e.rating, None);
    assert_eq!(e.chapters_posted, None);
    assert_eq!(e.summary.as_deref(), Some("the real work summary"), "one Summary: here");
}

#[test]
fn title_phrase_does_not_flip_kind_or_author() {
    let body = "\
lamplighter posted a new chapter of \"x posted a new work:\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Rating: Teen\r\n";
    let e = event(&mail(body));
    // No fandom in this block either, so the index is not recovered; the kind
    // is what the finding was about, and it is no longer flipped to NewWork.
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: None });
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.work_title, "x posted a new work:");
    assert_eq!(e.author, "lamplighter");
    assert_eq!(e.words, Some(34_920));
    assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9"));
    assert_eq!(e.chapter_words, Some(4_679));
}

#[test]
fn chapter_title_word_count_is_ao3s_closer() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Fake\" (1 words)\r\n\
Rest of the real title\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Rating: Teen\r\n";
    let e = event(&mail(body));
    assert_eq!(e.chapter_words, Some(4_679));
    assert_eq!(
        e.chapter_title.as_deref(),
        Some("Fake\" (1 words)\r\nRest of the real title")
    );
    assert_eq!(e.words, Some(34_920));
}
