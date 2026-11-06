//! Runs the gate and parser over a directory of real `.eml` files.
//!
//! Real notification mail carries a reader's address and their whole reading
//! history, so none is committed and this repository holds no sample. The test
//! skips unless you point it at a directory yourself:
//!
//! ```sh
//! KUDOS_REAL_MAIL_DIR=/path/to/eml cargo test --test real_mail -- --nocapture
//! ```
//!
//! It asserts only on shape — that the gate admits AO3 mail, that every message
//! is either a subscription event or a recognised non-event, and that nothing
//! panics. It never prints message content.

// A test harness may panic: that is how it reports.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use kudos_mail_core::{gate, parser, read, ReadError};

#[test]
fn every_real_message_is_handled_without_panicking() {
    let Ok(dir) = std::env::var("KUDOS_REAL_MAIL_DIR") else {
        eprintln!("skipped: set KUDOS_REAL_MAIL_DIR to a directory of .eml files");
        return;
    };
    let entries = std::fs::read_dir(&dir).expect("the directory should be readable");

    let (mut seen, mut admitted, mut events, mut not_events) = (0, 0, 0, 0);
    let attestor = gate::Attestor::provider("mx.google.com");

    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("eml") {
            continue;
        }
        let raw = std::fs::read(&path).expect("the file should be readable");
        seen += 1;

        match read(&raw, &attestor) {
            Ok(reading) => {
                admitted += 1;
                events += 1;
                let event = reading.event;
                // Identity must survive, whatever else is missing.
                assert!(event.work_id > 0, "{} parsed without a work id", path.display());
                assert!(!event.work_title.is_empty(), "{} has no title", path.display());
                assert!(event.at > 0, "{} has no timestamp", path.display());
                // The subscription's kind and id come from AO3's unsubscribe
                // URL; printed so a template change shows up as wrong identity
                // rather than as a silently plausible guess.
                assert_ne!(
                    event.via,
                    kudos_mail_core::Subscription::Unknown,
                    "{} has no readable unsubscribe link",
                    path.display()
                );
                eprintln!("  {} -> {:?}", path.file_name().unwrap_or_default().to_string_lossy(), event.via);
                eprintln!("     summary: {:?}", event.summary.as_deref().map(|s| (s.lines().count(), s.len())));
                eprintln!("     tags: f={} r={} c={} t={}", event.fandoms.len(), event.relationships.len(), event.characters.len(), event.additional_tags.len());
            }
            // Kudos, comment replies and abuse reports share the sender.
            Err(ReadError::Parse(parser::ParseError::NotASubscriptionEvent)) => {
                admitted += 1;
                not_events += 1;
            }
            Err(ReadError::Refused) => {
                panic!("{} is real AO3 mail and must not be refused", path.display())
            }
            Err(e) => panic!("{} failed to parse: {e}", path.display()),
        }
    }

    eprintln!(
        "{seen} file(s): {admitted} admitted by the gate, \
         {events} subscription event(s), {not_events} non-event(s)"
    );
    assert!(seen > 0, "no .eml files found in {dir}");
}
