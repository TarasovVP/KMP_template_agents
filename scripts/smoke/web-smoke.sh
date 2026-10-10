#!/usr/bin/env bash
# Behavioural smoke for web, the one way to run it (build-all.sh uses this too). Does NOT run npm run build:
# the shared package is a symlink into KMP_template_shared/shared/build/dist, so after
# `./gradlew :shared:jsBrowserProductionLibraryDistribution` the smoke already sees the new code.
# Usage: scripts/smoke/web-smoke.sh <browser|node>
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
case "${1:-}" in browser|node) ;; *) echo "usage: web-smoke.sh <browser|node>" >&2; exit 2 ;; esac
[ "$#" -eq 1 ] || { echo "usage: web-smoke.sh <browser|node>" >&2; exit 2; }
exec node --preserve-symlinks "$ROOT/scripts/smoke/web-smoke.mjs" "$ROOT/KMP_template_web" "$1"
