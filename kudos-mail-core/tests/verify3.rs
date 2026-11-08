//! Codex's third review pass: every finding was a consequence of AO3
//! interpolating an author-controlled work title — which may contain newlines
//! and quotes — into both the preface and the footer. Each test below is the
//! attack that was reproduced, asserting the behaviour after the fix.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Attestor, Subscription};

fn mail(title: &str, footer_name: &str) -> String {
    format!("From: Archive of Our Own <do-not-reply@archiveofourown.org>\r\n\
Date: Thu, 29 Oct 2026 00:49:51 +0000\r\nSubject: [AO3] x\r\n\
Content-Type: text/plain; charset=UTF-8\r\n\r\n\
Archive of Our Own\r\n=========================================\r\n\r\n\r\n\
lamplighter posted a new chapter of \"{title}\" (34920 words):\r\n\
https://archiveofourown.org/works/83701926/chapters/255464091\r\n\r\n\
\"Chapter 9\" (4679 words)\r\n\r\nChapters: 9/13\r\nRating: Teen And Up Audiences\r\n\r\n\
-----------------------------------------\r\n\
You're receiving this email because you've subscribed to {footer_name}. Follow the link to unsubscribe if you no longer wish to receive updates: https://archiveofourown.org/users/lamplighter\r\n")
}

#[test] fn f1_colon_in_title_moves_the_link() {
    let t = "Decoy:\r\nhttps://archiveofourown.org/works/111/chapters/222\r\nrest";
    let r = read(mail(t, "lamplighter").as_bytes(), &Attestor::none());
    println!("F1 work_id -> {:?}", r.as_ref().map(|r| (r.event.work_id, r.event.chapter_id)));
    // Once the preface ends at AO3's own `words):` terminator rather than at any
    // line ending in a colon, the decoy no longer ends it early — so the link
    // scan starts below the whole title and finds AO3's own line. This used to
    // report work 111; it then became a refusal; it is now simply correct, which
    // is what the subscriber needs, since a refusal loses the real update.
    assert_eq!(
        r.map(|r| (r.event.work_id, r.event.chapter_id)),
        Ok((83_701_926, Some(255_464_091)))
    );
}

#[test] fn f4_title_in_footer_moves_the_rule() {
    let t = "Innocent";
    let name = "Innocent\r\n-----------------------------------------\r\nYou're receiving this email because you've subscribed to impostor. Follow the link";
    let r = read(mail(t, name).as_bytes(), &Attestor::none());
    println!("F4 via -> {:?}", r.as_ref().map(|r| r.event.via.clone()));
    // The forged sentence can still choose the display NAME, but the kind and
    // the identity come from AO3's unsubscribe URL, which it cannot move.
    assert_eq!(
        r.map(|r| r.event.via),
        Ok(Subscription::Author { username: "lamplighter".into(), name: Some("impostor".into()) })
    );
}

#[test] fn f6_pseud_containing_the_phrase() {
    // AO3 renders every creator as `<byline> (<pseud url>)` (`text_pseud`), as
    // all six real messages do, and prints its phrase after that block. So the
    // pseud URL is what separates a pseud containing the phrase from AO3's own
    // use of it — neither the first occurrence nor the last can, since a TITLE
    // can hold the phrase too. Taking the last read the author out of the
    // middle of AO3's sentence; this body is the real rendering.
    let raw = mail("Work", "lamplighter").replace(
        "lamplighter posted a new chapter of",
        "Alice posted a new chapter of Bob          (https://archiveofourown.org/users/alice/pseuds/Alice) posted a new chapter of",
    );
    let r = read(raw.as_bytes(), &Attestor::none());
    println!("F6 author -> {:?}", r.as_ref().map(|r| r.event.author.clone()));
    // The pseud survives whole, and the URL AO3 appended is not part of it.
    assert_eq!(r.map(|r| r.event.author).as_deref(), Ok("Alice posted a new chapter of Bob"));
}

#[test] fn f7_quote_in_title_sets_word_count() {
    let r = read(mail("Safe\" (1 words) \"Rest", "lamplighter").as_bytes(), &Attestor::none());
    println!("F7 title/words -> {:?}", r.as_ref().map(|r| (r.event.work_title.clone(), r.event.words)));
    // The whole title, and AO3's own word count rather than the author's.
    assert_eq!(
        r.map(|r| (r.event.work_title, r.event.words)),
        Ok(("Safe\" (1 words) \"Rest".to_owned(), Some(34_920)))
    );
}

#[test] fn f5_divider_in_title_suppresses_the_event() {
    let t = "A\r\n--------------------\r\nB";
    let r = read(mail(t, "lamplighter").as_bytes(), &Attestor::none());
    println!("F5 -> {:?}", r.as_ref().map(|r| r.event.work_id));
    // A hyphen rule inside a title is not a batch divider, so the notification
    // is still delivered rather than cut in half and refused.
    assert_eq!(r.map(|r| r.event.work_id), Ok(83_701_926));
}
