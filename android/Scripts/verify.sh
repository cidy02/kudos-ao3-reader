#!/bin/sh
# Android definition of done — analogue of repo Scripts/verify.sh for the
# kudos-ao3-reader-android product line. Run from anywhere.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export PATH="$JAVA_HOME/bin:${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

if [ ! -f "$ROOT/local.properties" ]; then
  echo "sdk.dir=$ANDROID_HOME" > "$ROOT/local.properties"
fi

echo "== 1/5 invariants =="
"$ROOT/Scripts/check-invariants.sh"

echo "== 2/5 unit tests =="
(cd "$ROOT" && ./gradlew :app:testDebugUnitTest --console=plain)

echo "== 3/5 compile + assembleDebug =="
(cd "$ROOT" && ./gradlew :app:assembleDebug --console=plain)

echo "== 4/5 persistence subset (serial smoke) =="
(cd "$ROOT" && ./gradlew :app:testDebugUnitTest \
  --tests 'io.github.cidy02.kudos.backup.*' \
  --tests 'io.github.cidy02.kudos.reader.*' \
  --tests 'io.github.cidy02.kudos.network.ao3.AO3NetworkingCoreTest' \
  --tests 'io.github.cidy02.kudos.files.*' \
  --tests 'io.github.cidy02.kudos.works.*' \
  --console=plain)

echo "== 5/5 whitespace =="
if command -v git >/dev/null 2>&1; then
  git -C "$ROOT/.." diff --check || true
fi

echo "android verify: ALL GREEN"
