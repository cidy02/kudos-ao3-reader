# kudos-mail-core

Reads AO3 subscription notifications out of a mailbox, and nothing else.

AO3's website never says what changed or when — its subscriptions page lists a
name and a byline and no more. Its notification *email* carries the work id,
chapters posted and total, rating, warnings, tags, word counts, a summary, an
exact timestamp, and a line naming which subscription fired. This crate reads
that, for both the iOS and Android apps.

## Why a separate crate

Containment. The host apps receive `Ao3Event` values and have **no type that can
hold a mail message**, so "Kudos reads only AO3's notifications" is a property of
the boundary rather than a rule someone has to remember. Raw mail is parsed here
and dropped here.

## Three defences

1. **Scope.** The IMAP `SEARCH` is restricted to AO3's sender, so the server
   never returns anything else and nothing else is ever downloaded.
2. **Gate** (`gate.rs`). The sender is re-checked, and where the receiving
   provider attested the message, DKIM must have passed *for AO3's domain* —
   read from the topmost `Authentication-Results` whose `authserv-id` is the host
   we are connected to. A sender may prepend as many forged ones below it as they
   like.
3. **Parse defensively** (`parser.rs`). Ids must be digits under AO3's own
   `/works/` path, every string is length-capped, lists are bounded, and only
   `text/plain` is read — the HTML alternative says the same thing and parsing it
   would mean running a stranger's markup through another parser.

`unsafe` is forbidden crate-wide and release builds abort rather than unwind, so
a panic can never cross the FFI boundary as undefined behaviour.

## Why not verify DKIM ourselves

There is no maintained native-Rust-to-mobile DKIM verifier we can lean on, and a
verifier with a bug that *accepts* bad signatures is worse than none — it turns
"we do not check" into "we check wrongly and believe it". So the gate reports
what it can actually establish:

| verdict | meaning |
|---|---|
| `Trusted` | sender matches and the provider attested DKIM for AO3 |
| `SenderOnly` | sender matches, nobody attested it — a watched folder, say |
| `Rejected` | not AO3's, or attested as failing |

The caller decides policy per tier. Content is treated as hostile either way.

## Measurements behind the code

Taken from a real mailbox on 2026-11-05 (273 AO3 messages over two years):

* every message: `From: do-not-reply@archiveofourown.org`, DKIM
  `d=archiveofourown.org`, `spf=pass dkim=pass dmarc=pass`. Gmail writes the
  identity as `header.i=@archiveofourown.org`, not `header.d=` — reading only
  `d=` would reject all real mail.
* a `SUBJECT "[AO3]"` probe matched **six Reddit notifications** that merely
  mention AO3. Subject text is therefore never part of the decision.
* shapes: 213 new chapter via a work subscription, 31 new chapter via an author
  subscription, 14 new work via an author subscription; plus kudos, comment
  replies and an abuse report, which are not subscription events.
* **fields are not uniform.** `Chapters:`, `Rating:` and `Summary:` appeared on
  every notification; `Warning:` on 154/213, `Relationships:` on 180/213,
  `Additional Tags:` on 108/213. Nothing may be assumed present.

## Testing against real mail

No real message is committed — notification mail carries a reader's address and
their reading history, and this repository is public. `tests/real_mail.rs` skips
unless you point it at your own directory:

```sh
KUDOS_REAL_MAIL_DIR=/path/to/eml cargo test --test real_mail -- --nocapture
```

## Status

Gate and parser are complete and tested. The IMAP session is not yet written;
its dependencies are pinned in `Cargo.toml` so the surface is reviewable before
any network code exists.
