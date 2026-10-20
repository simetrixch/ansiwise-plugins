#!/usr/bin/env bash
# =============================================================================
# build.sh — prove every package of this repository locally. It is the one
# runner: scripts/check.sh and the release of ansiwise-cli call this file
# rather than spelling a loop of their own.
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
# THEY OVERLAP, BECAUSE EACH ONE IS A PROCESS OF ITS OWN. What a package costs is
# mostly start-up that nothing here can shorten: a resolver, an analyzer, a
# formatter and a test runner, each started again for the next package. Started
# together those waits overlap instead of adding up, and the tree is judged in a
# fraction of the time without one package boundary moving.
#
# BUT ONLY A FEW AT A TIME, BECAUSE EACH ONE HOLDS MEMORY. The build of the
# binaries of ansiwise-cli runs this file in a pod of 3 GiB. With all eleven started at once the kernel killed some
# of them, and the run said a package was red that was only out of memory. So at
# most $jobs packages are judged at once; scripts/build.test.sh holds the number
# to that budget.
#
# THE RESOLVER RUNS ALONE, BECAUSE THE PUB CACHE IS ONE DIRECTORY. pub keeps a
# git dependency as one checkout per ref under $PUB_CACHE/git and holds git's
# index lock while it checks that ref out. Eleven resolvers reaching for the
# same ref at once meet on that lock, and all but the first die on it. A sibling
# checkout hides this: pubspec_overrides.yaml answers the pin from a path and
# nothing is cloned. So every package is resolved first, one after another, and
# only the judging overlaps. After the first package the resolve is a cache hit
# and costs nothing worth overlapping.
#
# EVERY PACKAGE RUNS BEFORE ANYTHING IS REPORTED, so one red package does not
# hide the state of the ten behind it. Each run writes to a file of its own and
# is printed whole, in directory order — eleven runs writing to one screen at
# once interleave into a log nobody can read a failure out of.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

jobs=3

logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

packages=()
for manifest in */pubspec.yaml; do
  package="${manifest%/pubspec.yaml}"
  [ -d "$package/test" ] || continue
  (cd "$package" && dart pub get >/dev/null)
  packages+=("$package")
done

judge() {
  (
    cd "$1"
    dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed . && dart test
  ) >"$logs/$1" 2>&1 || touch "$logs/$1.red"
}
export -f judge
export logs
printf '%s\n' "${packages[@]}" | xargs -n 1 -P "$jobs" bash -c 'judge "$1"' _

failed=0
for package in "${packages[@]}"; do
  echo "build: $package"
  cat "$logs/$package"
  if [ -e "$logs/$package.red" ]; then failed=1; fi
done

test "$failed" -eq 0 || { echo "build: FAIL — a package above is red" >&2; exit 1; }
echo "build: OK — every package of this repository is green"
