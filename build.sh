#!/usr/bin/env bash
# =============================================================================
# build.sh — prove every package of this repository locally, the way
# .github/workflows/checks.yml does.
# =============================================================================
#
# THIS REPOSITORY BUILDS NOTHING. It holds the steps that touch a real machine,
# as passive parts of ansiwise-cli: no binary, no release, no tag of its own.
# "Building" it means proving it — analysing, formatting and testing every
# package that carries tests.
#
# ONE PACKAGE AT A TIME, BECAUSE THAT IS HOW THEY STAND. A dozen packages share
# this tree and each carries its own manifest. A single run at the root would
# resolve one dependency graph for all of them and report about a thing that does
# not exist.
#
# EVERY PACKAGE RUNS BEFORE ANYTHING IS REPORTED, so one red package does not
# hide the state of the eleven behind it.
#
# Windows twin: build.ps1 in this folder. The two are held to answering
# identically.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

failed=0
for manifest in */pubspec.yaml; do
  package="${manifest%/pubspec.yaml}"
  [ -d "$package/test" ] || continue
  echo "build: $package"
  (
    cd "$package"
    dart pub get >/dev/null
    dart analyze --fatal-infos
    dart format --output=none --set-exit-if-changed .
    dart test
  ) || failed=1
done
test "$failed" -eq 0 || { echo "build: FAIL — a package above is red" >&2; exit 1; }
echo "build: OK — every package of this repository is green"
