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
#    writing its replacement (destroyed-only-copy window, T-73). Heuristic since
#    T-139's incremental sync directory: every per-file write in the folder-sync
#    writer must stay atomic (temp + rename), so a failed write leaves the
#    previous manifest/asset intact. Covered end-to-end by
#    FolderSyncTests/failedSyncUpWritePreservesExistingRemoteManifest.
if ! grep -q "options: .atomic" "$APP/Services/FolderSyncService.swift"; then
  fail "FolderSyncService no longer writes sync files atomically" \
    "Failed writes must leave the previous manifest intact. docs/DATA_AND_PERSISTENCE_INVARIANTS.md."
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

# The app must own an accent colour. Without one, its default tint is the *system*
# blue, and any view that renders without inheriting an explicit `.tint(...)` — which
# is what happens when a presentation is dismissed and rows re-render — shows a blue
# icon next to themed text. Both halves are required: the asset, and the build setting
# that makes it the global accent.
ACCENT="$ROOT/kudos-ao3-reader/Assets.xcassets/AccentColor.colorset/Contents.json"
if [ ! -f "$ACCENT" ]; then
  fail "kudos-ao3-reader/Assets.xcassets/AccentColor.colorset is missing" \
    "Without it the app's default tint is the system blue; icons revert to it on re-render. See ContentView.applyWindowTint."
elif ! grep -q "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;" \
  "$ROOT/AO3_App_OpenSource.xcodeproj/project.pbxproj"; then
  fail "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME is not set to AccentColor" \
    "The asset exists but is not wired as the global accent, so the default tint is still the system blue."
fi


# --- Signing-identity leak guard (repo is PUBLIC) -----------------------------
# NQH85H7343 is the owner's real Apple Developer team ID (confirmed via issued
# Apple Distribution / Developer ID Application certs, 2026-08-16) and the
# owner has explicitly decided it is fine to keep tracked in project.pbxproj —
# a team ID isn't a credential, it can't authenticate or authorize anything on
# its own, and it's already embedded in every shipped build's provisioning
# profile. Do not "fix" this by scrubbing it; that decision was made
# deliberately, not by oversight.
#
# What this guard actually protects against: a DIFFERENT, unreviewed signing
# identity ending up in a tracked file. That did happen once — `codesign -dv`
# / `security find-identity` output was pasted verbatim into a Markdown
# report, embedding "Apple Development: <email> (<TEAMID>)" for a *different*
# team than the one below. Docs are checked too, not just the project file.
# This is an ALLOW-list on purpose: it never names a value being protected, so
# the guard itself cannot leak anything new.
PUBLIC_PLACEHOLDER_TEAM="NQH85H7343"   # the real team ID; owner-approved to stay public

BAD_TEAM_LINES="$(grep -nE 'DEVELOPMENT_TEAM = [^";]' "$ROOT/AO3_App_OpenSource.xcodeproj/project.pbxproj" \
  | grep -v "DEVELOPMENT_TEAM = ${PUBLIC_PLACEHOLDER_TEAM};" || true)"
if [ -n "$BAD_TEAM_LINES" ]; then
  fail "project.pbxproj pins a DEVELOPMENT_TEAM that is not the public placeholder" \
    "Xcode writes the signing team here when you add a capability. Set it locally via an untracked xcconfig instead. Offending: ${BAD_TEAM_LINES}"
fi

# Any pasted codesign / security output that carries a 10-char team ID in parens.
LEAKED_IDENTITY="$(grep -rInE 'Apple (Development|Distribution|Developer ID [A-Za-z]+): .*\([A-Z0-9]{10}\)' \
  "$ROOT" --include='*.md' --include='*.sh' --include='*.swift' --include='*.kt' --include='*.yml' \
  --exclude-dir=.git --exclude-dir=DerivedData --exclude-dir=build 2>/dev/null || true)"
if [ -n "$LEAKED_IDENTITY" ]; then
  fail "a signing identity with a team ID is embedded in a tracked file" \
    "Redact the team ID before committing (this repo is public). Offending: ${LEAKED_IDENTITY}"
fi

# Entitlements files must reference the team via the build-setting variable,
# never a literal 10-char team ID (e.g. the ubiquity-kvstore-identifier entitlement
# needs $(TeamIdentifierPrefix)$(CFBundleIdentifier), not a hardcoded value).
BAD_ENTITLEMENT_TEAM="$(grep -rlnE '<string>[A-Z0-9]{10}\.' "$ROOT" --include='*.entitlements' \
  --exclude-dir=.git 2>/dev/null || true)"
if [ -n "$BAD_ENTITLEMENT_TEAM" ]; then
  fail "an entitlements file has a literal team-ID prefix instead of \$(TeamIdentifierPrefix)" \
    "Offending: ${BAD_ENTITLEMENT_TEAM}"
fi

# The local signing override must stay untracked. If it is ever force-added,
# whatever team ID it holds becomes part of history the moment it's committed.
if git -C "$ROOT" ls-files --error-unmatch "Config/LocalSigning.xcconfig" >/dev/null 2>&1; then
  fail "Config/LocalSigning.xcconfig is tracked by git" \
    "This file is gitignored on purpose — it holds the local (possibly paid) signing team ID. Untrack it: git rm --cached Config/LocalSigning.xcconfig."
fi

if [ "$FAIL" -ne 0 ]; then
  echo "check-invariants: FAILED"
  exit 1
fi
echo "check-invariants: OK"
