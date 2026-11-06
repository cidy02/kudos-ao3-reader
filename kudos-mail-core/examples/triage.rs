//! Parse a directory of real `.eml` files and report STRUCTURE ONLY.
//!
//! `cargo run --example triage -- <dir>`
//!
//! Deliberately prints no titles, pseuds, summaries or tag names: a corpus of
//! notification mail is a reader's own history. What it prints is whether each
//! field arrived, which is what tells us the parser is right.
#![allow(clippy::unwrap_used, clippy::expect_used)]

use kudos_mail_core::{read, Attestor, Identity, ReadError, Subscription};

fn main() {
    let dir = std::env::args().nth(1).expect("usage: triage <dir>");
    let mut files: Vec<std::path::PathBuf> = std::fs::read_dir(&dir)
        .expect("readable directory")
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "eml"))
        .collect();
    files.sort();

    let mut ok = 0usize;
    let mut errs: Vec<(String, String)> = Vec::new();
    let mut no_meta = 0usize;
    let mut no_summary = 0usize;
    let mut no_title = 0usize;
    let mut anon = 0usize;
    let mut body_identity = 0usize;
    let mut unknown_via = 0usize;

    println!(
        "{:9} {:8} {:16} {:>9} {:>9} {:>4} {:>3} {:>3} {:>3} {:>3} {:>4} {:>4} {:>4}",
        "file", "identity", "via", "work", "chapter", "num", "f", "r", "c", "t", "sum", "ser", "ttl"
    );
    for path in &files {
        let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
        let raw = std::fs::read(path).expect("readable file");
        match read(&raw, &Attestor::none()) {
            Ok(r) => {
                ok += 1;
                let e = r.event;
                let via = match &e.via {
                    Subscription::Work { id, .. } => format!("work {id}"),
                    Subscription::Series { id, .. } => format!("series {id}"),
                    Subscription::Author { username, .. } => {
                        format!("user {}", &username[..username.len().min(8)])
                    }
                    Subscription::Unknown => {
                        unknown_via += 1;
                        "UNKNOWN".to_owned()
                    }
                };
                if e.rating.is_none() {
                    no_meta += 1;
                }
                if e.summary.is_none() {
                    no_summary += 1;
                }
                if e.work_title.is_empty() {
                    no_title += 1;
                }
                if e.author == "Anonymous" {
                    anon += 1;
                }
                if e.identity == Identity::Body {
                    body_identity += 1;
                }
                println!(
                    "{:9} {:8} {:16} {:>9} {:>9} {:>4} {:>3} {:>3} {:>3} {:>3} {:>4} {:>4} {:>4}",
                    name,
                    if e.identity == Identity::Work { "work" } else { "BODY" },
                    via,
                    e.work_id,
                    e.chapter_id.map_or("-".to_owned(), |c| c.to_string()),
                    e.chapters_posted.map_or("-".to_owned(), |c| c.to_string()),
                    e.fandoms.len(),
                    e.relationships.len(),
                    e.characters.len(),
                    e.additional_tags.len(),
                    e.summary.as_ref().map_or("-".to_owned(), |s| s.len().to_string()),
                    if e.series.is_some() { "yes" } else { "-" },
                    if e.work_title.is_empty() { "NONE" } else { "ok" },
                );
            }
            Err(ReadError::Parse(p)) => errs.push((name, format!("{p}"))),
            Err(e) => errs.push((name, format!("{e}"))),
        }
    }

    println!("\n{} file(s): {ok} parsed, {} not", files.len(), errs.len());
    if !errs.is_empty() {
        println!("\nnot parsed:");
        for (name, why) in &errs {
            println!("  {name}: {why}");
        }
    }
    println!(
        "\nof the {ok} parsed: {no_meta} without a rating, {no_summary} without a summary, \
         {no_title} without a work title, {anon} anonymous, {body_identity} with Identity::Body, \
         {unknown_via} with an unknown subscription"
    );
}
