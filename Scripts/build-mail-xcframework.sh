#!/usr/bin/env bash
# Build kudos-mail-ffi as an xcframework and generate its Swift bindings.
#
# The crate is the one place that touches a user's mailbox, and the whole point
# of its boundary is that the app receives `Ao3Event` values and no type that
# can hold a mail message. That property only holds if the app links THIS
# library rather than a hand-copied subset, so this script is the only
# supported way to produce it.
#
# Output:
#   build/KudosMail.xcframework — ignored device + simulator build artifact
#   kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift — tracked binding
#
# Usage: Scripts/build-mail-xcframework.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
CRATE="$ROOT/kudos-mail-core"
OUT="$ROOT/build"
GENERATED="$ROOT/build/Generated"
TRACKED_BINDING="$ROOT/kudos-ao3-reader/Generated/KudosMail/kudos_mail_core.swift"
LIB=libkudos_mail_ffi.a

# rustup's shims are not always on a GUI-launched PATH.
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
# Match the app target instead of inheriting the currently installed SDK version.
export IPHONEOS_DEPLOYMENT_TARGET=26.5

for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  if ! rustup target list --installed | grep -qx "$target"; then
    echo "installing missing Rust target: $target"
    rustup target add "$target"
  fi
done

echo "building the FFI crate for device and simulator"
cd "$CRATE"
cargo build -p kudos-mail-ffi --target aarch64-apple-ios --release
cargo build -p kudos-mail-ffi --target aarch64-apple-ios-sim --release

echo "generating Swift bindings from the built library"
rm -rf "$GENERATED"
mkdir -p "$GENERATED"
# Generate from the SIMULATOR slice: the bindings are identical across slices,
# and the simulator one is what the test target links.
cargo run --quiet -p kudos-mail-ffi --features bindgen --bin uniffi-bindgen -- \
  generate --library "target/aarch64-apple-ios-sim/release/$LIB" \
  --language swift --out-dir "$GENERATED" --no-format

# The app target is cross-platform, while this static library is iOS-only.
# Normalize generator whitespace so the repository whitespace gate stays useful.
mkdir -p "$(dirname "$TRACKED_BINDING")"
awk '
  BEGIN { print "#if os(iOS)\n" }
  { sub(/[[:space:]]+$/, ""); print }
  END { print "\n#endif" }
' "$GENERATED/kudos_mail_core.swift" > "$TRACKED_BINDING.tmp"
mv "$TRACKED_BINDING.tmp" "$TRACKED_BINDING"

# UniFFI emits a modulemap whose name must match the framework's module. Xcode
# compiles the .swift from the synchronized group and links the xcframework, so
# the header and modulemap belong with the framework, not the app sources.
HEADERS="$OUT/headers"
# In a folder named after the module: Xcode copies every xcframework's headers
# into the same BUILT_PRODUCTS_DIR/include, so a bare module.modulemap collides
# with any other library's (FluidAudio's NemoTextProcessing ships one). Clang
# finds <include>/<ModuleName>/module.modulemap on its own.
MODULE_HEADERS="$HEADERS/kudos_mail_coreFFI"
rm -rf "$OUT/KudosMail.xcframework" "$HEADERS"
mkdir -p "$MODULE_HEADERS"
mv "$GENERATED"/*.h "$MODULE_HEADERS"/ 2>/dev/null || true
if compgen -G "$GENERATED/*.modulemap" > /dev/null; then
  mv "$GENERATED"/*.modulemap "$MODULE_HEADERS/module.modulemap"
fi

echo "assembling the xcframework"
xcodebuild -create-xcframework \
  -library "$CRATE/target/aarch64-apple-ios/release/$LIB" -headers "$HEADERS" \
  -library "$CRATE/target/aarch64-apple-ios-sim/release/$LIB" -headers "$HEADERS" \
  -output "$OUT/KudosMail.xcframework"

echo
echo "xcframework: $OUT/KudosMail.xcframework"
echo "swift binding: $TRACKED_BINDING"
