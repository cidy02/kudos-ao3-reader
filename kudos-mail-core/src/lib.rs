//! Reads AO3 subscription notifications out of a mailbox, and nothing else.
//!
//! The point of this crate being a crate is containment. The host apps get
//! [`Ao3Event`] values and no type that can hold a mail message, so "Kudos reads
//! only AO3's notifications" is a property of the boundary rather than a rule
//! anyone has to remember. Raw mail is parsed here and dropped here.
//!
//! Three defences, in order:
//!
//! 1. the IMAP `SEARCH` is scoped to AO3's sender, so the server never returns
//!    anything else and nothing else is ever downloaded;
//! 2. [`gate`] re-checks the sender and, where a provider attested the message,
//!    that DKIM passed for AO3's domain;
//! 3. [`parser`] treats every field as hostile: ids must be digits, links must
//!    sit under AO3's own host, and every string is length-capped.
//!
//! `unsafe` is forbidden crate-wide and release builds abort rather than unwind,
//! so a panic can never cross into Swift or Kotlin as undefined behaviour.

#![forbid(unsafe_code)]

pub mod gate;
pub mod parser;

pub use gate::{Attestor, Verdict};
pub use parser::{Ao3Event, Ao3EventKind, ParseError, Subscription};
