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

/// True when the message carries exactly one `From` header and every address
/// in it is AO3's notification address.
///
/// The header count is checked separately because `Message::from()` reports only
/// one header when several are present — so `From: attacker` followed by
/// `From: <AO3>` looked like AO3's alone, while a mail client showing the first
/// header would show the attacker. A message with two `From` headers is
/// malformed; we do not have to guess which one anybody else believes.
fn sender_is_ao3(message: &Message<'_>) -> bool {
    let from_headers = message
        .headers()
        .iter()
        .filter(|h| h.name().eq_ignore_ascii_case("From"))
        .count();
    if from_headers != 1 {
        return false;
    }
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
        return dkim_verdict_for_ao3(rest);
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

/// `Some(true)` for a `dkim=pass` clause whose identity is AO3's domain,
/// `Some(false)` when a DKIM verdict is readable but is not that, and `None`
/// when no DKIM verdict can be read here at all.
///
/// The third case is not pedantry. Only the clauses before the header's first
/// comment are readable (see [`before_first_comment`]), so a provider that
/// writes a comment ahead of its DKIM clause leaves us with nothing to go on —
/// and "the provider said no" is a rejection, while "we could not tell" has to
/// degrade to [`Verdict::SenderOnly`]. Collapsing the two would have rejected
/// every message from such a provider, killing the feature silently instead of
/// marking it unverified.
///
/// RFC 8601 gives this header structured syntax: comments in parentheses, and
/// quoted strings in which a backslash escapes the next character. A naive
/// scanner let all three of these forge a pass, each confirmed by test:
///
/// * `reason="x\"; dkim=pass header.d=archiveofourown.org"` — the escaped quote
///   flipped the quote state, exposing a fake clause;
/// * `spf=fail (x; dkim=pass header.d=archiveofourown.org )` — a comment was
///   split as though it were real syntax;
/// * `dkim=pass header.i=@archiveofourown.org header.d=evil.test` — the first
///   identity won and the contradicting one was never looked at.
fn dkim_verdict_for_ao3(results: &str) -> Option<bool> {
    // Only the clauses before the header's first comment are read. See
    // `before_first_comment` for why nothing after it can be believed.
    let plain = strip_comments(before_first_comment(results));
    let mut saw_a_verdict = false;
    for clause in split_clauses(&plain) {
        let clause = clause.trim();
        let Some(rest) = strip_ci_prefix(clause, "dkim=") else { continue };
        saw_a_verdict = true;
        if !rest.split_whitespace().next().unwrap_or("").eq_ignore_ascii_case("pass") {
            continue;
        }
        if !is_well_formed_clause(rest) {
            // Everything after `dkim=pass` must be a `key=value` property. Prose
            // there means the clause was assembled out of something that escaped
            // a comment — a stray `)` in an address a provider reflected, say —
            // and a clause we cannot read cleanly is not one to believe.
            continue;
        }
        let domains = identity_domains(clause);
        // Every identity the clause names must be AO3's. One that disagrees
        // means the clause is not telling us one thing, so we believe none of it.
        if !domains.is_empty()
            && domains.iter().all(|d| d.eq_ignore_ascii_case(AO3_DKIM_DOMAIN))
        {
            return Some(true);
        }
    }
    saw_a_verdict.then_some(false)
}

/// The header up to its first comment, ignoring parentheses inside quoted
/// strings.
///
/// This is the one defence that cannot be done by parsing more carefully. A
/// provider reflects sender-supplied text — an envelope-from address, a `From`
/// display name — into its own `Authentication-Results`, inside a comment.
/// Measured against the six real Gmail headers in the corpus (2026-11-05):
///
/// ```text
/// mx.google.com; dkim=pass header.i=@archiveofourown.org header.s=… header.b=…;
///                spf=pass (google.com: domain of <THE SENDER'S ADDRESS> designates …)
/// ```
///
/// A local part may contain `)` when quoted, so a sender addressed
/// `"x) ; dkim=pass header.d=archiveofourown.org x=y (@evil.test"` closes the
/// comment, writes a whole clause of their own, and re-opens it. After comment
/// stripping that clause is indistinguishable from a real one: the `)` that
/// ended the comment was a real `)`, every token holds an `=`, and the only
/// identity it names is AO3's. No scanner can tell them apart, so the forged
/// clause must be kept out of reach instead.
///
/// It always is, because the injection needs the provider's `(` to sit before
/// it. In all six real messages `dkim=pass` is the FIRST clause, at offset 15,
/// while the reflected address begins at offset 105 — so stopping at the first
/// comment loses nothing genuine. A provider that ordered them the other way
/// would yield [`Verdict::SenderOnly`], which is the safe direction to fail.
fn before_first_comment(results: &str) -> &str {
    let (mut quoted, mut escaped) = (false, false);
    for (i, c) in results.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        match c {
            '\\' => escaped = true,
            '"' => quoted = !quoted,
            '(' if !quoted => return results.get(..i).unwrap_or(""),
            _ => {}
        }
    }
    results
}

