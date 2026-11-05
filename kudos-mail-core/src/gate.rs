//! The gate: decides whether a message is allowed to reach the parser at all.
//!
//! Two independent checks, because neither is sufficient alone:
//!
//! * the **sender** must be AO3's one notification address. A `From` header is
//!   trivially forged, so this alone proves nothing — but it is what the IMAP
//!   `SEARCH` is scoped to, so it keeps anything else from being fetched.
//! * where the receiving provider attested the message, its verdict must say
//!   DKIM passed **for `archiveofourown.org`**. Only the topmost
//!   `Authentication-Results` whose `authserv-id` is the host we are connected
//!   to counts: a sender can put as many forged ones below it as they like.
//!
//! Measured against a real mailbox (2026-11-05): 273 of 273 AO3 messages carry
//! `From: do-not-reply@archiveofourown.org`, DKIM `d=archiveofourown.org`, and
//! `spf=pass dkim=pass dmarc=pass`. A probe on `SUBJECT "[AO3]"` instead matched
//! six Reddit notifications that merely mention AO3 — which is why subject text
//! is never part of this decision.

use mail_parser::Message;
#[cfg(test)]
use mail_parser::MessageParser;

/// AO3's only notification sender, as observed over two years of mail.
pub const AO3_SENDER: &str = "do-not-reply@archiveofourown.org";

/// The domain a DKIM signature must cover for us to call a message attested.
pub const AO3_DKIM_DOMAIN: &str = "archiveofourown.org";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// Sender matches and the provider attested DKIM for AO3's domain.
    Trusted,
    /// Sender matches, but nobody attested it — a file in a watched folder, say.
    /// Usable, but the caller must not present it as verified.
    SenderOnly,
    /// Not AO3's, or attested as failing. Never parsed.
    Rejected,
}

/// Which `Authentication-Results` headers we are willing to believe.
///
/// A message carries every `Authentication-Results` header any hop chose to add,
/// and a sender can embed forgeries. Only the one stamped by the server we are
/// actually talking to means anything, so the caller passes that hostname in.
#[derive(Debug, Clone)]
pub struct Attestor {
    authserv_id: Option<String>,
}

impl Attestor {
    /// Trust `Authentication-Results` whose authserv-id matches this host.
    pub fn provider(authserv_id: &str) -> Self {
        Self { authserv_id: Some(authserv_id.trim().to_ascii_lowercase()) }
    }

    /// Trust nobody's attestation — for mail read out of a folder, where no
    /// provider stamped anything and the headers are just bytes in a file.
    pub fn none() -> Self {
        Self { authserv_id: None }
    }
}

/// Decide whether `message` may be parsed.
pub fn check(message: &Message<'_>, attestor: &Attestor) -> Verdict {
    if !sender_is_ao3(message) {
        return Verdict::Rejected;
    }
    let Some(expected) = attestor.authserv_id.as_deref() else {
        return Verdict::SenderOnly;
    };
    match topmost_attestation(message, expected) {
        Some(true) => Verdict::Trusted,
        // The provider looked and said no. That is worse than not knowing.
        Some(false) => Verdict::Rejected,
        None => Verdict::SenderOnly,
    }
}

/// True when every `From` address is AO3's notification address.
///
/// Every, not any: a message listing AO3 alongside another sender is not AO3's.
fn sender_is_ao3(message: &Message<'_>) -> bool {
    let Some(from) = message.from() else { return false };
    let mut saw_one = false;
    for addr in from.iter() {
        let Some(a) = addr.address() else { return false };
        if !a.trim().eq_ignore_ascii_case(AO3_SENDER) {
            return false;
        }
        saw_one = true;
    }
    saw_one
}

/// `Some(true)`/`Some(false)` when the named authserv stamped a verdict,
/// `None` when it did not stamp one at all.
///
/// Headers are read in the order they appear, which is the order they were
/// prepended — so the first match is the outermost, and the only one the
/// sender could not have written.
fn topmost_attestation(message: &Message<'_>, expected_authserv: &str) -> Option<bool> {
    for header in message.headers() {
        if !header.name().eq_ignore_ascii_case("Authentication-Results") {
            continue;
        }
        let raw = header.value().as_text()?;
        let (authserv, rest) = split_authserv(raw)?;
        if !authserv.eq_ignore_ascii_case(expected_authserv) {
            // Somebody else's verdict, or a forgery. Keep looking outward.
            continue;
        }
        return Some(dkim_passes_for_ao3(rest));
    }
    None
}

