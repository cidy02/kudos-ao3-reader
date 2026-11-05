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

use kudos_mail_core::{gate, parser};
use mail_parser::MessageParser;

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

        let message = MessageParser::default()
            .parse(&raw)
            .unwrap_or_else(|| panic!("{} did not parse as mail", path.display()));

        let verdict = gate::check(&message, &attestor);
        assert_ne!(
            verdict,
            gate::Verdict::Rejected,
            "{} is real AO3 mail and must not be rejected",
            path.display()
        );
        admitted += 1;

        match parser::parse_message(&message) {
            Ok(event) => {
                events += 1;
                // Identity must survive, whatever else is missing.
                assert!(event.work_id > 0, "{} parsed without a work id", path.display());
                assert!(!event.work_title.is_empty(), "{} has no title", path.display());
                assert!(event.at > 0, "{} has no timestamp", path.display());
            }
            // Kudos, comment replies and abuse reports share the sender.
            Err(parser::ParseError::NotASubscriptionEvent) => not_events += 1,
            Err(e) => panic!("{} failed to parse: {e}", path.display()),
        }
    }

    eprintln!(
        "{seen} file(s): {admitted} admitted by the gate, \
         {events} subscription event(s), {not_events} non-event(s)"
    );
    assert!(seen > 0, "no .eml files found in {dir}");
}
