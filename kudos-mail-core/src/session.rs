//! The IMAP session: the only code in this crate that talks to a server.
//!
//! This module is the first of the crate's three defences — the one that makes
//! "Kudos reads only AO3's notifications" true of the network rather than of our
//! intentions. IMAP credentials open the whole mailbox, so the promise cannot be
//! that we ignore the rest; it has to be that the rest is never asked for.
//!
//! Four properties, each a deliberate choice rather than a default:
//!
//! 1. **The server does the filtering.** Every run issues `UID SEARCH FROM
//!    "do-not-reply@archiveofourown.org"`, and only UIDs it returns are ever
//!    fetched. A message from anyone else is not skipped after downloading — it
//!    is never named, never transferred, and never present in this process.
//! 2. **The mailbox is opened with `EXAMINE`, not `SELECT`.** The session is
//!    read-only at the protocol level, so no code path here can delete a
//!    message, move one, or alter a flag, whatever it is asked to do.
//! 3. **Bodies are fetched with `BODY.PEEK[]`.** A plain `BODY[]` sets `\Seen`,
//!    which would silently mark the reader's own mail as read. Peeking leaves
//!    their unread state exactly as they left it.
//! 4. **TLS is required.** Implicit TLS on connect, certificate verification
//!    against the webpki roots, no plaintext and no `STARTTLS` upgrade path, so
//!    there is no negotiation to strip.
//!
//! What this module does *not* defend against: the user's own IMAP server. They
//! gave it their password, and it can lie — report a small `RFC822.SIZE` and
//! then send a large literal, which `async-imap` does not cap. The server is
//! inside the trust boundary; the *mail* is not, and that is what [`crate::read`]
//! treats as hostile.

use std::collections::HashSet;
use std::sync::Arc;

use async_imap::Session;
use futures::StreamExt;
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::rustls::{ClientConfig, RootCertStore};
use tokio_rustls::TlsConnector;
use zeroize::Zeroizing;

use crate::gate::Attestor;
use crate::{Reading, ReadError};

/// AO3's only notification sender, shared with the gate rather than written
/// twice: the server-side `SEARCH` and the local re-check have to name the same
/// address, and two copies of a security constant are one edit from disagreeing.
use crate::gate::AO3_SENDER;

/// Messages fetched in one run. A first sync of a long-standing mailbox can
/// match thousands; it continues on the next run from the cursor rather than
/// holding them all at once.
const MAX_PER_RUN: usize = 200;

/// UIDs per `FETCH`. Keeps the command line short on servers that limit it.
const FETCH_CHUNK: usize = 25;

/// Where to connect and as whom.
///
/// The password is held in [`Zeroizing`] so it is wiped when dropped rather than
/// left in freed memory. It is never logged, and never formatted into an error:
/// [`MailError`] carries no credential field for that reason.
pub struct Credentials {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub password: Zeroizing<String>,
}

/// How far a mailbox has been read, to be stored by the host app and handed back
/// on the next run.
///
/// `uid_validity` is the mailbox's own generation number. If the server reports
/// a different one, every stored UID means a different message than it did, so
/// the cursor is discarded rather than trusted — the alternative is silently
/// skipping real mail or re-reading old mail as new.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cursor {
    pub uid_validity: u32,
    pub last_uid: u32,
}

