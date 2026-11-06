#!/usr/bin/env bash
# Fail if the committed UniFFI binding no longer matches the Rust source.
#
# kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift is generated code
# that is deliberately tracked (the xcframework it binds is not, so a fresh
# clone has to be able to compile the app without first installing a Rust
# toolchain). That trade means the checked-in Swift can silently fall behind the
# crate: change a `uniffi::Record` field or an exported signature, forget to
# re-run Scripts/build-mail-xcframework.sh, and nothing in the build complains.
#
# The generated file does embed UniFFI checksums and `fatalError`s on a
# mismatch, but only at runtime, on the first call into the library — so the
# first person to find out is whoever launches the app, and the Swift unit tests
# never do, because they build `Reading` and friends in process. This check
# moves that failure to the gate.
#
# It regenerates through the real script rather than reimplementing the
# generation, so the `#if os(iOS)` wrapper and whitespace normalisation are
# whatever that script does today and the two cannot drift apart either.
#
# Needs a Rust toolchain and both iOS targets, so it is NOT part of
# check-invariants.sh (which is pure grep and expected to be instant). Skips
# itself with a clear message when cargo is absent, so a contributor without
# Rust can still run the rest of the gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINDING="kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift"

export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
if ! command -v cargo > /dev/null; then
  echo "check-binding-drift: SKIPPED (no cargo on PATH)"
  echo "  The committed binding was not verified against the crate. Install a"
  echo "  Rust toolchain and re-run if you changed anything under kudos-mail-core/."
  exit 0
fi

# Refuse to run on a dirty binding: a pre-existing local edit would be reported
# as drift, and the regeneration below would destroy it.
if ! git -C "$ROOT" diff --quiet -- "$BINDING"; then
  echo "check-binding-drift: FAILED"
  echo "  $BINDING has uncommitted changes."
  echo "  Commit or revert them first — this check overwrites that file."
  exit 1
fi

BEFORE=$(git -C "$ROOT" hash-object "$ROOT/$BINDING")

echo "check-binding-drift: regenerating from the crate"
"$ROOT/Scripts/build-mail-xcframework.sh" > /dev/null

AFTER=$(git -C "$ROOT" hash-object "$ROOT/$BINDING")

if [ "$BEFORE" != "$AFTER" ]; then
  echo "check-binding-drift: FAILED"
  echo "  The committed binding does not match the crate. Diff:"
  git -C "$ROOT" --no-pager diff --stat -- "$BINDING"
  echo
  echo "  The regenerated file is already in your tree — review it and commit it"
  echo "  together with the Rust change that caused it."
  exit 1
fi

echo "check-binding-drift: OK"
