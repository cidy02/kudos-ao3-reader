//! Seventh review pass. Bodies supplied with the findings; assertions are
//! AO3's real values, so a failure is the finding.
//!
//! Two themes. The work-id anchor only helps when it picks AO3's own link, so
//! an author or series subscription — which has no anchor — and a work
//! subscription pointed at another chapter of the same work both still move.
//! And one finding is not an attack at all: AO3's word count is pluralised, so
//! `(1 word):` is a shape every anchor here was requiring away.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, Subscription};

fn mail(message: &str, unsub: &str) -> Vec<u8> {
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
         {unsub}\r\n"
    )
    .into_bytes()
}

fn event(raw: &[u8]) -> Ao3Event {
    read(raw, &Attestor::none()).expect("notification").event
}

/// 1 (High). No footer anchor exists for an author subscription, and the
/// positional scan took the FIRST preface candidate — so a title holding a
/// closer and a URL above AO3's own won, and AO3's genuine metadata was then
/// attached to the attacker's ids.
#[test]
fn author_subscription_keeps_ao3s_work() {
    let body = "\
lamplighter posted a new chapter of \"Decoy\" (1 words):\r\n\
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
    let e = event(&mail(body, "https://archiveofourown.org/users/subscriber"));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.words, Some(34_920));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(
        e.via,
        Subscription::Author { username: "subscriber".into(), name: Some("Linger".into()) }
    );
}

/// 2 (High). The work id matches, so the anchor is satisfied — but a leading
/// fragment with its own `Fandom:` line became the chosen region, moving the
/// chapter id, the index and the rating.
#[test]
fn work_subscription_keeps_ao3s_chapter() {
    let body = "\
lamplighter posted a new chapter of \"Decoy\" (1 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/1\r\n\
Chapters: 1/1\r\n\
Fandom: Attacker\r\n\
Rating: Explicit\r\n\
--------------------\r\n\
ignored posted a new chapter of \"x\r\n\
\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n";
    let e = event(&mail(body, "https://archiveofourown.org/works/83701926"));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(e.rating.as_deref(), Some("Teen And Up Audiences"));
    assert_eq!(e.fandoms, vec!["Original Work".to_owned()]);
}

/// 3 (High). Two agreeing links inside that first fragment refused the WHOLE
/// message, so one author in a series batch could drop every other author's
/// work from it.
#[test]
fn series_batch_is_not_refused_by_the_first_title() {
    let body = "\
attacker posted a new chapter of \"Decoy\" (1 words):\r\n\
https://archiveofourown.org/works/111/chapters/222\r\n\
https://archiveofourown.org/works/111/chapters/333\r\n\
Chapters: 1/1\r\n\
Fandom: Attacker\r\n\
--------------------\r\n\
still going posted a new chapter of \"x\r\n\
\" (10 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Ch\" (5 words)\r\n\
\r\n\
Chapters: 2/2\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n\
\r\n\
--------------------\r\n\
otherauthor posted a new work:\r\n\
https://archiveofourown.org/works/999\r\n\
\r\n\
\"Theirs\" (100 words)\r\n\
\r\n\
Chapters: 1/1\r\n\
Fandom: Their Fandom\r\n\
Rating: General Audiences\r\n";
    let e = event(&mail(body, "https://archiveofourown.org/series/55"));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
}

/// 4 (Medium). Even with the ids right, the link was paired with the EARLIEST
/// agreeing candidate, so the work title and its word count stopped at a closer
/// the author wrote.
#[test]
fn preface_word_count_is_ao3s() {
    let body = "\
lamplighter posted a new chapter of \"Fake\" (1 words):\r\n\
still the real title\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen And Up Audiences\r\n";
    let e = event(&mail(body, "https://archiveofourown.org/works/83701926"));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.words, Some(34_920));
    assert_eq!(e.work_title, "Fake\" (1 words):\r\nstill the real title");
}

/// 5 (Medium) — and not an attack. `mailer.general.creation.word_count.one` is
/// `"%{count} word"`, so every chapter notification for a ONE-WORD work ends
/// `(1 word):`. The terminator, the title bound and the closer scan all
/// required the plural, so the whole message was rejected.
#[test]
fn one_word_chapter_preface_parses() {
    let body = "\
lamplighter posted a new chapter of \"Hi\" (1 word):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 2\" (50 words)\r\n\
\r\n\
Chapters: 2/2\r\n\
Fandom: Original Work\r\n\
Rating: General Audiences\r\n";
    let e = event(&mail(body, "https://archiveofourown.org/works/83701926"));
    assert_eq!(e.work_id, 83_701_926);
    assert_eq!(e.chapter_id, Some(255_464_091));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(2) });
    assert_eq!(e.words, Some(1));
}

/// 5b. A chapter whose own count is one word, on a longer work.
#[test]
fn a_one_word_chapter_title_is_still_read() {
    let body = "\
lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (1 word)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n";
    let e = event(&mail(body, "https://archiveofourown.org/works/83701926"));
    assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9"));
    assert_eq!(e.chapter_words, Some(1));
}

/// 6 (Low). A pseud cannot contain a terminator — `pseud.rb` allows only
/// `[\p{Word} -]+` — but a TITLE can contain the phrase, and taking its last
/// occurrence on the preface line read the author out of AO3's own sentence.
#[test]
fn a_phrase_inside_a_title_does_not_move_the_author() {
    let body = "\
lamplighter posted a new chapter of \"x posted a new chapter of Bob\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\
\r\n\
\"Chapter 9\" (4679 words)\r\n\
\r\n\
Chapters: 9/13\r\n\
Fandom: Original Work\r\n\
Rating: Teen\r\n";
    let e = event(&mail(body, "https://archiveofourown.org/works/83701926"));
    assert_eq!(e.author, "lamplighter");
    assert_eq!(e.work_title, "x posted a new chapter of Bob");
    assert_eq!(e.words, Some(34_920));
}
