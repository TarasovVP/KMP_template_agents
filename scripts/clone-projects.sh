#!/usr/bin/env bash
# Clone the five KMP_template_* repositories from GitHub INTO the harness root, one directory per repository.
# Directories that already exist are skipped. Needs only git.
# Usage: scripts/clone-projects.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="TarasovVP"
fail=0
for name in KMP_template_shared KMP_template_android KMP_template_ios KMP_template_desktop KMP_template_web; do
  if [ -e "$ROOT/$name" ]; then
    echo "skip $name: $ROOT/$name already exists"
    continue
  fi
  echo "clone $name"
  git clone "https://github.com/$OWNER/$name.git" "$ROOT/$name" || { echo "FAILED: $name" >&2; fail=1; }
done
exit "$fail"
