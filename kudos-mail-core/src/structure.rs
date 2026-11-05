//! Locating the parts of AO3's notification, from its template rather than by
//! searching the body for phrases.
//!
//! The template is `app/views/user_mailer/batch_subscription_notification.text.erb`
//! inside the layout `app/views/layouts/mailer.text.erb` (otwarchive master,
//! read 2026-11-05). Its shape, for one creation:
//!
//! ```text
//! Archive of Our Own
//! =========================================
//!
//! <creators> posted a new chapter of "<work title>" (N words):   <- preface, ends in ':'
//! https://archiveofourown.org/works/<id>/chapters/<id>            <- the only trusted link
//!
//! "<chapter title>" (M words)
//! by <creators>                                                   <- only if pseuds differ
//!
//! Chapter Summary: <author text>                                  <- author-controlled
//!
//! Chapters: 9/13                                                  <- _work_info starts here
//! Fandom: …
//! Rating: …
//! Warning: …
//!
//! Summary: 
//!     <author text>                                               <- author-controlled
//!
//! --------------------                                            <- between creations only
//! …
//! -----------------------------------------                       <- layout rule, 41 hyphens
//! You're receiving this email because you've subscribed to <name>. Follow the link…
//! ```
//!
//! Everything an AO3 author can type — titles, summaries, pseuds — lands inside a
//! genuine signed message, so position in this structure is the only thing that
//! separates AO3's words from theirs.

/// A notification split into the regions the template defines.
pub(crate) struct Layout<'a> {
    /// Creations, in order. A batch mail has several; the first is the subject.
    pub creations: Vec<&'a str>,
    /// Everything below the layout's hyphen rule. AO3's words only.
    pub footer: &'a str,
}

/// The layout rule is 41 hyphens; the batch divider is 20. Anything at least
/// this long is treated as the rule.
const RULE_MIN: usize = 30;
/// The batch divider, exactly.
const DIVIDER: usize = 20;

/// Byte offset just past the layout's `=====` rule, if present.
fn equals_rule(body: &str) -> Option<usize> {
    let mut offset = 0usize;
    for line in body.split_inclusive('\n') {
        let t = line.trim();
        if t.len() >= 8 && t.bytes().all(|b| b == b'=') {
            return Some(offset + line.len());
        }
        offset += line.len();
    }
    None
}

fn hyphen_run(line: &str) -> Option<usize> {
    let t = line.trim();
    (!t.is_empty() && t.bytes().all(|b| b == b'-')).then_some(t.len())
}

impl<'a> Layout<'a> {
    pub(crate) fn of(body: &'a str) -> Self {
        // The footer is below the LAST long rule. An author can print hyphens in
        // a summary, but only above AO3's own, so taking the last is safe where
        // taking the first was not.
        let (body, _) = match equals_rule(body) {
            // The layout opens with "Archive of Our Own" over a rule of '='.
            // Everything above it is chrome, and the preface is the first thing
            // after it — so it has to go before any line is read as AO3's.
            Some(end) => (body.get(end..).unwrap_or(""), ()),
            None => (body, ()),
        };

        let mut rule_at = None;
        let mut offset = 0usize;
        for line in body.split_inclusive('\n') {
            if hyphen_run(line).is_some_and(|n| n >= RULE_MIN) {
                rule_at = Some((offset, offset + line.len()));
            }
            offset += line.len();
        }

        let (message, footer) = match rule_at {
            Some((start, end)) => (
                body.get(..start).unwrap_or(""),
                body.get(end..).unwrap_or(""),
            ),
            None => (body, ""),
        };

        // Creations are separated by a line of exactly 20 hyphens.
        let mut creations = Vec::new();
        let mut current_start = 0usize;
        let mut offset = 0usize;
        for line in message.split_inclusive('\n') {
            if hyphen_run(line) == Some(DIVIDER) {
                if let Some(piece) = message.get(current_start..offset) {
                    creations.push(piece);
                }
                current_start = offset + line.len();
            }
            offset += line.len();
        }
        if let Some(piece) = message.get(current_start..) {
            creations.push(piece);
        }
        Self { creations, footer }
    }
}

/// What AO3's preface says happened. These are the only six, from
/// `config/locales/mailers/en.yml` under
/// `batch_subscription_notification.preface`.
pub(crate) struct Preface<'a> {
    pub kind: PrefaceKind,
    /// `%{creators}`, or `None` when the creation is anonymous.
    pub creators: Option<&'a str>,
    /// Byte offset just past the preface, where the URL line begins.
    pub ends_at: usize,
}

#[derive(PartialEq, Eq, Clone, Copy, Debug)]
pub(crate) enum PrefaceKind {
    NewChapter,
    NewWork,
    BackdatedWork,
}

const PHRASES: [(&str, PrefaceKind); 3] = [
    ("posted a new chapter of ", PrefaceKind::NewChapter),
    ("posted a new work:", PrefaceKind::NewWork),
    ("posted a backdated work:", PrefaceKind::BackdatedWork),
];

impl<'a> Preface<'a> {
    /// Read the preface of one creation region.
    ///
    /// The preface may wrap onto further lines, because a work title may contain
    /// a newline and the title is interpolated into it. Every preface ends with a
    /// colon, so the preface is everything up to the first line ending in one —
    /// which is what keeps a URL smuggled into a title from being read as the
    /// link line.
    pub(crate) fn of(creation: &'a str) -> Option<Self> {
        let mut offset = 0usize;
        let mut found: Option<(PrefaceKind, &str)> = None;
        for line in creation.split_inclusive('\n') {
            if found.is_none() {
                for (phrase, kind) in PHRASES {
                    if let Some(at) = line.find(phrase) {
                        found = Some((kind, line.get(..at).unwrap_or("")));
                        break;
                    }
                }
                // A phrase must appear in the first non-empty line of the region,
                // or it is somebody's prose rather than AO3's preface.
                if found.is_none() && !line.trim().is_empty() {
                    return None;
                }
            }
            offset += line.len();
            if let Some((kind, head)) = found {
                if line.trim_end().ends_with(':') {
                    let creators = head.trim();
                    return Some(Self {
                        kind,
                        creators: (!creators.is_empty() && creators != "Anonymous")
                            .then_some(creators),
                        ends_at: offset,
                    });
                }
            }
        }
        None
    }
}
