#!/usr/bin/env bash
# Build the web app (tutornote-web) and copy its production bundle into renderer/, which the
# desktop app serves from its own origin and packages (src/main/renderer.ts). The work is
# scripts/build-renderer.mjs (as the Windows app's): a named, committed ref is exported with
# `git archive` and built outside the checkout, never its working tree. This finds Node 22 and
# takes the old names of its settings.
#
#   scripts/build-renderer.sh                                   ../tutornote-web, else a .web/ clone, at feature/october
#   TUTORNOTE_WEB_DIR=../tutornote-web scripts/build-renderer.sh   a checkout you already have
#   TUTORNOTE_WEB_REF=94ae3b7 scripts/build-renderer.sh         a branch, tag or commit
#
# (ANOTHERNOTES_WEB_DIR, ANOTHERNOTES_WEB_REF and ANOTHERNOTES_WEB_REPO, the names before, are
# taken too.) The build is `npm run build:off` (Turnstile off, API at the relative /api), the same
# profile deploy-aws.sh ships by default. renderer/BUILD names the commit and the UTC time:
#   <short sha> <time>Z
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "${ANOTHERNOTES_WEB_DIR:-}" ] && export TUTORNOTE_WEB_DIR="${TUTORNOTE_WEB_DIR:-$ANOTHERNOTES_WEB_DIR}"
[ -n "${ANOTHERNOTES_WEB_REF:-}" ] && export TUTORNOTE_WEB_REF="${TUTORNOTE_WEB_REF:-$ANOTHERNOTES_WEB_REF}"
[ -n "${ANOTHERNOTES_WEB_REPO:-}" ] && export TUTORNOTE_WEB_REPO="${TUTORNOTE_WEB_REPO:-$ANOTHERNOTES_WEB_REPO}"

# Node 22 or later, as in run-mac.sh: nvm and .nvmrc, with npm_config_prefix dropped for this
# script (nvm refuses to run with it set), else the Node 22 nvm installed, found by its path.
node_major() { node -v 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/'; }
if [ "$(node_major)" -lt 22 ] 2>/dev/null || ! command -v node >/dev/null; then
  unset npm_config_prefix NPM_CONFIG_PREFIX PREFIX
  if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
    set +u
    # shellcheck disable=SC1091
    . "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1 || true
    nvm use 22 >/dev/null 2>&1 || nvm install 22 >/dev/null 2>&1 || true
    set -u
  fi
  if [ "$(node_major)" -lt 22 ] 2>/dev/null || ! command -v node >/dev/null; then
    for dir in "${NVM_DIR:-$HOME/.nvm}"/versions/node/v2[2-9]*/bin "${NVM_DIR:-$HOME/.nvm}"/versions/node/v[3-9][0-9]*/bin; do
      [ -x "$dir/node" ] && PATH="$dir:$PATH"
    done
  fi
fi
if [ "$(node_major)" -lt 22 ] 2>/dev/null; then
  echo "Node 22 or later is required; found $(node -v 2>/dev/null || echo none). Install it with 'nvm install 22'." >&2
  exit 1
fi

exec node "$ROOT/scripts/build-renderer.mjs"
