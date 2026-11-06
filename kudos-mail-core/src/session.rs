//! The IMAP session: the only code in this crate that talks to a server.
//!
//! This module is the crate's first line of defence. IMAP credentials open the
//! whole mailbox, so the promise cannot be that we ignore the rest — it has to
//! be that the rest is never asked for. Be precise about how far that reaches,
//! because the honest version is narrower than the slogan:
//!
//! * **What the server enforces.** Every run issues `UID SEARCH FROM
//!   "do-not-reply@archiveofourown.org"`, and only UIDs it returns are fetched.
//!   But IMAP's `FROM` is a **case-insensitive substring match on the From
//!   field**, not an address comparison (RFC 3501 §6.4.4). So a message headed
//!   `From: "do-not-reply@archiveofourown.org" <someone@evil.test>` matches the
//!   search, and its body does transfer before [`crate::gate`] rejects it on
//!   the exact address. AO3's own kudos, comment and abuse mail matches too, by
//!   design — it shares the sender.
//! * **What is therefore true.** Only messages whose From field contains AO3's
//!   notification address are ever requested; everything fetched is then
//!   checked exactly, locally, and anything else is dropped without reaching
//!   the host app. What is *not* true is that only AO3 subscription mail is
//!   ever transferred.
//!
//! Three further properties, each a deliberate choice rather than a default:
//!
//! 1. **The mailbox is opened with `EXAMINE`, not `SELECT`.** The session is
//!    read-only at the protocol level, so no code path here can delete a
//!    message, move one, or alter a flag, whatever it is asked to do.
//! 2. **Bodies are fetched with `BODY.PEEK[]`.** A plain `BODY[]` sets `\Seen`,
//!    which would silently mark the reader's own mail as read.
//! 3. **TLS is required.** Implicit TLS on connect, certificate and hostname
//!    verification against the webpki roots, no plaintext and no `STARTTLS`
//!    upgrade path, so there is no negotiation to strip.
//!
//! Known limits, written down rather than implied:
//!
//! * **Trace logging would leak.** `async-imap` formats `LOGIN "user" "pass"`
//!   into an ordinary `String` and trace-logs every request and response, so a
//!   host that installs a `log` sink at trace level will capture the password
//!   and raw message bodies. Nothing in this crate can prevent that; the host
//!   must not enable trace logging for `async_imap` in a release build.
//! * **The search phase is bounded by the dependency, not by us.**
//!   [`MAX_PER_RUN`] caps what is *fetched*; `uid_search` has already collected
//!   every matching UID into a set before we see them.
//! * **A server that reports no `UIDVALIDITY` cannot be resumed.** No cursor is
//!   returned, so each run restarts from the beginning. With more than
//!   [`MAX_PER_RUN`] matches such a mailbox never progresses past the first
//!   batch; [`Harvest::more_waiting`] is how the host notices.

use std::collections::HashSet;
use std::fmt::Debug;
use std::sync::Arc;
use std::time::Duration;

use async_imap::Session;
use futures::StreamExt;
use tokio::io::{AsyncRead as Read, AsyncWrite as Write};
use tokio::net::TcpStream;
use tokio::time::timeout;
use tokio_rustls::client::TlsStream;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::rustls::{ClientConfig, RootCertStore};
use tokio_rustls::TlsConnector;
use zeroize::Zeroizing;

/// AO3's only notification sender, shared with the gate rather than written
/// twice: the server-side `SEARCH` and the local re-check have to name the same
/// address, and two copies of a security constant are one edit from disagreeing.
use crate::gate::AO3_SENDER;
use crate::gate::Attestor;
use crate::{Reading, ReadError};

/// Messages fetched in one run. A first sync of a long-standing mailbox can
/// match thousands; it continues on the next run from the cursor rather than
/// holding them all at once.
const MAX_PER_RUN: usize = 200;

/// UIDs per `FETCH`. Keeps the command line short on servers that limit it.
const FETCH_CHUNK: usize = 25;

/// Per-phase deadlines. Without these a stalled link leaves a socket, a task
/// and a live copy of the password parked indefinitely, and on a phone that is
/// the difference between a slow sync and one that never ends.
const CONNECT_SECS: u64 = 10;
const GREETING_SECS: u64 = 10;
const SIGN_IN_SECS: u64 = 20;
const COMMAND_SECS: u64 = 30;
const FETCH_SECS: u64 = 60;
const LOGOUT_SECS: u64 = 5;

