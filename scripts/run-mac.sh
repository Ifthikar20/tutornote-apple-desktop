#!/usr/bin/env bash
# Build Tutornote for the Mac and open it, with its logs in this terminal.
#
#   scripts/run-mac.sh                          the live site, packaged .app
#   scripts/run-mac.sh http://<test-server>/     a test server instead
#   scripts/run-mac.sh --dev [url]              from source with Electron, no .app (fastest)
#   scripts/run-mac.sh --dist [url]             also build the universal .dmg
#   scripts/run-mac.sh --key [url]              ask for the maintenance-gate team key first
#   scripts/run-mac.sh --renderer [url]         rebuild the bundled web app first (scripts/build-renderer.sh)
#   scripts/run-mac.sh --site [url]             load the site in the window instead of the bundle
#
# Environment: ANOTHERNOTES_URL and ANOTHERNOTES_API_URL as in the README, and
# ANOTHERNOTES_PREVIEW_KEY (the gate key; stored by the app on first use, see README).
# Ctrl-C here quits the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE=pack
ASK_KEY=0
RENDERER=auto
for arg in "$@"; do
  case "$arg" in
    --dev) MODE=dev ;;
    --dist) MODE=dist ;;
    --key) ASK_KEY=1 ;;
    --renderer) RENDERER=build ;;
    --site) RENDERER=site ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) export ANOTHERNOTES_URL="$arg" ;;
  esac
done

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# 1. Node 22.12 or later (scripts/use-node.sh: uses nvm and .nvmrc if the shell has an older one).
# shellcheck disable=SC1091
. scripts/use-node.sh
say "node $(node -v), npm $(npm -v)"

# 2. Dependencies, including the Electron binary (missing when npm ci ran under an old Node).
if [ ! -d node_modules ] || ! node -e "require('electron')" >/dev/null 2>&1; then
  say "installing dependencies"
  npm ci
fi

# 3. codesign refuses files carrying Finder or iCloud metadata, and iCloud Drive stamps
#    everything under a synced folder (Desktop, Documents). Keep the build output elsewhere.
in_icloud() {
  local d="$1"
  while [ "$d" != "/" ]; do
    xattr -l "$d" 2>/dev/null | grep -q 'com.apple.file-provider' && return 0
    d="$(dirname "$d")"
  done
  return 1
}
if [ "$MODE" != dev ] && [ ! -L release ] && in_icloud "$ROOT"; then
  OUT="$HOME/Library/Caches/anothernotes-release"
  say "project is in an iCloud-synced folder; building into $OUT (release -> symlink)"
  rm -rf release
  mkdir -p "$OUT"
  ln -s "$OUT" release
fi

# 4. The app allows one running copy; a second launch would quit silently. (It was
#    AnotherNote before the rename, and AnotherNotes until 0.1.0; a copy from then may still be running.)
DEV_BIN="$ROOT/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"
if pgrep -x Tutornote >/dev/null || pgrep -x AnotherNote >/dev/null || pgrep -x AnotherNotes >/dev/null || pgrep -f "$DEV_BIN" >/dev/null; then
  say "quitting the running copy"
  pkill -x Tutornote 2>/dev/null || true
  pkill -x AnotherNote 2>/dev/null || true
  pkill -x AnotherNotes 2>/dev/null || true
  pkill -f "$DEV_BIN" 2>/dev/null || true
  sleep 1
fi

# 5. The maintenance-gate key, typed here so it never lands in shell history.
if [ "$ASK_KEY" = 1 ] && [ -z "${ANOTHERNOTES_PREVIEW_KEY:-}" ]; then
  read -rs -p "Team key (hidden): " ANOTHERNOTES_PREVIEW_KEY
  echo
  export ANOTHERNOTES_PREVIEW_KEY
fi

# 6. The web app's bundle, served from the app's own origin (src/main/renderer.ts). Built
#    when missing or asked for; --site skips it and loads the site in the window instead.
case "$RENDERER" in
  site) export ANOTHERNOTES_SITE=1 ;;
  build) scripts/build-renderer.sh ;;
  auto) [ -f renderer/index.html ] || scripts/build-renderer.sh ;;
esac

# 7. Build, then run in the foreground: the app prints its own and the web app's console
#    output here. ELECTRON_ENABLE_LOGGING=1 in the environment adds Chromium's own.
say "app URL: ${ANOTHERNOTES_URL:-https://tutornote.ai/dashboard (default)}"
case "$MODE" in
  dev)
    say "building from source and starting Electron"
    npm run build
    exec node_modules/.bin/electron .
    ;;
  pack)
    say "building release/<arch>/Tutornote.app"
    npm run pack
    ARCH_DIR="mac-$(uname -m | sed 's/x86_64/x64/')"
    [ -d "release/$ARCH_DIR" ] || ARCH_DIR=mac
    APP="release/$ARCH_DIR/Tutornote.app"
    ;;
  dist)
    say "building the universal .app and .dmg"
    npm run dist:mac
    APP="release/mac-universal/Tutornote.app"
    ls -1 release/*.dmg
    ;;
esac
say "starting $APP"
exec "$APP/Contents/MacOS/Tutornote"
