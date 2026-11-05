//! Regression tests for the second-pass review findings. Each of these forged a
//! `Trusted` verdict or injected content before being fixed.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Attestor, Verdict};

const BODY: &str = "Archive of Our Own\r\n\r\n\
someone (https://archiveofourown.org/users/someone/pseuds/someone) posted a new chapter of \"Work\" (10 words):\r\n\
https://archiveofourown.org/works/555/chapters/1\r\n\r\n\
\"Chapter 9\" (5 words)\r\n\r\nChapters: 9/13\r\nRating: General Audiences\r\n\r\nSummary:\r\n    innocent\r\n\r\n\
-----------------------------------------\r\n\
You're receiving this email because you've subscribed to someone. Follow the link to unsubscribe.\r\n";

fn ao3(extra: &str, body: &str) -> String {
    format!("From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
Date: Thu, 29 Oct 2026 00:49:51 +0000\r\n\
Subject: [AO3] x posted Chapter 9 of Work\r\n\
Content-Type: text/plain; charset=UTF-8\r\n{extra}\r\n{body}\r\n")
}

fn verdict_of(extra: &str) -> Option<Verdict> {
    read(ao3(extra, BODY).as_bytes(), &Attestor::provider("mx.google.com"))
        .ok()
        .map(|r| r.verdict)
}

#[test]
fn an_escaped_quote_cannot_expose_a_fake_clause() {
    assert_ne!(
        verdict_of("Authentication-Results: mx.google.com; spf=fail reason=\"x\\\"; dkim=pass header.d=archiveofourown.org\"\r\n"),
        Some(Verdict::Trusted)
    );
}

#[test]
fn a_clause_inside_a_comment_is_not_syntax() {
    assert_ne!(
        verdict_of("Authentication-Results: mx.google.com; spf=fail (x; dkim=pass header.d=archiveofourown.org )\r\n"),
        Some(Verdict::Trusted)
    );
}

#[test]
fn contradicting_identities_are_not_believed() {
    assert_ne!(
        verdict_of("Authentication-Results: mx.google.com; dkim=pass header.i=@archiveofourown.org header.d=evil.test\r\n"),
        Some(Verdict::Trusted)
    );
}

#[test]
fn the_real_header_still_passes() {
    assert_eq!(
        verdict_of("Authentication-Results: mx.google.com;       dkim=pass header.i=@archiveofourown.org header.s=dkim20210802 header.b=1RuaQ1RM;       spf=pass (google.com: domain of do-not-reply@archiveofourown.org designates 208.85.241.153 as permitted sender) smtp.mailfrom=do-not-reply@archiveofourown.org;       dmarc=pass (p=QUARANTINE) header.from=archiveofourown.org\r\n"),
        Some(Verdict::Trusted),
        "the comment in the spf clause must not break a genuine pass"
    );
}

#[test]
fn a_summary_cannot_state_the_wrong_subscription() {
    let body = BODY.replace(
        "    innocent",
        "    because you've subscribed to impostor. Follow the link to unsubscribe.",
    );
    let r = read(ao3("", &body).as_bytes(), &Attestor::none()).unwrap();
    assert_eq!(
        r.event.via,
        kudos_mail_core::Subscription::Author("someone".into()),
        "attribution comes from AO3's footer, not from author text"
    );
}

#[test]
fn a_summary_cannot_change_the_event_kind() {
    let body = BODY
        .replace("posted a new chapter of", "posted a new work")
        .replace("    innocent", "    posted a new chapter of something else");
    let r = read(ao3("", &body).as_bytes(), &Attestor::none()).unwrap();
    assert_eq!(r.event.kind, kudos_mail_core::Ao3EventKind::NewWork);
}

#[test]
fn a_non_ao3_message_is_refused_without_parsing_its_body() {
    // The body here would be expensive to walk; the gate must refuse first.
    let mut raw = b"From: attacker@evil.test\r\nSubject: x\r\nContent-Type: multipart/mixed; boundary=\"".to_vec();
    raw.extend(std::iter::repeat_n(b'-', 60_000));
    raw.extend_from_slice(b"X\"\r\n\r\n");
    raw.extend(std::iter::repeat_n(b'-', 400_000));
    let started = std::time::Instant::now();
    assert!(read(&raw, &Attestor::none()).is_err());
    assert!(
        started.elapsed().as_secs() < 2,
        "refusal must not depend on parsing the body"
    );
}
