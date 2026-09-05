#!/usr/bin/env bash
# The one entry point for this repository's checks.
#
#   ./scripts/check.sh
#
# One step, and a red one stops the run: build.sh in the root analyses, formats and tests every
# package of this tree, which is what .github/workflows/checks.yml runs on a push and what the
# release of ansiwise-cli runs once more before it builds a binary.
#
# Windows entry point: check.ps1 beside this file. It is a shim that starts THIS file, so there
# is no second spelling of these checks that could answer differently.
set -uo pipefail

root="$(git rev-parse --show-toplevel)" || exit 1
cd "$root" || exit 1

fail() { echo "check: FAIL — $1"; exit 1; }

echo "check: every package analysed, formatted and tested."

# dart is named here rather than left to build.sh. build.sh runs each package in a subshell, so a
# missing dart reaches the screen as "dart: command not found" under a package heading, and the
# run then walks the ten behind it and says a package is red. A skipped check must never read
# like a check that ran.
command -v dart >/dev/null 2>&1 \
  || fail "bash build.sh — dart is not on this machine, so no package was analysed, formatted or tested. The version this organisation pins stands in ../ansiwise-core/tool/gate/pins.dart."

bash build.sh || fail "bash build.sh — a package above is red."

echo "check: OK — every check green"
