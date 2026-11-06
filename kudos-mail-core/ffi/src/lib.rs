//! The whole foreign-language surface for `kudos-mail-core`.
//!
//! Nothing here accepts bytes or exposes the parser, gate, or a mail-message
//! type. Swift and Kotlin can only ask the read-only session for parsed events.
//! UniFFI's generated ABI code is isolated in this package so the core package
//! keeps its crate-wide `unsafe_code = "forbid"` invariant.

use std::sync::{Arc, OnceLock};

use kudos_mail_core as core;
use tokio::runtime::Runtime;
use tokio::sync::Mutex;
use zeroize::Zeroizing;

uniffi::setup_scaffolding!("kudos_mail_core");

type CoreMailbox = core::TlsMailbox;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum Ao3EventKind {
    /// The preface could not be told from an author's imitation of one, so
    /// what happened is not reported. The work id still is.
    Contested,
    NewChapter { number: Option<u32> },
    NewWork,
}

impl From<core::Ao3EventKind> for Ao3EventKind {
    fn from(value: core::Ao3EventKind) -> Self {
        match value {
            core::Ao3EventKind::Contested => Self::Contested,
            core::Ao3EventKind::NewChapter { number } => Self::NewChapter { number },
            core::Ao3EventKind::NewWork => Self::NewWork,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum Subscription {
    Work {
        id: u64,
        name: Option<String>,
    },
    Series {
        id: u64,
        name: Option<String>,
    },
    Author {
        username: String,
        name: Option<String>,
    },
    Unknown,
}

impl From<core::Subscription> for Subscription {
    fn from(value: core::Subscription) -> Self {
        match value {
            core::Subscription::Work { id, name } => Self::Work { id, name },
            core::Subscription::Series { id, name } => Self::Series { id, name },
            core::Subscription::Author { username, name } => Self::Author { username, name },
            core::Subscription::Unknown => Self::Unknown,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Identity {
    Work,
    Body,
}

impl From<core::Identity> for Identity {
    fn from(value: core::Identity) -> Self {
        match value {
            core::Identity::Work => Self::Work,
            core::Identity::Body => Self::Body,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Verdict {
    Trusted,
    SenderOnly,
    Rejected,
}

impl From<core::Verdict> for Verdict {
    fn from(value: core::Verdict) -> Self {
        match value {
            core::Verdict::Trusted => Self::Trusted,
            core::Verdict::SenderOnly => Self::SenderOnly,
            core::Verdict::Rejected => Self::Rejected,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Ao3Event {
    pub identity: Identity,
    pub kind: Ao3EventKind,
    pub at: i64,
    pub work_id: u64,
    pub chapter_id: Option<u64>,
    pub work_title: String,
    pub author: String,
    pub via: Subscription,
    pub chapters_posted: Option<u32>,
    pub chapters_total: Option<u32>,
    pub words: Option<u64>,
    pub chapter_title: Option<String>,
    pub chapter_words: Option<u64>,
    pub rating: Option<String>,
    pub warnings: Vec<String>,
    pub fandoms: Vec<String>,
    pub relationships: Vec<String>,
    pub characters: Vec<String>,
    pub additional_tags: Vec<String>,
    pub series: Option<String>,
    pub summary: Option<String>,
    pub extra_creations: u64,
}

impl From<core::Ao3Event> for Ao3Event {
    fn from(value: core::Ao3Event) -> Self {
        Self {
            identity: value.identity.into(),
            kind: value.kind.into(),
            at: value.at,
            work_id: value.work_id,
            chapter_id: value.chapter_id,
            work_title: value.work_title,
            author: value.author,
            via: value.via.into(),
            chapters_posted: value.chapters_posted,
            chapters_total: value.chapters_total,
            words: value.words,
            chapter_title: value.chapter_title,
            chapter_words: value.chapter_words,
            rating: value.rating,
            warnings: value.warnings,
            fandoms: value.fandoms,
            relationships: value.relationships,
            characters: value.characters,
            additional_tags: value.additional_tags,
            series: value.series,
            summary: value.summary,
            extra_creations: u64::try_from(value.extra_creations).unwrap_or(u64::MAX),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Reading {
    pub event: Ao3Event,
    pub verdict: Verdict,
}

impl From<core::Reading> for Reading {
    fn from(value: core::Reading) -> Self {
        Self {
            event: value.event.into(),
            verdict: value.verdict.into(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct Cursor {
    pub uid_validity: u32,
    pub last_uid: u32,
}

impl From<Cursor> for core::Cursor {
    fn from(value: Cursor) -> Self {
        Self {
            uid_validity: value.uid_validity,
            last_uid: value.last_uid,
        }
    }
}

impl From<core::Cursor> for Cursor {
    fn from(value: core::Cursor) -> Self {
        Self {
            uid_validity: value.uid_validity,
            last_uid: value.last_uid,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Harvest {
    pub readings: Vec<Reading>,
    pub cursor: Option<Cursor>,
    pub other_ao3_mail: u64,
    pub refused: u64,
    pub too_large: u64,
    pub more_waiting: bool,
}

impl From<core::Harvest> for Harvest {
    fn from(value: core::Harvest) -> Self {
        Self {
            readings: value.readings.into_iter().map(Into::into).collect(),
            cursor: value.cursor.map(Into::into),
            other_ao3_mail: u64::try_from(value.other_ao3_mail).unwrap_or(u64::MAX),
            refused: u64::try_from(value.refused).unwrap_or(u64::MAX),
            too_large: u64::try_from(value.too_large).unwrap_or(u64::MAX),
            more_waiting: value.more_waiting,
        }
    }
}

#[derive(Debug, thiserror::Error, PartialEq, Eq, uniffi::Error)]
pub enum MailError {
    #[error("could not reach the mail server")]
    Connect,
    #[error("the server name is not a valid hostname")]
    BadHost,
    #[error("the mail server rejected the sign-in")]
    SignIn,
    #[error("the mail server refused the {command} request")]
    Protocol { command: String },
    #[error("the mail server did not answer the {command} request in time")]
    TimedOut { command: String },
    #[error("the mail session is closed")]
    Closed,
    #[error("the mail runtime failed")]
    Internal,
}

impl From<core::MailError> for MailError {
    fn from(value: core::MailError) -> Self {
        match value {
            core::MailError::Connect => Self::Connect,
            core::MailError::BadHost => Self::BadHost,
            core::MailError::SignIn => Self::SignIn,
            core::MailError::Protocol(command) => Self::Protocol {
                command: command.to_owned(),
            },
            core::MailError::TimedOut(command) => Self::TimedOut {
                command: command.to_owned(),
            },
        }
    }
}

#[derive(uniffi::Object)]
pub struct Credentials {
    inner: core::Credentials,
}

#[uniffi::export]
impl Credentials {
    #[uniffi::constructor]
    pub fn new(host: String, port: u16, user: String, password: String) -> Arc<Self> {
        Arc::new(Self {
            inner: core::Credentials {
                host,
                port,
                user,
                password: Zeroizing::new(password),
            },
        })
    }
}

impl Credentials {
    fn core_copy(&self) -> core::Credentials {
        core::Credentials {
            host: self.inner.host.clone(),
            port: self.inner.port,
            user: self.inner.user.clone(),
            password: Zeroizing::new(self.inner.password.as_str().to_owned()),
        }
    }
}

#[derive(uniffi::Object)]
pub struct Mailbox {
    inner: Arc<Mutex<Option<CoreMailbox>>>,
}

#[uniffi::export]
pub async fn connect(credentials: Arc<Credentials>) -> Result<Arc<Mailbox>, MailError> {
    let credentials = credentials.core_copy();
    let mailbox = runtime()?
        .spawn(async move { CoreMailbox::connect(&credentials).await })
        .await
        .map_err(|_| MailError::Internal)??;
    Ok(Arc::new(Mailbox {
        inner: Arc::new(Mutex::new(Some(mailbox))),
    }))
}

#[uniffi::export]
impl Mailbox {
    /// Read new events. `authserv_id` is the provider hostname whose outermost
    /// Authentication-Results header may be believed; `None` yields SenderOnly.
    pub async fn read_new(
        &self,
        cursor: Option<Cursor>,
        authserv_id: Option<String>,
    ) -> Result<Harvest, MailError> {
        let inner = Arc::clone(&self.inner);
        runtime()?
            .spawn(async move {
                let attestor = authserv_id
                    .as_deref()
                    .map_or_else(core::Attestor::none, core::Attestor::provider);
                let mut mailbox = inner.lock().await;
                let mailbox = mailbox.as_mut().ok_or(MailError::Closed)?;
                mailbox
                    .read_new(cursor.map(Into::into), &attestor)
                    .await
                    .map(Into::into)
                    .map_err(Into::into)
            })
            .await
            .map_err(|_| MailError::Internal)?
    }

    /// Close is idempotent. The underlying session is removed before logout,
    /// so no later call can use a half-closed connection.
    pub async fn close(&self) -> Result<(), MailError> {
        let inner = Arc::clone(&self.inner);
        runtime()?
            .spawn(async move {
                if let Some(mailbox) = inner.lock().await.take() {
                    mailbox.close().await;
                }
            })
            .await
            .map_err(|_| MailError::Internal)
    }
}

fn runtime() -> Result<&'static Runtime, MailError> {
    static RUNTIME: OnceLock<Result<Runtime, ()>> = OnceLock::new();
    match RUNTIME.get_or_init(|| Runtime::new().map_err(|_| ())) {
        Ok(runtime) => Ok(runtime),
        Err(()) => Err(MailError::Internal),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uniffi::FfiConverter;

    #[test]
    fn event_round_trips_through_the_uniffi_converter() -> uniffi::Result<()> {
        let expected = Ao3Event {
            identity: Identity::Work,
            kind: Ao3EventKind::NewChapter { number: Some(9) },
            at: 1_798_072_191,
            work_id: 83_701_926,
            chapter_id: Some(255_464_091),
            work_title: "Linger".to_owned(),
            author: "lamplighter".to_owned(),
            via: Subscription::Work {
                id: 83_701_926,
                name: Some("Linger".to_owned()),
            },
            chapters_posted: Some(9),
            chapters_total: Some(13),
            words: Some(34_920),
            chapter_title: Some("Chapter 9".to_owned()),
            chapter_words: Some(4_679),
            rating: Some("Teen And Up Audiences".to_owned()),
            warnings: vec!["No Archive Warnings Apply".to_owned()],
            fandoms: vec!["Original Work".to_owned()],
            relationships: vec!["A/B".to_owned()],
            characters: vec!["A".to_owned(), "B".to_owned()],
            additional_tags: vec!["Mail".to_owned()],
            series: Some("Inbox".to_owned()),
            summary: Some("One parsed event, no message.".to_owned()),
            extra_creations: 1,
        };

        let lowered = <Ao3Event as FfiConverter<crate::UniFfiTag>>::lower(expected.clone());
        let actual = <Ao3Event as FfiConverter<crate::UniFfiTag>>::try_lift(lowered)?;

        assert_eq!(actual, expected);
        Ok(())
    }

    #[test]
    fn protocol_errors_cross_with_only_the_command() {
        assert_eq!(
            MailError::from(core::MailError::Protocol("FETCH")),
            MailError::Protocol {
                command: "FETCH".to_owned()
            }
        );
    }
}
