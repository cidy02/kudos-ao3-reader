//! Reads AO3 subscription notifications out of a mailbox, and nothing else.
//!
//! The point of this crate being a crate is containment. The host apps get
//! [`Ao3Event`] values and no type that can hold a mail message, so "Kudos reads
//! only AO3's notifications" is a property of the boundary rather than a rule
//! anyone has to remember. Raw mail is parsed here and dropped here.
//!
//! [`read`] is the only way in, and it gates before it parses. The parser is
//! deliberately not public: an earlier shape exposed it alongside the gate, so
//! the containment claim rested on callers remembering to check first.
//!
//! Three defences, in order:
//!
//! 1. the IMAP `SEARCH` is scoped to AO3's sender, so the server never returns
//!    anything else and nothing else is ever downloaded;
//! 2. [`gate`] re-checks the sender and, where a provider attested the message,
//!    that DKIM passed for AO3's domain;
//! 3. [`parser`] treats every field as hostile — including fields a legitimate
//!    AO3 author controls, which arrive inside correctly signed mail.
//!
//! `unsafe` is forbidden crate-wide. Note that `panic = "abort"` turns a panic
//! into a process abort rather than undefined behaviour across the FFI boundary;
//! it does not prevent the crash, so unbounded work is still a denial of service
//! and is bounded explicitly instead.

#![forbid(unsafe_code)]

pub mod gate;
pub mod parser;

pub use gate::{Attestor, Verdict};
pub use parser::{Ao3Event, Ao3EventKind, ParseError, Subscription};

use mail_parser::MessageParser;

/// One notification, with how far its provenance could be established.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reading {
    pub event: Ao3Event,
    /// [`Verdict::Trusted`] only when a provider attested DKIM for AO3's domain.
    /// A watched folder yields [`Verdict::SenderOnly`]: the sender looks right
    /// and nothing more, which the caller must not present as verified.
    pub verdict: Verdict,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum ReadError {
    /// The gate refused it. Not AO3's, or attested as failing.
    #[error("message was refused by the gate")]
    Refused,
    #[error(transparent)]
    Parse(#[from] ParseError),
}

/// Read one message. Gates first, then parses; there is no way to do only the
/// second.
pub fn read(raw: &[u8], attestor: &Attestor) -> Result<Reading, ReadError> {
    if raw.len() > parser::MAX_MESSAGE_BYTES {
        return Err(ReadError::Parse(ParseError::TooLarge));
    }
    let message = MessageParser::default()
        .parse(raw)
        .ok_or(ReadError::Parse(ParseError::NotMail))?;

    let verdict = gate::check(&message, attestor);
    if verdict == Verdict::Rejected {
        return Err(ReadError::Refused);
    }
    let event = parser::parse_message(&message)?;
    Ok(Reading { event, verdict })
}
