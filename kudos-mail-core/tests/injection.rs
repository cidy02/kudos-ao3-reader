//! An exhaustive injection matrix over every author-controlled slot.
//!
//! Ten review passes all found the same shape of defect: put hostile text in a
//! slot an AO3 author controls, see whether a trusted field moves. There are
//! only seven such slots and a small vocabulary of payloads, so the whole space
//! is enumerable — which no reviewer will do by hand, and which costs nothing
//! to re-run on every change.
//!
//! The invariants below are what the crate actually promises. Each is asserted
//! for every (slot, payload) pair and for every pair of pairs, so a defect is
//! reported as the exact combination that produced it rather than as prose.
//!
//! The baseline is AO3's measured rendering: creators with their pseud URL, the
//! `_work_info` field order, pluralised labels. If the baseline stops being
//! faithful the whole matrix stops meaning anything, so it is asserted first.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Ao3Event, Ao3EventKind, Attestor, Identity, ReadError};

/// AO3's real ids for the message being forged against.
const WORK: u64 = 83_701_926;
const CHAPTER: u64 = 255_464_091;
/// Ids that appear ONLY inside payloads. Seeing either in a parsed event is a
/// defect by definition — no genuine field can produce them.
const DECOY_WORK: u64 = 111;
const DECOY_CHAPTER: u64 = 222;

const CREATOR: &str =
    "skydarius11 (https://archiveofourown.org/users/skydarius11/pseuds/skydarius11)";

/// The seven slots AO3 interpolates author text into.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Slot {
    WorkTitle,
    ChapterTitle,
    ChapterSummary,
    Summary,
    Fandom,
    Series,
    Pseud,
}

const SLOTS: [Slot; 7] = [
    Slot::WorkTitle,
    Slot::ChapterTitle,
    Slot::ChapterSummary,
    Slot::Summary,
    Slot::Fandom,
    Slot::Series,
    Slot::Pseud,
];

/// Every shape that has ever moved a boundary in this parser, plus the pieces
/// they are built from. `to_plain_text` turns `<p>` markup into column-zero
/// lines, so a multi-line payload is what ordinary markup renders as.
const PAYLOADS: [&str; 18] = [
    // Inert control: nothing should change except the slot itself.
    "ordinary text",
    // Quotes and counts — AO3's own closer shapes.
    "q\" (1 word)",
    "q\" (1 words):",
    "(1 word):",
    "\" (34920 words):",
    // Links, both schemes and both forms.
    "\nhttps://archiveofourown.org/works/111/chapters/222\n",
    "\nhttp://archiveofourown.org/works/111/chapters/222\n",
    "\nhttps://archiveofourown.org/works/111\n",
    "\nhttps://archiveofourown.org/works/83701926/chapters/222\n",
    // Preface phrases and terminators.
    "\nposted a new work:\n",
    "\nposted a backdated work:\n",
    "x posted a new chapter of y",
    // Layout rules.
    "\n--------------------\n",
    "\n-----------------------------------------\n",
    // Labels, including the mandatory ones and the summary anchor.
    "\nChapters: 99/99\n",
    "\nRating: Explicit\n",
    "\nFandom: Forged\n",
    "\nSummary:\n    INJECTED SUMMARY\n",
];