/// `mx.google.com; spf=pass …` → `("mx.google.com", "spf=pass …")`
fn split_authserv(raw: &str) -> Option<(&str, &str)> {
    let (head, rest) = raw.split_once(';')?;
    // An authserv-id may carry a version token: "mx.google.com 1".
    let authserv = head.split_whitespace().next()?;
    Some((authserv, rest))
}

/// True only for `dkim=pass` whose own `header.d`/`d=` is AO3's domain.
///
/// A message can legitimately carry several DKIM results — one for AO3 and one
/// for a list that relayed it. We need AO3's specifically to have passed, so a
/// `dkim=pass` for some other domain is not enough.
fn dkim_passes_for_ao3(results: &str) -> bool {
    for clause in results.split(';') {
        let clause = clause.trim();
        let Some(rest) = strip_ci_prefix(clause, "dkim=") else { continue };
        let outcome = rest.split_whitespace().next().unwrap_or("");
        if !outcome.eq_ignore_ascii_case("pass") {
            continue;
        }
        if clause_domain(clause).is_some_and(|d| d.eq_ignore_ascii_case(AO3_DKIM_DOMAIN)) {
            return true;
        }
    }
    false
}

/// The signing domain named inside one result clause.
///
/// Gmail writes DKIM identity as `header.i=@archiveofourown.org` — confirmed
/// against real mail — while other providers write `header.d=archiveofourown.org`.
/// Both must be read, or every real message is rejected.
fn clause_domain(clause: &str) -> Option<&str> {
    for token in clause.split_whitespace() {
        if let Some(v) = strip_ci_prefix(token, "header.d=") {
            return clean_domain(v);
        }
        if let Some(v) = strip_ci_prefix(token, "header.i=") {
            // An identity is `[local-part]@domain`; the domain is what signs.
            return clean_domain(v.rsplit('@').next()?);
        }
        if let Some(v) = strip_ci_prefix(token, "d=") {
            return clean_domain(v);
        }
    }
    None
}

fn clean_domain(raw: &str) -> Option<&str> {
    let v = raw.trim_matches(|c: char| c == '"' || c == ';' || c == ',' || c.is_whitespace());
    (!v.is_empty()).then_some(v)
}

