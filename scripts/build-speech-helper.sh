#!/usr/bin/env bash
# Build the Mac speech helper (helpers/speech/main.swift) into build/helpers/tutornote-speech:
# the app runs it for dictation and Teach mode (src/main/speech.ts), and electron-builder
# packages it into Tutornote.app/Contents/Resources (electron-builder.config.cjs).
#
# A universal binary (arm64 + x86_64) when the toolchain can make one, else this Mac's
# own. Not on macOS, or without the Xcode command line tools (xcode-select --install),
# there is no helper: the app still runs, and dictation goes through the server's whisper
# as it did before. `npm run build` runs this; it is a no-op when the helper is current.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/helpers/speech/main.swift"
PLIST="$ROOT/helpers/speech/Info.plist"
OUT_DIR="$ROOT/build/helpers"
OUT="$OUT_DIR/tutornote-speech"
MIN_MACOS=12.0

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

if [ "$(uname -s)" != Darwin ]; then
  say "speech helper: macOS only, skipped"
  exit 0
fi
if ! xcrun -f swiftc >/dev/null 2>&1; then
  say "speech helper: no Swift compiler (xcode-select --install); dictation will use the server's whisper"
  exit 0
fi
if [ -x "$OUT" ] && [ "$OUT" -nt "$SRC" ] && [ "$OUT" -nt "$PLIST" ] && [ "$OUT" -nt "${BASH_SOURCE[0]}" ]; then
  say "speech helper: up to date ($OUT)"
  exit 0
fi

mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

built=()
for arch in arm64 x86_64; do
  # The Info.plist goes INSIDE the binary: macOS reads the helper's reasons for the
  # microphone and speech recognition from it (main.swift, "Its own responsible process").
  if xcrun swiftc -O -target "$arch-apple-macos$MIN_MACOS" -framework Speech -framework AVFoundation -framework Security \
       -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" \
       -o "$TMP/$arch" "$SRC" 2>"$TMP/$arch.log"; then
    built+=("$TMP/$arch")
  else
    # The host's own architecture must build; the other is a nice-to-have.
    if [ "$arch" = "$(uname -m | sed 's/x86_64/x86_64/;s/arm64/arm64/')" ]; then
      cat "$TMP/$arch.log" >&2
      echo "speech helper: build failed for $arch" >&2
      exit 1
    fi
    say "speech helper: no $arch build ($(tail -n1 "$TMP/$arch.log"))"
  fi
done

if [ "${#built[@]}" -gt 1 ]; then
  lipo -create -output "$OUT" "${built[@]}"
else
  cp "${built[0]}" "$OUT"
fi
chmod +x "$OUT"
# An ad-hoc signature so it runs from here (npm start); electron-builder signs the packaged copy.
codesign --force --sign - --identifier app.tutornote.desktop.speech "$OUT" >/dev/null 2>&1 || true
say "speech helper: built $OUT ($(lipo -archs "$OUT" 2>/dev/null || echo "$(uname -m)"))"
