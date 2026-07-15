#!/bin/sh
# Mechanical invariant checks — each rule exists because its violation was a real,
# debugged bug (see docs/AGENT_ONBOARDING.md pitfalls + docs/AO3_NETWORKING_POLICY.md).
# Prose advises; this gate enforces. Run standalone or via Scripts/verify.sh.
#
# Adding a rule: pattern must be exact enough to be false-positive-free on the
# current tree (comments count as hits — pick call-syntax patterns), and the
# failure message must say WHY and link the doc that explains it.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/kudos-ao3-reader"
FAIL=0

fail() {
  FAIL=1
  printf 'INVARIANT VIOLATED: %s\n%s\n\n' "$1" "$2"
}

# 1. Exactly one .fileImporter in SettingsView — SwiftUI honors one file-dialog
#    presenter per view node; a sibling silently kills the others (T-73).
COUNT=$(grep -c "\.fileImporter(" "$APP/Settings/SettingsView.swift" || true)
if [ "$COUNT" != "1" ]; then
  fail "SettingsView must have exactly one .fileImporter (found $COUNT)" \
    "Extend the FileImportKind enum instead. docs/AGENT_ONBOARDING.md (pitfalls)."
fi

# 2. One User-Agent definition, in AO3AuthService (AO3RequestDefaults.userAgent).
#    Per-request headers override session defaults, forking the app's identity.
HITS=$(grep -rl "Mozilla/5.0" --include="*.swift" "$APP" | grep -v "Services/AO3AuthService.swift" || true)
if [ -n "$HITS" ]; then
  fail "User-Agent string defined outside AO3RequestDefaults" \
    "$HITS
Use AO3RequestDefaults.userAgent. docs/AO3_NETWORKING_POLICY.md."
fi

# 3. No new URLSessions talking to AO3 — all AO3 traffic goes through AO3Client
#    (pacing, retry, coalescing). The auth validator's session is the one exception.
HITS=$(grep -rl "URLSession(configuration" --include="*.swift" "$APP" \
  | grep -v "Services/AO3AuthService.swift" | grep -v "Services/AO3Client.swift" || true)
if [ -n "$HITS" ]; then
  fail "URLSession created outside AO3Client/AO3AuthService" \
    "$HITS
Route AO3 traffic through AO3Client. docs/AO3_NETWORKING_POLICY.md."
fi

# 4. Never name a @Model property isDeleted — collides with CoreData's reserved
#    NSManagedObject.isDeleted and silently resets on save (T-70).
if grep -q "var isDeleted" "$APP/Models/Models.swift"; then
  fail "@Model property named isDeleted in Models.swift" \
    "Use isPendingDeletion (the backup JSON key may stay isDeleted). docs/AGENT_ONBOARDING.md."
fi

# 5. The derived search index never travels in backups and never bumps sync
#    timestamps (a reindex must not look like a user edit to merge rules).
if grep -q "searchText" "$APP/Services/KudosBackup.swift"; then
  fail "searchText referenced in KudosBackup.swift" \
    "The index is derived state; restore rebuilds it. docs/DATA_AND_PERSISTENCE_INVARIANTS.md."
fi
if grep -q "\.markModified(" "$APP/Services/WorkSearchIndex.swift"; then
  fail "markModified called inside WorkSearchIndex" \
    "Reindexing must not win sync merges. docs/DATA_AND_PERSISTENCE_INVARIANTS.md."
fi

# 6. No force-try / force-cast in app code (test code may use them).
HITS=$(grep -rn "try! \|as! " --include="*.swift" "$APP" || true)
if [ -n "$HITS" ]; then
  fail "try!/as! in app code" "$HITS"
fi

# 7. The placeholder bundle-id must never return (App ID conflicts, T-note bcfe335).
HITS=$(grep -rln "devplaceholder" "$APP" "$ROOT/AO3_App_OpenSource.xcodeproj/project.pbxproj" || true)
if [ -n "$HITS" ]; then
  fail "devplaceholder identifier reappeared" "$HITS"
fi

# 8. Destructive write pattern: never remove a sync/backup destination before
#    writing its replacement (destroyed-only-copy window, T-73). Heuristic: the
#    folder-sync writer must keep using replaceItemAt.
if ! grep -q "replaceItemAt" "$APP/Services/FolderSyncService.swift"; then
  fail "FolderSyncService no longer stages+replaces its package write" \
    "Failed writes must leave the previous package intact. docs/DATA_AND_PERSISTENCE_INVARIANTS.md."
fi

# 9. Every Package.resolved pin has a bundled license notice (A10-F1): the GPL
#    text and the third-party notices file must exist inside the synced
#    kudos-ao3-reader/ folder (so Xcode actually bundles them as resources),
#    the bundled GPL copy must stay byte-identical to the root LICENSE, and
#    every pinned package identity must appear in ThirdPartyNotices.txt.
LEGAL="$APP/Legal"
RESOLVED="$ROOT/AO3_App_OpenSource.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [ ! -f "$LEGAL/LICENSE.txt" ]; then
  fail "kudos-ao3-reader/Legal/LICENSE.txt is missing" \
    "The bundled GPL text is required for release distribution. docs/RELEASE_READINESS_FABLE5.md (A10-F1)."
elif ! diff -q "$ROOT/LICENSE" "$LEGAL/LICENSE.txt" >/dev/null 2>&1; then
  fail "kudos-ao3-reader/Legal/LICENSE.txt has drifted from the root LICENSE" \
    "Re-copy the root LICENSE into the bundled resource. docs/RELEASE_READINESS_FABLE5.md (A10-F1)."
fi
if [ ! -f "$LEGAL/ThirdPartyNotices.txt" ]; then
  fail "kudos-ao3-reader/Legal/ThirdPartyNotices.txt is missing" \
    "Bundled dependency notices are required for release distribution. docs/RELEASE_READINESS_FABLE5.md (A10-F1)."
elif [ -f "$RESOLVED" ]; then
  IDENTITIES=$(grep '"identity"' "$RESOLVED" | sed -E 's/.*"identity" *: *"([^"]+)".*/\1/')
  for id in $IDENTITIES; do
    if ! grep -qi "Package identity: $id\$" "$LEGAL/ThirdPartyNotices.txt"; then
      fail "Package.resolved identity '$id' has no ThirdPartyNotices.txt entry" \
        "Add its license/copyright text so every distributed dependency is credited. docs/RELEASE_READINESS_FABLE5.md (A10-F1)."
    fi
  done
fi

if [ "$FAIL" -ne 0 ]; then
  echo "check-invariants: FAILED"
  exit 1
fi
echo "check-invariants: OK"