fn strip_ci_prefix<'a>(haystack: &'a str, prefix: &str) -> Option<&'a str> {
    let head = haystack.get(..prefix.len())?;
    head.eq_ignore_ascii_case(prefix).then(|| haystack.get(prefix.len()..))?
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;

    fn msg(raw: &str) -> Message<'_> {
        MessageParser::default().parse(raw.as_bytes()).expect("fixture parses")
    }

    /// Gmail's real wording for AO3 mail, copied from a live message: one
    /// unfolded line, DKIM identity as `header.i=`, and an SPF clause carrying a
    /// parenthesised comment that itself mentions the domain.
    const GOOD_AR: &str = "Authentication-Results: mx.google.com;       dkim=pass header.i=@archiveofourown.org header.s=dkim20210802 header.b=1RuaQ1RM;       spf=pass (google.com: domain of do-not-reply@archiveofourown.org designates 208.85.241.153 as permitted sender) smtp.mailfrom=do-not-reply@archiveofourown.org;       dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=archiveofourown.org\r\n";

    fn ao3(extra: &str) -> String {
        format!(
            "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
             To: reader@example.com\r\n\
             Subject: [AO3] someone posted Chapter 1 of A Work\r\n\
             {extra}\r\nbody\r\n"
        )
    }

    #[test]
    fn trusts_ao3_mail_the_provider_attested() {
        let raw = ao3(GOOD_AR);
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Trusted
        );
    }

    #[test]
    fn without_an_attestor_it_is_sender_only() {
        let raw = ao3(GOOD_AR);
        assert_eq!(check(&msg(&raw), &Attestor::none()), Verdict::SenderOnly);
    }

    #[test]
    fn rejects_a_different_sender() {
        // The Reddit notifications a subject filter would have let through.
        let raw = "From: Reddit <noreply@redditmail.com>\r\n\
                   Subject: [AO3] Monetizing AO3\r\n\r\nbody\r\n";
        assert_eq!(
            check(&msg(raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }

    #[test]
    fn rejects_a_forged_from_that_merely_contains_the_address() {
        let raw = "From: \"do-not-reply@archiveofourown.org\" <attacker@evil.test>\r\n\
                   Subject: [AO3] x\r\n\r\nbody\r\n";
        assert_eq!(check(&msg(raw), &Attestor::none()), Verdict::Rejected);
    }

    #[test]
    fn rejects_a_lookalike_domain() {
        let raw = "From: <do-not-reply@archiveofourown.org.evil.test>\r\n\r\nbody\r\n";
        assert_eq!(check(&msg(raw), &Attestor::none()), Verdict::Rejected);
    }

    #[test]
    fn rejects_when_the_provider_says_dkim_failed() {
        let raw = ao3("Authentication-Results: mx.google.com; dkim=fail header.d=archiveofourown.org\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }

    #[test]
    fn ignores_an_attestation_from_a_server_we_are_not_talking_to() {
        // A sender can prepend whatever Authentication-Results they like.
        let raw = ao3("Authentication-Results: evil.test; dkim=pass header.d=archiveofourown.org\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::SenderOnly
        );
    }

    #[test]
    fn a_forged_header_below_the_real_one_cannot_override_it() {
        let raw = ao3(
            "Authentication-Results: mx.google.com; dkim=fail header.d=archiveofourown.org\r\n\
             Authentication-Results: mx.google.com; dkim=pass header.d=archiveofourown.org\r\n",
        );
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected,
            "the outermost verdict is the only one that counts"
        );
    }

    #[test]
    fn dkim_pass_for_some_other_domain_is_not_enough() {
        let raw = ao3("Authentication-Results: mx.google.com; dkim=pass header.d=evil.test\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }

    #[test]
    fn adkim_is_not_mistaken_for_a_signing_domain() {
        let raw = ao3("Authentication-Results: mx.google.com; dkim=pass adkim=r header.d=evil.test\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }

    #[test]
    fn a_subdomain_of_ao3_does_not_count_as_ao3() {
        let raw = ao3("Authentication-Results: mx.google.com; dkim=pass header.d=mail.archiveofourown.org\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }

    #[test]
    fn a_message_with_no_from_is_rejected() {
        let raw = "Subject: [AO3] x\r\n\r\nbody\r\n";
        assert_eq!(check(&msg(raw), &Attestor::none()), Verdict::Rejected);
    }

    #[test]
    fn a_second_sender_alongside_ao3_is_rejected() {
        let raw = "From: <do-not-reply@archiveofourown.org>, <attacker@evil.test>\r\n\r\nbody\r\n";
        assert_eq!(check(&msg(raw), &Attestor::none()), Verdict::Rejected);
    }

    #[test]
    fn a_properly_folded_header_still_reads() {
        // Continuation lines begin with whitespace. This is what a real folded
        // Authentication-Results looks like on the wire.
        let folded = "Authentication-Results: mx.google.com;\r\n\tdkim=pass header.i=@archiveofourown.org;\r\n\tspf=pass\r\n";
        let raw = ao3(folded);
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Trusted
        );
    }

    #[test]
    fn a_truncated_attestation_is_not_trusted() {
        // No dkim clause at all: the provider stamped something we cannot read
        // as a pass, so it must not count as one.
        let raw = ao3("Authentication-Results: mx.google.com;\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }

    #[test]
    fn header_d_is_read_as_well_as_header_i() {
        let raw = ao3("Authentication-Results: mx.google.com; dkim=pass header.d=archiveofourown.org\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Trusted
        );
    }

    #[test]
    fn the_spf_comment_naming_ao3_cannot_fake_a_dkim_pass() {
        // The real SPF clause contains "domain of do-not-reply@archiveofourown.org".
        // That must not be mistaken for a DKIM signing domain.
        let raw = ao3("Authentication-Results: mx.google.com; dkim=fail header.i=@evil.test; spf=pass (google.com: domain of do-not-reply@archiveofourown.org designates 1.2.3.4 as permitted sender)\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }
}
