# A60: code the JVM tests pass that an Android device would fail

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file: `docs/android-port/audits/A60-result.md`.
**Write the priority list first and keep it current.** Do not edit `TASKS.md`.

Android: this worktree (lane HEAD named in the dispatch). `minSdk = 26`, `targetSdk = 37`, core
library desugaring on. The unit tests run on a desktop JVM (with Robolectric for some), so code
that only an Android runtime rejects passes the gate. **It has happened:** a regex built with
Java's Unicode-class flag (`(?U)`) passed every test and crashed the comment composer on a
device, because Android's `java.util.regex` is ICU-backed (fixed `5a74078c`; a source check
now bans that flag).

Find every other place of this kind in `android/app/src/main/java`. Look at least for:

1. **Regex** that ICU rejects or reads differently from the JDK: inline flags, `\p{java…}`,
   `\p{Is…}`/`\p{In…}` names ICU spells otherwise, possessive or atomic groups, `\R`, `\X`,
   `\h`/`\v`, named groups, `Pattern` flags, `String.split`/`replace` with patterns, and the
   meaning of `\s`, `\w`, `\b`, `.` (ICU's are Unicode-aware by default; the JDK's are ASCII).
   Quote each pattern and say what a device does with it.
2. **APIs above API 26 or absent from Android**, used without a version check or desugaring:
   `java.time` beyond what desugaring covers, `java.nio.file` members, `String`/`Collection`
   methods from later JDKs (`String.repeat`, `strip`, `lines`, `isBlank` on `String`,
   `List.of` and friends, `Stream.toList`), `HttpClient`, `ProcessHandle`, `java.awt`, etc.
3. **Locale and charset**: `lowercase()`/`uppercase()` without a locale where a Turkish or
   other locale would change the result (keys, URLs, tag names, comparisons); `String.format`
   or `%,d` where a key or URL, not display text, is built; default-charset I/O.
4. **Files and process**: paths or permissions Android's sandbox forbids (hard links were
   already found and removed), `File.deleteOnExit`, temp-dir assumptions.
5. Anything else of the same kind you find.

For each finding: quote the code (`path:line`), say exactly what a device does (crash, wrong
result) and on which API levels, rate it (P1 crash or data loss, P2 wrong result, P3 cosmetic)
and suggest the smallest fix. Say plainly where something looks risky but is fine on Android
(e.g. `\p{InCombiningDiacriticalMarks}` is supported). The priority list first.
