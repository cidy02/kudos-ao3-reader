#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use kudos_mail_core::{read, Attestor, ParseError, ReadError};

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
    // Two works URLs in one creation region: the second was typed by an author,
    // and the text cannot say which is AO3's. Refused rather than guessed at.
    assert!(matches!(r, Err(ReadError::Parse(ParseError::NoWorkLink))));
}

#[test] fn f4_title_in_footer_moves_the_rule() {
    let t = "Innocent";
    let name = "Innocent\r\n-----------------------------------------\r\nYou're receiving this email because you've subscribed to impostor. Follow the link";
    let r = read(mail(t, name).as_bytes(), &Attestor::none());
    println!("F4 via -> {:?}", r.map(|r| r.event.via));
}

#[test] fn f6_pseud_containing_the_phrase() {
    let raw = mail("Work", "lamplighter")
        .replace("lamplighter posted a new chapter of", "Alice posted a new chapter of Bob posted a new chapter of");
    let r = read(raw.as_bytes(), &Attestor::none());
    println!("F6 author -> {:?}", r.as_ref().map(|r| r.event.author.clone()));
    // A pseud may legitimately contain AO3's own preface phrase; the creators
    // string runs to the LAST occurrence, so it is no longer truncated.
    assert_eq!(r.map(|r| r.event.author).as_deref(), Ok("Alice posted a new chapter of Bob"));
}

#[test] fn f7_quote_in_title_sets_word_count() {
    let r = read(mail("Safe\" (1 words) \"Rest", "lamplighter").as_bytes(), &Attestor::none());
    println!("F7 title/words -> {:?}", r.map(|r| (r.event.work_title, r.event.words)));
}

#[test] fn f5_divider_in_title_suppresses_the_event() {
    let t = "A\r\n--------------------\r\nB";
    println!("F5 -> {:?}", read(mail(t, "lamplighter").as_bytes(), &Attestor::none()).map(|r| r.event.work_id));
}
