//! Codex's fourth finding (F2): a provider reflects sender-supplied text into
//! its own `Authentication-Results` inside a comment, so a sender whose address
//! contains `)` escapes that comment and writes a whole forged clause.
#![allow(clippy::unwrap_used, clippy::panic)]
use kudos_mail_core::{read, Attestor, Verdict};

/// Gmail's real shape, measured 2026-11-05: `spf=... (google.com: domain of
/// <SENDER ADDRESS> designates ... as permitted sender) smtp.mailfrom=...`.
/// The address is the sender's. Here it carries `)` and re-opens `(`.
fn mail_with(auth: &str) -> String {
    format!(
        "Authentication-Results: {auth}\r\n\
         From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
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
         Follow the link to unsubscribe: https://archiveofourown.org/works/83701926\r\n"
    )
}

#[test]
fn an_address_that_escapes_the_spf_comment_cannot_forge_a_pass() {
    let evil = "x) ; dkim=pass header.d=archiveofourown.org x=y (@evil.test";
    let auth = format!(
        "mx.google.com; spf=fail (google.com: domain of {evil} does not designate \
         1.2.3.4 as permitted sender) smtp.mailfrom=\"{evil}\""
    );
    let r = read(mail_with(&auth).as_bytes(), &Attestor::provider("mx.google.com")).unwrap();
    println!("F2 verdict -> {:?}", r.verdict);
    // Unverified, not attested. Before the fix this read as Trusted.
    assert_eq!(r.verdict, Verdict::SenderOnly, "a forged clause must not read as attested");
}

/// The genuine header must still attest, or the fix has cost the feature.
#[test]
fn a_real_gmail_header_still_attests() {
    let auth = "mx.google.com; dkim=pass header.i=@archiveofourown.org \
                header.s=dkim20210802 header.b=1RuaQ1RM; spf=pass (google.com: domain of \
                do-not-reply@archiveofourown.org designates 208.85.241.153 as permitted \
                sender) smtp.mailfrom=do-not-reply@archiveofourown.org; dmarc=pass";
    let r = read(mail_with(auth).as_bytes(), &Attestor::provider("mx.google.com")).unwrap();
    assert_eq!(r.verdict, Verdict::Trusted);
}