/// One message in AO3's rendering, with `payload` substituted into `slot`.
fn message(slots: &[(Slot, &str)], unsub: &str) -> Vec<u8> {
    let get = |s: Slot, default: &str| -> String {
        slots
            .iter()
            .find(|(k, _)| *k == s)
            .map_or_else(|| default.to_owned(), |(_, v)| (*v).to_owned())
    };
    let pseud = get(Slot::Pseud, CREATOR);
    let body = format!(
        "{pseud} posted a new chapter of \"{work_title}\" (576402 words):\r\n\
         https://archiveofourown.org/works/{WORK}/chapters/{CHAPTER}\r\n\
         \r\n\
         \"{chapter_title}\" (4679 words)\r\n\
         \r\n\
         Chapter Summary: {chapter_summary}\r\n\
         \r\n\
         Chapters: 9/13\r\n\
         Fandom: {fandom}\r\n\
         Rating: Teen And Up Audiences\r\n\
         Warning: No Archive Warnings Apply\r\n\
         Series: Part 1 of {series}\r\n\
         \r\n\
         Summary:\r\n\
         \x20   {summary}",
        work_title = get(Slot::WorkTitle, "Honest Work"),
        chapter_title = get(Slot::ChapterTitle, "Chapter 9"),
        chapter_summary = get(Slot::ChapterSummary, "a chapter summary"),
        fandom = get(Slot::Fandom, "Original Work"),
        series = get(Slot::Series, "A Series"),
        summary = get(Slot::Summary, "the real work summary"),
    );
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
         Follow the link to unsubscribe: https://archiveofourown.org/{unsub}\r\n"
    )
    .into_bytes()
}

/// What must hold however the slots are filled.
///
/// Returns the reason it failed, so the caller can name the combination.
fn check(e: &Ao3Event, where_: &str) -> Result<(), String> {
    if e.identity == Identity::Work && e.work_id != WORK {
        return Err(format!("{where_}: Identity::Work but work_id = {}", e.work_id));
    }
    if e.work_id == DECOY_WORK {
        return Err(format!("{where_}: work_id is the decoy {DECOY_WORK}"));
    }
    if e.chapter_id == Some(DECOY_CHAPTER) {
        return Err(format!("{where_}: chapter_id is the decoy {DECOY_CHAPTER}"));
    }
    if !matches!(e.chapter_id, None | Some(CHAPTER)) {
        return Err(format!("{where_}: chapter_id = {:?}", e.chapter_id));
    }
    // A field is AO3's value or absent. Never a payload's.
    if !matches!(e.rating.as_deref(), None | Some("Teen And Up Audiences")) {
        return Err(format!("{where_}: rating = {:?}", e.rating));
    }
    if !matches!(e.chapters_posted, None | Some(9)) {
        return Err(format!("{where_}: chapters_posted = {:?}", e.chapters_posted));
    }
    if !matches!(e.chapters_total, None | Some(13)) {
        return Err(format!("{where_}: chapters_total = {:?}", e.chapters_total));
    }
    // `Contested` is a safe third outcome, like a refusal: the preface could not
    // be told from an author's imitation of one, so nothing read from it is
    // reported. What must then hold is that it really is empty — a half-filled
    // contested event would be worse than either answer.
    if e.kind == Ao3EventKind::Contested {
        if !e.work_title.is_empty()
            || e.words.is_some()
            || e.chapter_id.is_some()
            || e.chapter_title.is_some()
            || !e.author.is_empty()
        {
            return Err(format!("{where_}: contested but still reporting preface fields"));
        }
        return Ok(());
    }
    if !matches!(e.kind, Ao3EventKind::NewChapter { .. }) {
        return Err(format!("{where_}: kind = {:?}, a chapter notification", e.kind));
    }
    Ok(())
}

fn parse(raw: &[u8]) -> Option<Ao3Event> {
    match read(raw, &Attestor::none()) {
        Ok(r) => Some(r.event),
        // A refusal is always acceptable: it shows nothing wrong to the reader.
        Err(ReadError::Parse(_) | ReadError::Refused) => None,
    }
}

