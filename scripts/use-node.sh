#!/usr/bin/env bash
# Put a Node that can build the app first on PATH: 22.12 or later. Electron 44 needs 22,
# and electron-builder require()s ES modules, which Node only allows from 22.12 on (an
# older one fails with ERR_REQUIRE_ESM while building the .dmg).
#
#   . scripts/use-node.sh                 in a script: fixes PATH, or exits with a message
#   scripts/use-node.sh <command> [args]  run one command with that Node (package.json)
#
# nvm refuses to run while npm_config_prefix (or PREFIX) is set, which some shell profiles
# and conda environments do; the build has no use for either, so they are dropped here.
# Should nvm still not work, a Node it has installed is found by its path.
node_ok() {
  "${1:-node}" -e 'const [a, b] = process.versions.node.split(".").map(Number); process.exit(a > 22 || (a === 22 && b >= 12) ? 0 : 1)' 2>/dev/null
}
if ! node_ok; then
  unset npm_config_prefix NPM_CONFIG_PREFIX PREFIX
  if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
    case $- in *u*) _nounset=1 ;; *) _nounset=0 ;; esac
    set +u
    # shellcheck disable=SC1091
    . "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1 || true
    nvm use >/dev/null 2>&1 || nvm install >/dev/null 2>&1 || true
    [ "$_nounset" = 1 ] && set -u
    unset _nounset
  fi
  if ! node_ok; then
    for dir in "${NVM_DIR:-$HOME/.nvm}"/versions/node/v2[2-9]*/bin "${NVM_DIR:-$HOME/.nvm}"/versions/node/v[3-9][0-9]*/bin; do
      [ -x "$dir/node" ] && node_ok "$dir/node" && PATH="$dir:$PATH"
    done
    export PATH
  fi
fi
if ! node_ok; then
  echo "Node 22.12 or later is required; found $(node -v 2>/dev/null || echo none). Install it with 'nvm install 22'." >&2
  exit 1
fi
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ $# -gt 0 ]; then
  exec "$@"
fi