/// True when every token after the result keyword is a `key=value` property.
fn is_well_formed_clause(after_keyword: &str) -> bool {
    after_keyword
        .split_whitespace()
        .skip(1) // the outcome itself: `pass`
        .all(|token| token.contains('='))
}

/// Every `header.d=` / `header.i=` domain named in one clause.
fn identity_domains(clause: &str) -> Vec<&str> {
    let mut out = Vec::new();
    for token in clause.split_whitespace() {
        let value = strip_ci_prefix(token, "header.d=")
            .or_else(|| strip_ci_prefix(token, "header.i=").and_then(|v| v.rsplit('@').next()));
        if let Some(d) = value.and_then(clean_domain) {
            out.push(d);
        }
    }
    out
}

fn clean_domain(raw: &str) -> Option<&str> {
    let v = raw.trim_matches(|c: char| c == '"' || c == ';' || c == ',' || c.is_whitespace());
    (!v.is_empty()).then_some(v)
}

/// Remove RFC 5322 comments — `(...)`, which nest — leaving a space behind.
///
/// Quoted strings are copied through untouched, and a backslash escapes the
/// character after it in both contexts.
fn strip_comments(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let (mut depth, mut quoted, mut escaped) = (0usize, false, false);
    for c in input.chars() {
        if escaped {
            escaped = false;
            if depth == 0 {
                out.push(c);
            }
            continue;
        }
        match c {
            '\\' => {
                escaped = true;
                if depth == 0 {
                    out.push(c);
                }
            }
            '"' if depth == 0 => {
                quoted = !quoted;
                out.push(c);
            }
            '(' if !quoted => {
                depth += 1;
                out.push(' ');
            }
            ')' if !quoted && depth > 0 => depth -= 1,
            _ if depth == 0 => out.push(c),
            _ => {}
        }
    }
    out
}

/// Split on `;` outside quoted strings, honouring backslash escapes.
fn split_clauses(input: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let (mut start, mut quoted, mut escaped) = (0usize, false, false);
    for (i, c) in input.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        match c {
            '\\' => escaped = true,
            '"' => quoted = !quoted,
            ';' if !quoted => {
                if let Some(piece) = input.get(start..i) {
                    out.push(piece);
                }
                start = i + 1;
            }
            _ => {}
        }
    }
    if let Some(piece) = input.get(start..) {
        out.push(piece);
    }
    out
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
        // A readable `dkim=fail` is the provider saying no, which is a rejection
        // and not the "cannot tell" that degrades to SenderOnly.
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
        // No dkim clause at all. Unreadable is not the same as "the provider
        // said no", so this degrades to SenderOnly rather than being rejected —
        // and that costs nothing, because a sender who wanted SenderOnly could
        // simply omit the header, which already yields it. What must never
        // happen is Trusted.
        let raw = ao3("Authentication-Results: mx.google.com;\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::SenderOnly
        );
    }

    /// A header we cannot read must land exactly where an absent one does, or
    /// an attacker could choose between tiers by malforming it.
    #[test]
    fn an_unreadable_attestation_lands_where_an_absent_one_does() {
        let unreadable = ao3("Authentication-Results: mx.google.com; (comment first) dkim=pass header.d=archiveofourown.org\r\n");
        let absent = ao3("Subject: x\r\n");
        let p = Attestor::provider("mx.google.com");
        assert_eq!(check(&msg(&unreadable), &p), check(&msg(&absent), &p));
        assert_eq!(check(&msg(&unreadable), &p), Verdict::SenderOnly);
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

    #[test]
    fn two_from_headers_are_refused() {
        // `Message::from()` reports only one of them, so the other was invisible
        // to the address check while a mail client might show it instead.
        let raw = "From: attacker@evil.test\r\n\
                   From: do-not-reply@archiveofourown.org\r\n\
                   Subject: x\r\n\r\nbody\r\n";
        assert_eq!(check(&msg(raw), &Attestor::none()), Verdict::Rejected);
    }

    #[test]
    fn a_semicolon_inside_a_quoted_value_cannot_smuggle_a_clause() {
        // Confirmed bypass: this returned Trusted before clause splitting
        // learned about quoting.
        let raw = ao3(
            "Authentication-Results: mx.google.com; spf=fail reason=\"x; dkim=pass header.d=archiveofourown.org\"\r\n",
        );
        // The smuggled clause is inside a quoted string, so once splitting is
        // quote-aware no DKIM verdict is readable at all — "cannot tell", not
        // "said no". What this pins is that it is never Trusted.
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::SenderOnly
        );
    }

    #[test]
    fn a_bare_d_is_not_accepted_as_a_signing_domain() {
        // RFC 8601 spells these header.d / header.i.
        let raw = ao3("Authentication-Results: mx.google.com; dkim=pass d=archiveofourown.org\r\n");
        assert_eq!(
            check(&msg(&raw), &Attestor::provider("mx.google.com")),
            Verdict::Rejected
        );
    }
}