/// One run's result.
#[derive(Debug, Default)]
pub struct Harvest {
    pub readings: Vec<Reading>,
    /// Where to resume. `None` when the server reported no `UIDVALIDITY`, in
    /// which case nothing may be stored: resuming from a UID without it is how
    /// a mailbox gets silently misread after a rebuild.
    pub cursor: Option<Cursor>,
    /// Matched AO3 mail that is not a subscription notification — kudos,
    /// comment replies, abuse reports. Expected, not an error.
    pub other_ao3_mail: usize,
    /// Refused by the gate despite matching the sender search.
    pub refused: usize,
    /// Skipped on reported size before any body was transferred.
    pub too_large: usize,
    /// True when the run stopped at [`MAX_PER_RUN`] and more is waiting.
    pub more_waiting: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum MailError {
    #[error("could not reach the mail server")]
    Connect(#[source] std::io::Error),
    #[error("the server name is not a valid hostname")]
    BadHost,
    #[error("the mail server rejected the sign-in")]
    SignIn,
    #[error("the mail server refused a request: {0}")]
    Protocol(String),
}

/// A connected, signed-in, read-only session.
pub struct Mailbox {
    session: Session<TlsStream<TcpStream>>,
}

impl Mailbox {
    /// Connect over TLS and sign in.
    ///
    /// There is no plaintext path and no `STARTTLS`: the socket is wrapped
    /// before a byte is written, so a network attacker has no cleartext
    /// negotiation to tamper with.
    pub async fn connect(creds: &Credentials) -> Result<Self, MailError> {
        let roots = RootCertStore {
            roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
        };
        let config = ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth();
        let name = ServerName::try_from(creds.host.clone()).map_err(|_| MailError::BadHost)?;

        let tcp = TcpStream::connect((creds.host.as_str(), creds.port))
            .await
            .map_err(MailError::Connect)?;
        let tls = TlsConnector::from(Arc::new(config))
            .connect(name, tcp)
            .await
            .map_err(MailError::Connect)?;

        let client = async_imap::Client::new(tls);
        // The error half carries the server's text, which can quote the command
        // it rejected — and that command is `LOGIN`. Dropped rather than
        // reported, so a password cannot reach a log through an error message.
        let session = client
            .login(&creds.user, creds.password.as_str())
            .await
            .map_err(|_| MailError::SignIn)?;
        Ok(Self { session })
    }

    /// Read AO3's notifications that arrived after `cursor`.
    ///
    /// `attestor` names the provider whose `Authentication-Results` header may
    /// be believed; see [`Attestor`]. Pass [`Attestor::none`] when the mailbox's
    /// provider is unknown — the readings then carry
    /// [`crate::Verdict::SenderOnly`] and must not be shown as verified.
    pub async fn read_new(
        &mut self,
        cursor: Option<Cursor>,
        attestor: &Attestor,
    ) -> Result<Harvest, MailError> {
        let mailbox = self
            .session
            .examine("INBOX")
            .await
            .map_err(|e| MailError::Protocol(e.to_string()))?;
        let uid_validity = mailbox.uid_validity;

        // A cursor only means anything within the generation that produced it.
        let from_uid = match (cursor, uid_validity) {
            (Some(c), Some(v)) if c.uid_validity == v => c.last_uid.saturating_add(1),
            _ => 1,
        };

        // The one place the mailbox is narrowed, and it is narrowed on the
        // server: only UIDs this returns are ever fetched.
        let query = format!("FROM \"{AO3_SENDER}\" UID {from_uid}:*");
        let matched: HashSet<u32> = self
            .session
            .uid_search(&query)
            .await
            .map_err(|e| MailError::Protocol(e.to_string()))?;

        // `UID n:*` always returns at least one message on a non-empty mailbox,
        // so anything at or below the cursor is that artefact, not new mail.
        let mut uids: Vec<u32> = matched.into_iter().filter(|u| *u >= from_uid).collect();
        uids.sort_unstable();
        let mut harvest = Harvest {
            more_waiting: uids.len() > MAX_PER_RUN,
            ..Harvest::default()
        };
        uids.truncate(MAX_PER_RUN);

        let mut highest = cursor.map_or(0, |c| c.last_uid);
        for chunk in uids.chunks(FETCH_CHUNK) {
            let set = chunk.iter().map(u32::to_string).collect::<Vec<_>>().join(",");
            // PEEK, so the reader's unread state is not touched. RFC822.SIZE
            // comes back with it so an implausible message can be dropped
            // without being decoded.
            let mut stream = self
                .session
                .uid_fetch(&set, "(UID RFC822.SIZE BODY.PEEK[])")
                .await
                .map_err(|e| MailError::Protocol(e.to_string()))?;

            while let Some(item) = stream.next().await {
                let fetch = item.map_err(|e| MailError::Protocol(e.to_string()))?;
                let Some(uid) = fetch.uid else { continue };
                highest = highest.max(uid);

                if fetch.size.is_some_and(|n| n as usize > crate::parser::MAX_MESSAGE_BYTES) {
                    harvest.too_large += 1;
                    continue;
                }
                let Some(raw) = fetch.body() else { continue };

                match crate::read(raw, attestor) {
                    Ok(reading) => harvest.readings.push(reading),
                    // Kudos, comment replies and abuse reports share the sender.
                    Err(ReadError::Parse(_)) => harvest.other_ao3_mail += 1,
                    Err(ReadError::Refused) => harvest.refused += 1,
                }
            }
        }

        harvest.cursor = uid_validity.map(|uid_validity| Cursor {
            uid_validity,
            last_uid: highest,
        });
        Ok(harvest)
    }

    /// Say goodbye properly, so the server does not hold the connection open.
    pub async fn close(mut self) {
        let _ = self.session.logout().await;
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    /// The search string is the whole of defence one, so its shape is pinned.
    /// A missing `FROM` term, or quotes in the wrong place, would widen the
    /// fetch to the reader's entire mailbox without failing anything else.
    #[test]
    fn the_search_names_ao3_and_the_cursor() {
        let q = format!("FROM \"{AO3_SENDER}\" UID {}:*", 42);
        assert_eq!(q, "FROM \"do-not-reply@archiveofourown.org\" UID 42:*");
    }

    /// A rebuilt mailbox reuses UIDs for different messages, so a cursor from
    /// another generation must not be honoured.
    #[test]
    fn a_changed_uid_validity_restarts_from_the_beginning() {
        let resume = |c: Option<Cursor>, v: Option<u32>| match (c, v) {
            (Some(c), Some(v)) if c.uid_validity == v => c.last_uid.saturating_add(1),
            _ => 1,
        };
        let c = Cursor { uid_validity: 7, last_uid: 90 };
        assert_eq!(resume(Some(c), Some(7)), 91);
        assert_eq!(resume(Some(c), Some(8)), 1);
        assert_eq!(resume(Some(c), None), 1);
        assert_eq!(resume(None, Some(7)), 1);
        // u32::MAX must not wrap round to zero and re-read the whole mailbox.
        let last = Cursor { uid_validity: 7, last_uid: u32::MAX };
        assert_eq!(resume(Some(last), Some(7)), u32::MAX);
    }

    /// A password must not be reachable through `Debug` or a `Display` error.
    #[test]
    fn errors_carry_no_credentials() {
        let e = MailError::SignIn;
        assert_eq!(e.to_string(), "the mail server rejected the sign-in");
        assert!(!format!("{e:?}").contains("hunter2"));
    }
}
