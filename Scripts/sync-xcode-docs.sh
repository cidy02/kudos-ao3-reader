#!/usr/bin/env zsh
# Sync Xcode's 'AdditionalDocumentation' (LLM-oriented Markdown) into this repo,
# so Claude/other AI tooling can read it without leaving the sandbox.
#
#   Scripts/sync-xcode-docs.sh
#
# Prefers /Applications/Xcode-beta.app, falls back to /Applications/Xcode.app
# (only Xcode.app is installed on this machine today, so that's the live path).
#
# Output: docs/xcode/<version+build>/... with docs/xcode/latest -> that folder.
# docs/xcode/ is gitignored (local-only, environment-specific — this repo is
# public, see AGENTS.md's "Sensitive / never-commit").

set -eu
set -o pipefail

PREFERRED_APP="/Applications/Xcode-beta.app"
FALLBACK_APP="/Applications/Xcode.app"

REPO_ROOT="$(cd "$(dirname "${0:A}")/.." && pwd)"
REPO_DOCS_DIR="$REPO_ROOT/docs/xcode"
REPO_LATEST_LINK="$REPO_DOCS_DIR/latest"
mkdir -p "$REPO_DOCS_DIR"

APP=""
if [[ -d "$PREFERRED_APP" ]]; then
  APP="$PREFERRED_APP"
elif [[ -d "$FALLBACK_APP" ]]; then
  APP="$FALLBACK_APP"
else
  print -u2 "No Xcode app found at $PREFERRED_APP or $FALLBACK_APP"
  exit 1
fi

INFO_PLIST="$APP/Contents/Info.plist"
VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || print -r -- "unknown")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || print -r -- "0")
VERSION_DIR="$REPO_DOCS_DIR/${VER}+${BUILD}"
mkdir -p "$VERSION_DIR"

typeset -a DOC_DIRS
DOC_DIRS=(${(f)"$(find "$APP" -type d -name AdditionalDocumentation 2>/dev/null)"})

if (( ${#DOC_DIRS} == 0 )); then
  print -u2 "No 'AdditionalDocumentation' directories found in $APP"
  exit 0
fi

print "Found ${#DOC_DIRS} AdditionalDocumentation dir(s) in $APP"
print "Repo root: $REPO_ROOT"

TMPDIR="$(mktemp -d)"
for d in "${DOC_DIRS[@]}"; do
  rel="${d#"$APP/"}"
  dest="$TMPDIR/$rel"
  mkdir -p "$dest"
  rsync -a --include='*/' --include='*.md' --exclude='*' "$d/" "$dest/"
done

{
  print "app_path: $APP"
  print "version: $VER"
  print "build: $BUILD"
  print "synced_at: $(date +%Y-%m-%dT%H:%M:%S%z)"
} > "$TMPDIR/manifest.txt"

rsync -a "$TMPDIR/" "$VERSION_DIR/"
rm -rf "$TMPDIR"

rm -f "$REPO_LATEST_LINK"
ln -s "$VERSION_DIR" "$REPO_LATEST_LINK"

md_count=$(find -L "$REPO_LATEST_LINK" -type f -name '*.md' | wc -l | tr -d ' ')
print "Synced to $VERSION_DIR ($md_count Markdown files)"
print "Latest -> $REPO_LATEST_LINK"

GITIGNORE="$REPO_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]] && ! grep -qxF "docs/xcode/" "$GITIGNORE"; then
  # Group with the existing "Xcode: build output & DerivedData" block rather
  # than bolting a new section onto the end of the file. The inserted line
  # must be an exact match for the grep check above, or this dedup check
  # never fires and the line gets re-inserted on every run.
  awk '
    { print }
    /^# ---- Xcode: build output & DerivedData ----$/ && !done {
      print "# AdditionalDocumentation sync (Scripts/sync-xcode-docs.sh) — local only"
      print "docs/xcode/"
      done = 1
    }
  ' "$GITIGNORE" > "$GITIGNORE.tmp" && mv "$GITIGNORE.tmp" "$GITIGNORE"
  print "Added docs/xcode/ to .gitignore"
fi
