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
# check-invariants.sh (which is pure grep and expected to be instant).
#
# Without cargo it FAILS rather than skipping. An earlier version exited zero,
# which let verify.sh go on to print ALL GREEN having never run its only check —
# and with a cached xcframework the Swift tests pass against the old
# binding/library pair while the Rust source has moved. A gate that announces
# the definition of done must not pass when it did not run. Pass --allow-missing
# -cargo to opt out explicitly, for a contributor without a Rust toolchain who
# has changed no Rust.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINDING="kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift"

export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
ALLOW_MISSING_CARGO=0
[ "${1:-}" = "--allow-missing-cargo" ] && ALLOW_MISSING_CARGO=1

if ! command -v cargo > /dev/null; then
  if [ "$ALLOW_MISSING_CARGO" = "1" ]; then
    echo "check-binding-drift: SKIPPED by --allow-missing-cargo (no cargo on PATH)"
    echo "  The committed binding was NOT verified against the crate."
    exit 0
  fi
  echo "check-binding-drift: FAILED (no cargo on PATH)"
  echo "  This gate cannot verify the committed binding without a Rust toolchain,"
  echo "  and passing regardless would let verify.sh report ALL GREEN having"
  echo "  checked nothing. Install rustup, or re-run with --allow-missing-cargo"
  echo "  if you have changed nothing under kudos-mail-core/."
  exit 1
fi

# Refuse to run on a dirty binding: a pre-existing local edit would be reported
# as drift, and the regeneration below would destroy it. Compare against HEAD,
# not the index — `diff --quiet` alone ignores a STAGED edit, which the
# regeneration would then overwrite in the working tree.
if ! git -C "$ROOT" diff --quiet HEAD -- "$BINDING"; then
  echo "check-binding-drift: FAILED"
  echo "  $BINDING has uncommitted changes."
  echo "  Commit or revert them first — this check overwrites that file."
  exit 1
fi

BEFORE=$(git -C "$ROOT" hash-object "$ROOT/$BINDING")

# build-mail-xcframework.sh rewrites the tracked binding and deletes the existing
# xcframework before reassembling it. If assembly then fails, `set -e` would exit
# with the binding already overwritten and the previous framework gone — a check
# that breaks the tree it was asked to inspect. Restore the binding on any
# non-zero exit; the xcframework is a build artifact and is rebuilt on demand,
# but say so rather than leaving it a surprise.
restore_binding() {
  status=$?
  if [ "$status" -ne 0 ]; then
    git -C "$ROOT" checkout -- "$BINDING" 2> /dev/null || true
    echo "check-binding-drift: regeneration failed; restored $BINDING"
    echo "  build/KudosMail.xcframework may have been removed — re-run"
    echo "  Scripts/build-mail-xcframework.sh before building the app."
  fi
  return $status
}
trap restore_binding EXIT

echo "check-binding-drift: regenerating from the crate"
"$ROOT/Scripts/build-mail-xcframework.sh" > /dev/null

# Regeneration succeeded, so disarm the trap. Past this point a non-zero exit
# means DRIFT, not failure, and the regenerated file is the thing the developer
# is told to review and commit — restoring it here would delete the evidence and
# mislabel the result.
trap - EXIT

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
