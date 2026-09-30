You are implementing ONE bounded UI change in the Kudos iOS app (SwiftUI). Work ONLY in the current worktree/branch. Do not push, do not merge, do not touch main, never contact archiveofourown.org or any network service, never sign in. No new SwiftData fields. Do not edit AO3_App_OpenSource.xcodeproj/project.pbxproj (new .swift files are picked up automatically). Keep DEVELOPMENT_TEAM "" in the project.

Source of truth: docs/design/Final_Redesign_Spec.dc.html (artboards are <div class="dv-opt" id="1xx">; take exact sizes/colours from the inline styles). Owner decisions in code comments ("owner, 2026-…") and TASKS.md override the spec.

House rules:
- Reuse shared components: SubjectHeaderBlock, SectionRuleHeader, SubjectChip, SubjectStatStrip, SubjectPanel/subjectPanel, cardRow, screenTint, FandomDisplayName.bareTitle, Int.compactCount, layoutFreeHitTarget, UserFacingError.message(for:). Grep before writing a new one.
- Accent colour: `.tint` / palette, never Color.accentColor.
- Never put a modifier between a List row's .listRowInsets and the List (it drops the insets).
- 44pt hit targets via layoutFreeHitTarget (does not grow layout).
- Match surrounding code style and comment density. Swift 6.
Verification you must run before finishing (report the exact output lines):
  sh -c 'xcodebuild build-for-testing -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource -derivedDataPath $HOME/Library/Developer/Xcode/DerivedData/kudos-codex -clonedSourcePackagesDirPath $HOME/Library/Developer/Xcode/DerivedData/AO3_App_OpenSource-eteszxufmrtcfcgzcbknzgypadew/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO -destination "platform=iOS Simulator,id=A3E046C4-D517-4A71-88AC-E53252E4D5C4"' ; echo EXIT $?
  Scripts/lint.sh  (0 errors; do not add warnings)
The `Vendor` and `Packages` entries in this worktree are local symlinks — never `git add` them (commit with explicit file paths, never `git add -A` or `git add .`). Commit your change on this branch with a clear message ending in "Co-Authored-By: Codex <noreply@openai.com>". Final message: what changed (files), what you verified, anything you could not do.


## Sandbox note (2026-09-29)
Your sandbox cannot run xcodebuild (package cache is read-only) or write the worktree's git index.
Do not retry either. Verify with `Scripts/lint.sh` and `swiftc -parse` on the files you changed,
leave the change uncommitted, and list the changed files in your final message. Claude builds,
screenshots and commits. Use theme tokens (`glassFill`/`glassStroke`, `.secondary`, palette colours)
rather than the artboard's literal rgba values: the artboards are dark-theme only.
