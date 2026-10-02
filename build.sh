#!/usr/bin/env bash
# =============================================================================
# build.sh — prove every package of this repository locally. It is the one
# runner: .github/workflows/checks.yml calls this file rather than spelling a
# loop of its own.
# =============================================================================
#
# THIS REPOSITORY BUILDS NOTHING. It holds the steps that touch a real machine,
# as passive parts of ansiwise-cli: no binary, no release, no tag of its own.
# "Building" it means proving it — analysing, formatting and testing every
# package that carries tests.
#
# ONE MANIFEST PER PACKAGE, BECAUSE THAT IS HOW THEY STAND. Eleven packages
# share this tree and each carries its own manifest, so each is resolved and
# judged against its own. A single run at the root would resolve one dependency
# graph for all of them and report about a thing that does not exist.
#
# THEY RUN AT ONCE, BECAUSE EACH ONE IS A PROCESS OF ITS OWN. What a package
# costs is mostly start-up that nothing here can shorten: a resolver, an
# analyzer, a formatter and a test runner, each started again for the next
# package. Started together those waits overlap instead of adding up, and the
# tree is judged in a fraction of the time without one package boundary moving.
#
# THE RESOLVER RUNS ALONE, BECAUSE THE PUB CACHE IS ONE DIRECTORY. pub keeps a
# git dependency as one checkout per ref under $PUB_CACHE/git and holds git's
# index lock while it checks that ref out. Eleven resolvers reaching for the
# same ref at once meet on that lock, and all but the first die on it. A sibling
# checkout hides this: pubspec_overrides.yaml answers the pin from a path and
# nothing is cloned. So every package is resolved first, one after another, and
# only the judging runs at once. After the first package the resolve is a cache
# hit and costs nothing worth overlapping.
#
# EVERY PACKAGE RUNS BEFORE ANYTHING IS REPORTED, so one red package does not
# hide the state of the ten behind it. Each run writes to a file of its own and
# is printed whole, in directory order — eleven runs writing to one screen at
# once interleave into a log nobody can read a failure out of.
#
# Windows entry point: build.ps1 in this folder. It is a shim that starts
# THIS file, so there is no second spelling of this build to keep true.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

packages=()
for manifest in */pubspec.yaml; do
  package="${manifest%/pubspec.yaml}"
  [ -d "$package/test" ] || continue
  (cd "$package" && dart pub get >/dev/null)
  packages+=("$package")
done

runs=()
for package in "${packages[@]}"; do
  (
    cd "$package"
    dart analyze --fatal-infos
    dart format --output=none --set-exit-if-changed .
    dart test
  ) >"$logs/$package" 2>&1 &
  runs+=("$!")
done

failed=0
index=0
while [ "$index" -lt "${#packages[@]}" ]; do
  echo "build: ${packages[$index]}"
  wait "${runs[$index]}" || failed=1
  cat "$logs/${packages[$index]}"
  index=$((index + 1))
done

test "$failed" -eq 0 || { echo "build: FAIL — a package above is red" >&2; exit 1; }
echo "build: OK — every package of this repository is green"