/// The matrix is meaningless if the un-injected baseline is not read correctly.
#[test]
fn the_baseline_is_faithful() {
    let e = parse(&message(&[], &format!("works/{WORK}"))).expect("baseline must parse");
    assert_eq!(e.identity, Identity::Work);
    assert_eq!(e.work_id, WORK);
    assert_eq!(e.chapter_id, Some(CHAPTER));
    assert_eq!(e.kind, Ao3EventKind::NewChapter { number: Some(9) });
    assert_eq!(e.work_title, "Honest Work");
    assert_eq!(e.words, Some(576_402));
    assert_eq!(e.author, "skydarius11");
    assert_eq!(e.rating.as_deref(), Some("Teen And Up Audiences"));
    assert_eq!(e.chapter_title.as_deref(), Some("Chapter 9"));
    assert_eq!(e.summary.as_deref(), Some("the real work summary"));
    assert_eq!(e.fandoms, vec!["Original Work".to_owned()]);
    check(&e, "baseline").expect("baseline must satisfy its own invariants");
}

/// One payload in one slot: 7 x 18 = 126 messages.
#[test]
fn no_single_injection_moves_a_trusted_field() {
    let unsub = format!("works/{WORK}");
    let mut failures = Vec::new();
    for slot in SLOTS {
        for payload in PAYLOADS {
            let raw = message(&[(slot, payload)], &unsub);
            if let Some(e) = parse(&raw) {
                if let Err(why) = check(&e, &format!("{slot:?} <- {payload:?}")) {
                    failures.push(why);
                }
            }
        }
    }
    assert!(failures.is_empty(), "{} failures:\n{}", failures.len(), failures.join("\n"));
}

/// Two payloads in two different slots: the combinations a reviewer never
/// enumerates, and where several real findings actually lived — a terminator in
/// one slot plus a link in another.
#[test]
fn no_pair_of_injections_moves_a_trusted_field() {
    let unsub = format!("works/{WORK}");
    let mut failures = Vec::new();
    let mut checked = 0usize;
    for (i, a) in SLOTS.iter().enumerate() {
        for b in SLOTS.iter().skip(i + 1) {
            for pa in PAYLOADS {
                for pb in PAYLOADS {
                    checked += 1;
                    let raw = message(&[(*a, pa), (*b, pb)], &unsub);
                    if let Some(e) = parse(&raw) {
                        let at = format!("{a:?} <- {pa:?} + {b:?} <- {pb:?}");
                        if let Err(why) = check(&e, &at) {
                            failures.push(why);
                        }
                    }
                }
            }
        }
    }
    assert!(checked > 6_000, "the matrix shrank to {checked}");
    assert!(
        failures.is_empty(),
        "{} of {checked} combinations failed; first 20:\n{}",
        failures.len(),
        failures.iter().take(20).cloned().collect::<Vec<_>>().join("\n")
    );
}

/// With an author subscription there is no footer anchor, so the work id is not
/// pinned — that is `Identity::Body` and it is documented. Everything else must
/// still hold, and the event must never claim to be anchored.
#[test]
fn an_author_subscription_never_claims_to_be_anchored() {
    let mut failures = Vec::new();
    for slot in SLOTS {
        for payload in PAYLOADS {
            let raw = message(&[(slot, payload)], "users/subscriber");
            if let Some(e) = parse(&raw) {
                if e.identity != Identity::Body {
                    failures.push(format!(
                        "{slot:?} <- {payload:?}: identity {:?} on an author subscription",
                        e.identity
                    ));
                }
                if !matches!(e.rating.as_deref(), None | Some("Teen And Up Audiences")) {
                    failures.push(format!("{slot:?} <- {payload:?}: rating {:?}", e.rating));
                }
            }
        }
    }
    assert!(failures.is_empty(), "{} failures:\n{}", failures.len(), failures.join("\n"));
}

/// Nothing in the matrix may take unreasonable time; the message cap bounds the
/// input, not the work done on it.
#[test]
fn the_whole_matrix_runs_quickly() {
    let started = std::time::Instant::now();
    let unsub = format!("works/{WORK}");
    for slot in SLOTS {
        for payload in PAYLOADS {
            let _ = parse(&message(&[(slot, payload)], &unsub));
        }
    }
    let elapsed = started.elapsed();
    assert!(elapsed.as_secs() < 5, "126 messages took {elapsed:?}");
}
