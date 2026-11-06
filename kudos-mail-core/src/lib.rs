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
//! Only the second of those authenticates anything, and only when a provider
//! attested the message. Be plain about what the weaker tier is worth: a `From`
//! address is trivially forged, so [`Verdict::SenderOnly`] means *this claims to
//! be from AO3* and nothing more. Such a message still reaches the full MIME
//! parser. The third defence is therefore not depth behind authentication, it is
//! the only thing standing between unauthenticated input and the host app, which
//! is why the parser refuses ambiguity instead of guessing and why `panic =
//! "abort"` with bounded work is not optional here.
//!
//! `unsafe` is forbidden crate-wide. Note that `panic = "abort"` turns a panic
//! into a process abort rather than undefined behaviour across the FFI boundary;
//! it does not prevent the crash, so unbounded work is still a denial of service
//! and is bounded explicitly instead.

#![forbid(unsafe_code)]

pub mod gate;
pub mod parser;
pub mod session;
mod structure;

pub use gate::{Attestor, Verdict};
pub use parser::{Ao3Event, Ao3EventKind, ParseError, Subscription};
pub use session::{Credentials, Cursor, Harvest, MailError, Mailbox};

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

/// Headers we will look at. AO3's run well under this; the limit exists so the
/// gate's own work is bounded before anything larger is considered.
const MAX_HEADER_BYTES: usize = 64 * 1024;

/// Read one message: gate first, then parse. There is no way to do only the second.
///
/// The gate runs against the **header block alone**, before the MIME parser is
/// shown the body. That ordering is load-bearing rather than tidy: MIME boundary
/// scanning is quadratic in the worst case, so a crafted multipart under the byte
/// cap could burn the CPU of a message that was going to be refused anyway. The
/// body is only parsed once the sender has been established.
pub fn read(raw: &[u8], attestor: &Attestor) -> Result<Reading, ReadError> {
    if raw.len() > parser::MAX_MESSAGE_BYTES {
        return Err(ReadError::Parse(ParseError::TooLarge));
    }
    let headers_only = header_block(raw).ok_or(ReadError::Parse(ParseError::NotMail))?;
    let header_message = MessageParser::default()
        .parse(headers_only)
        .ok_or(ReadError::Parse(ParseError::NotMail))?;

    let verdict = gate::check(&header_message, attestor);
    if verdict == Verdict::Rejected {
        return Err(ReadError::Refused);
    }
    drop(header_message);

    let message = MessageParser::default()
        .parse(raw)
        .ok_or(ReadError::Parse(ParseError::NotMail))?;
    // The sender is re-established on the fully parsed message: the header block
    // we gated on is a prefix, and we do not assume the two agree.
    if gate::check(&message, attestor) != verdict {
        return Err(ReadError::Refused);
    }
    let event = parser::parse_message(&message)?;
    Ok(Reading { event, verdict })
}

/// The header block, up to and including the blank line that ends it.
fn header_block(raw: &[u8]) -> Option<&[u8]> {
    let limit = raw.len().min(MAX_HEADER_BYTES);
    let window = raw.get(..limit)?;
    for (i, w) in window.windows(4).enumerate() {
        if w == b"\r\n\r\n" {
            return raw.get(..i + 4);
        }
    }
    for (i, w) in window.windows(2).enumerate() {
        if w == b"\n\n" {
            return raw.get(..i + 2);
        }
    }
    // No body at all: headers may run to the end, if they fit the cap.
    (raw.len() <= MAX_HEADER_BYTES).then_some(raw)
}