/// Where to connect and as whom.
///
/// The password is held in [`Zeroizing`] so our copy is wiped when dropped.
/// Note what that does not cover: `async-imap` makes its own `String` copy of
/// the whole `LOGIN` command line, which is not zeroized and lives until it is
/// dropped inside the dependency.
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
    /// Matched mail that is not a subscription notification — AO3's kudos,
    /// comment replies and abuse reports, which share the sender. Expected.
    pub other_ao3_mail: usize,
    /// Refused by the gate: matched the server's substring search but is not
    /// actually from AO3's address.
    pub refused: usize,
    /// Skipped because the server reported a size over the parser's cap, so no
    /// body was requested for it.
    pub too_large: usize,
    /// True when the run stopped at [`MAX_PER_RUN`] and more is waiting.
    pub more_waiting: bool,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum MailError {
    #[error("could not reach the mail server")]
    Connect,
    #[error("the server name is not a valid hostname")]
    BadHost,
    #[error("the mail server rejected the sign-in")]
    SignIn,
    /// Names the command only. The server's own text is deliberately dropped:
    /// `async-imap` embeds the offending bytes in its error, and for a `FETCH`
    /// those bytes are somebody's mail.
    #[error("the mail server refused the {0} request")]
    Protocol(&'static str),
    #[error("the mail server did not answer the {0} request in time")]
    TimedOut(&'static str),
}

/// A connected, signed-in, read-only session.
///
/// Generic over the stream so the protocol itself can be tested. [`connect`]
/// is the only way to build one over the network, and it is always TLS.
///
/// [`connect`]: Mailbox::connect
pub struct Mailbox<T: Read + Write + Unpin + Debug + Send> {
    session: Session<T>,
}

/// The only `Mailbox` production code builds: TLS over TCP.
///
/// Named here so callers — the UniFFI boundary above all — need not spell out
/// the transport types. `Mailbox` is generic purely so the protocol can be
/// driven against a mock stream in tests; that genericity is an internal
/// testing affordance, not something a host app should have to know about.
pub type TlsMailbox = Mailbox<TlsStream<TcpStream>>;

impl Mailbox<TlsStream<TcpStream>> {
    /// Connect over TLS and sign in.
    ///
    /// There is no plaintext path and no `STARTTLS`: the socket is wrapped
    /// before a byte is written, so a network attacker has no cleartext
    /// negotiation to tamper with. The hostname used to verify the certificate
    /// is the same one the TCP connection was made to.
    pub async fn connect(creds: &Credentials) -> Result<Self, MailError> {
        let roots = RootCertStore {
            roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
        };
        let config = ClientConfig::builder()
            .with_root_certificates(roots)
            .with_no_client_auth();
        let name = ServerName::try_from(creds.host.clone()).map_err(|_| MailError::BadHost)?;

        let tcp = timeout(
            Duration::from_secs(CONNECT_SECS),
            TcpStream::connect((creds.host.as_str(), creds.port)),
        )
        .await
        .map_err(|_| MailError::TimedOut("connect"))?
        .map_err(|_| MailError::Connect)?;

        let tls = timeout(
            Duration::from_secs(CONNECT_SECS),
            TlsConnector::from(Arc::new(config)).connect(name, tcp),
        )
        .await
        .map_err(|_| MailError::TimedOut("TLS"))?
        .map_err(|_| MailError::Connect)?;

        Self::sign_in(tls, &creds.user, &creds.password).await
    }
}

impl<T: Read + Write + Unpin + Debug + Send> Mailbox<T> {
    /// Consume the server greeting, then sign in.
    ///
    /// The greeting is not optional politeness: `async-imap` requires it to be
    /// read before authenticating. Sending `LOGIN` first left an untagged `* OK`
    /// to be swallowed by the login loop, which also meant a server answering
    /// `* BYE` — refusing the connection outright — was reported as a rejected
    /// sign-in rather than as an unreachable server.
    pub(crate) async fn sign_in(stream: T, user: &str, password: &str) -> Result<Self, MailError> {
        let mut client = async_imap::Client::new(stream);
        let greeting = timeout(Duration::from_secs(GREETING_SECS), client.read_response())
            .await
            .map_err(|_| MailError::TimedOut("greeting"))?
            .map_err(|_| MailError::Connect)?
            .ok_or(MailError::Connect)?;
        // `* BYE` is the server refusing the connection outright — too many
        // connections, a blocked address, maintenance. Reporting that as a
        // rejected sign-in sent the user to check a password that is fine.
        if matches!(
            greeting.parsed(),
            async_imap::imap_proto::Response::Data { status: async_imap::imap_proto::Status::Bye, .. }
        ) {
            return Err(MailError::Connect);
        }

        // The error half carries the server's text, which can quote the command
        // it rejected — and that command is `LOGIN`. Dropped rather than
        // reported, so a password cannot reach a log through an error message.
        let session = timeout(
            Duration::from_secs(SIGN_IN_SECS),
            client.login(user, password),
        )
        .await
        .map_err(|_| MailError::TimedOut("sign-in"))?
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
        let mailbox = timeout(
            Duration::from_secs(COMMAND_SECS),
            self.session.examine("INBOX"),
        )
        .await
        .map_err(|_| MailError::TimedOut("EXAMINE"))?
        .map_err(|_| MailError::Protocol("EXAMINE"))?;
        let uid_validity = mailbox.uid_validity;

        // A cursor only means anything within the generation that produced it.
        // When it is discarded the high-water mark must be discarded with it:
        // carrying the old `last_uid` forward wrote it back under the NEW
        // validity, which silently skipped every message below it, possibly for
        // years.
        let resume = resume_from(cursor, uid_validity);
        let mut highest = resume.map_or(0, |(_, floor)| floor);
        let Some((from_uid, _)) = resume else {
            // `last_uid` is already `u32::MAX`: there is no newer UID to ask
            // for, and `UID MAX:*` would hand us that same message again on
            // every run.
            return Ok(Harvest {
                cursor: uid_validity.map(|v| Cursor { uid_validity: v, last_uid: u32::MAX }),
                ..Harvest::default()
            });
        };

        // The one place the mailbox is narrowed, and it is narrowed on the
        // server. Note the module docs: IMAP `FROM` is a substring match, so
        // this bounds what is transferred but does not establish the sender.
        let query = format!("FROM \"{AO3_SENDER}\" UID {from_uid}:*");
        let matched: HashSet<u32> = timeout(
            Duration::from_secs(COMMAND_SECS),
            self.session.uid_search(&query),
        )
        .await
        .map_err(|_| MailError::TimedOut("SEARCH"))?
        .map_err(|_| MailError::Protocol("SEARCH"))?;

        // `UID n:*` always returns at least one message on a non-empty mailbox,
        // so anything below the cursor is that artefact, not new mail.
        let mut uids: Vec<u32> = matched.into_iter().filter(|u| *u >= from_uid).collect();
        uids.sort_unstable();
        let mut harvest = Harvest {
            more_waiting: uids.len() > MAX_PER_RUN,
            ..Harvest::default()
        };
        uids.truncate(MAX_PER_RUN);

        for chunk in uids.chunks(FETCH_CHUNK) {
            let wanted: HashSet<u32> = chunk.iter().copied().collect();

            // Sizes first, in their own round trip. Asking for the size and the
            // body together made the size check pointless: the literal had
            // already been received and buffered by the time it was read.
            let sizes = self.fetch(chunk, "(UID RFC822.SIZE)", &wanted).await?;
            let mut acceptable = Vec::new();
            for (uid, size, _) in &sizes {
                if size.is_some_and(|n| n as usize > crate::parser::MAX_MESSAGE_BYTES) {
                    harvest.too_large += 1;
                    highest = highest.max(*uid);
                } else {
                    acceptable.push(*uid);
                }
            }
            if acceptable.is_empty() {
                continue;
            }

            // PEEK, so the reader's unread state is not touched. The allow-list
            // is what passed the size check, not the whole chunk: otherwise a
            // server could volunteer a body for a UID already counted
            // `too_large` and have it parsed anyway.
            let allowed: HashSet<u32> = acceptable.iter().copied().collect();
            let bodies = self
                .fetch(&acceptable, "(UID BODY.PEEK[])", &allowed)
                .await?;
            for (uid, _, body) in bodies {
                let Some(raw) = body else { continue };
                highest = highest.max(uid);
                match crate::read(&raw, attestor) {
                    Ok(reading) => harvest.readings.push(reading),
                    // AO3's kudos, comment replies and abuse reports.
                    Err(ReadError::Parse(_)) => harvest.other_ao3_mail += 1,
                    // Matched the substring search but is not AO3's address.
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

    /// One `UID FETCH`, keeping only responses for UIDs we actually asked for.
    ///
    /// A server may legitimately send `FETCH` responses for other messages, and
    /// `async-imap` forwards every one of them. Trusting them to set the
    /// high-water mark let a single unrequested response carrying a high UID
    /// skip every genuine message between it and the cursor.
    async fn fetch(
        &mut self,
        uids: &[u32],
        query: &str,
        wanted: &HashSet<u32>,
    ) -> Result<Vec<(u32, Option<u32>, Option<Vec<u8>>)>, MailError> {
        let set = uids.iter().map(u32::to_string).collect::<Vec<_>>().join(",");
        let mut stream = timeout(
            Duration::from_secs(COMMAND_SECS),
            self.session.uid_fetch(&set, query),
        )
        .await
        .map_err(|_| MailError::TimedOut("FETCH"))?
        .map_err(|_| MailError::Protocol("FETCH"))?;

        let mut out = Vec::new();
        while let Some(item) = timeout(Duration::from_secs(FETCH_SECS), stream.next())
            .await
            .map_err(|_| MailError::TimedOut("FETCH"))?
        {
            let fetch = item.map_err(|_| MailError::Protocol("FETCH"))?;
            let Some(uid) = fetch.uid else { continue };
            if !wanted.contains(&uid) {
                continue;
            }
            out.push((uid, fetch.size, fetch.body().map(<[u8]>::to_vec)));
        }
        Ok(out)
    }

    /// Say goodbye properly, so the server does not hold the connection open.
    pub async fn close(mut self) {
        let _ = timeout(Duration::from_secs(LOGOUT_SECS), self.session.logout()).await;
    }
}

/// Where to resume, and the high-water mark to carry forward.
///
/// `None` means the stored cursor has already reached `u32::MAX` and there is
/// nothing newer to ask for. `Some((from, floor))` gives the first UID to
/// search from and the mark to start the new cursor at — zero whenever the
/// stored cursor does not belong to this mailbox generation.
fn resume_from(cursor: Option<Cursor>, uid_validity: Option<u32>) -> Option<(u32, u32)> {
    match (cursor, uid_validity) {
        (Some(c), Some(v)) if c.uid_validity == v => {
            (c.last_uid != u32::MAX).then(|| (c.last_uid + 1, c.last_uid))
        }
        _ => Some((1, 0)),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::panic, clippy::indexing_slicing)]
mod tests {
    use super::*;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::net::TcpListener;

    /// A rebuilt mailbox reuses UIDs for different messages, so a cursor from
    /// another generation must not be honoured — and its UID must not be
    /// written back under the new generation either.
    #[test]
    fn a_changed_uid_validity_discards_the_mark_as_well_as_the_floor() {
        let c = Cursor { uid_validity: 7, last_uid: 900 };
        assert_eq!(resume_from(Some(c), Some(7)), Some((901, 900)));
        // Different generation: start over AND forget 900, or UIDs 1..900 of
        // the new mailbox are skipped.
        assert_eq!(resume_from(Some(c), Some(8)), Some((1, 0)));
        assert_eq!(resume_from(Some(c), None), Some((1, 0)));
        assert_eq!(resume_from(None, Some(7)), Some((1, 0)));
        // Exhausted: nothing newer exists, so do not search and do not
        // redeliver UID MAX on every run.
        let last = Cursor { uid_validity: 7, last_uid: u32::MAX };
        assert_eq!(resume_from(Some(last), Some(7)), None);
    }

    /// A password must not be reachable through `Debug` or `Display`, and a
    /// protocol error must not carry the server's bytes — for a `FETCH` those
    /// bytes are somebody's mail.
    #[test]
    fn errors_carry_neither_credentials_nor_content() {
        assert_eq!(MailError::SignIn.to_string(), "the mail server rejected the sign-in");
        let e = MailError::Protocol("FETCH");
        assert_eq!(e.to_string(), "the mail server refused the FETCH request");
        assert!(!format!("{e:?}").contains("Subject"));
    }

    /// Everything above is arithmetic. This drives the real `read_new` against
    /// a server that records what was actually asked for, because the privacy
    /// claim is about the wire and nothing else can check it.
    #[tokio::test]
    async fn the_wire_is_scoped_read_only_and_peeking() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move { serve_one(listener).await });

        let stream = TcpStream::connect(addr).await.unwrap();
        let mut mailbox = Mailbox::sign_in(stream, "reader@example.com", "secret")
            .await
            .unwrap();
        let harvest = mailbox
            .read_new(Some(Cursor { uid_validity: 7, last_uid: 9 }), &Attestor::none())
            .await
            .unwrap();
        // LOGOUT also ends the mock's read loop, so the join below terminates.
        mailbox.close().await;
        let log = server.await.unwrap();

        // The mailbox is opened read-only, and never selected for writing.
        assert!(log.iter().any(|c| c.contains("EXAMINE \"INBOX\"")), "{log:?}");
        assert!(!log.iter().any(|c| c.contains("SELECT ")), "{log:?}");
        // The search is scoped to AO3's sender and resumes after the cursor.
        assert!(
            log.iter().any(|c| c.contains(
                "UID SEARCH FROM \"do-not-reply@archiveofourown.org\" UID 10:*"
            )),
            "{log:?}"
        );
        // Sizes are asked for in their own round trip, before any body.
        let size_at = log.iter().position(|c| c.contains("RFC822.SIZE")).unwrap();
        let body_at = log.iter().position(|c| c.contains("BODY.PEEK[]")).unwrap();
        assert!(size_at < body_at, "size must be known before a body is asked for: {log:?}");
        // Peek, never a plain BODY[], which would set \Seen on the reader's mail.
        assert!(!log.iter().any(|c| c.contains("BODY[]") && !c.contains("PEEK")), "{log:?}");
        // UID 11 was over the cap, so no body was ever requested for it.
        assert!(!log.iter().any(|c| c.contains("FETCH 11 ")), "{log:?}");

        assert_eq!(harvest.too_large, 1);
        assert_eq!(harvest.readings.len(), 1);
        assert_eq!(harvest.cursor, Some(Cursor { uid_validity: 7, last_uid: 11 }));
    }

    const BODY: &str = "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
         Subject: [AO3] x\r\n\
         Content-Type: text/plain; charset=UTF-8\r\n\r\n\
         Archive of Our Own\r\n=========================================\r\n\r\n\r\n\
         lamplighter posted a new chapter of \"Linger\" (34920 words):\r\n\
         https://archiveofourown.org/works/83701926/chapters/255464091\r\n\r\n\
         \"Chapter 9\" (4679 words)\r\n\r\n\
         Chapters: 9/13\r\n\
         Fandom: Original Work\r\n\r\n\
         -----------------------------------------\r\n\
         You're receiving this email because you've subscribed to Linger. \
         Follow the link to unsubscribe: https://archiveofourown.org/works/83701926\r\n";

    /// A mock IMAP server: answers by command keyword, echoes the client's tag,
    /// and returns every command line it was sent. It also replies to the size
    /// fetch with an unrequested UID 9999, which must not move the cursor.
    async fn serve_one(listener: TcpListener) -> Vec<String> {
        let (socket, _) = listener.accept().await.unwrap();
        let (rx, mut tx) = socket.into_split();
        let mut lines = BufReader::new(rx).lines();
        let mut log = Vec::new();

        tx.write_all(b"* OK IMAP4rev1 ready\r\n").await.unwrap();
        while let Ok(Ok(Some(line))) =
            tokio::time::timeout(Duration::from_secs(10), lines.next_line()).await
        {
            log.push(line.clone());
            let tag = line.split_whitespace().next().unwrap_or("x").to_owned();
            let upper = line.to_uppercase();
            let reply = if upper.contains("LOGIN") {
                format!("{tag} OK LOGIN completed\r\n")
            } else if upper.contains("EXAMINE") {
                format!(
                    "* 3 EXISTS\r\n* OK [UIDVALIDITY 7] Ok\r\n\
                     * OK [UIDNEXT 12] Ok\r\n{tag} OK [READ-ONLY] EXAMINE completed\r\n"
                )
            } else if upper.contains("SEARCH") {
                format!("* SEARCH 10 11\r\n{tag} OK SEARCH completed\r\n")
            } else if upper.contains("RFC822.SIZE") {
                // UID 11 is over the 1 MiB cap; 9999 was never requested.
                format!(
                    "* 1 FETCH (UID 10 RFC822.SIZE {})\r\n\
                     * 2 FETCH (UID 11 RFC822.SIZE 99999999)\r\n\
                     * 3 FETCH (UID 9999 RFC822.SIZE 10)\r\n\
                     {tag} OK FETCH completed\r\n",
                    BODY.len()
                )
            } else if upper.contains("BODY.PEEK") {
                format!(
                    "* 1 FETCH (UID 10 BODY[] {{{}}}\r\n{BODY})\r\n{tag} OK FETCH completed\r\n",
                    BODY.len()
                )
            } else if upper.contains("LOGOUT") {
                format!("* BYE\r\n{tag} OK LOGOUT completed\r\n")
            } else {
                format!("{tag} OK done\r\n")
            };
            tx.write_all(reply.as_bytes()).await.unwrap();
            if upper.contains("LOGOUT") {
                break;
            }
        }
        log
    }
}
