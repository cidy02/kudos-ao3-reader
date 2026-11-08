//! Gate regressions for the Authentication-Results forgeries. Each of these
//! produced `Trusted` before the header gained a real RFC 8601 reader.
//!
//! These drive `gate::check` directly: they are about header handling, and
//! should not depend on the body parsing.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::gate::{check, Attestor, Verdict};
use mail_parser::MessageParser;

fn verdict(authentication_results: &str) -> Verdict {
    let raw = format!(
        "From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
         Subject: [AO3] x\r\n{authentication_results}\r\nbody\r\n"
    );
    let msg = MessageParser::default().parse(raw.as_bytes()).unwrap();
    check(&msg, &Attestor::provider("mx.google.com"))
}

#[test]
fn an_escaped_quote_cannot_expose_a_fake_clause() {
    assert_ne!(
        verdict("Authentication-Results: mx.google.com; spf=fail reason=\"x\\\"; dkim=pass header.d=archiveofourown.org\"\r\n"),
        Verdict::Trusted
    );
}

#[test]
fn a_clause_inside_a_comment_is_not_syntax() {
    assert_ne!(
        verdict("Authentication-Results: mx.google.com; spf=fail (x; dkim=pass header.d=archiveofourown.org )\r\n"),
        Verdict::Trusted
    );
}

#[test]
fn contradicting_identities_are_not_believed() {
    assert_ne!(
        verdict("Authentication-Results: mx.google.com; dkim=pass header.i=@archiveofourown.org header.d=evil.test\r\n"),
        Verdict::Trusted
    );
}

/// Gmail's own stamp, copied from a live message. Its spf clause carries a
/// parenthesised comment that names AO3; that must not break a genuine pass.
#[test]
fn the_real_header_still_passes() {
    assert_eq!(
        verdict("Authentication-Results: mx.google.com;       dkim=pass header.i=@archiveofourown.org header.s=dkim20210802 header.b=1RuaQ1RM;       spf=pass (google.com: domain of do-not-reply@archiveofourown.org designates 208.85.241.153 as permitted sender) smtp.mailfrom=do-not-reply@archiveofourown.org;       dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=archiveofourown.org\r\n"),
        Verdict::Trusted
    );
}

/// A later forged pass must not override the provider's own failure.
#[test]
fn a_pass_after_a_fail_in_one_header_is_not_a_pass() {
    assert_ne!(
        verdict("Authentication-Results: mx.google.com; dkim=fail header.d=evil.test; spf=fail (google.com: domain of x) ; dkim=pass header.i=@archiveofourown.org designates 1.2.3.4 as permitted sender)\r\n"),
        Verdict::Trusted
    );
}
