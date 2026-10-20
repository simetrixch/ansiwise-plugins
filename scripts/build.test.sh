#!/usr/bin/env bash
# build.sh against a tree of stand-in packages and a stand-in dart: how many packages it judges at once, and that it still judges every
# one of them. The build of the binaries of ansiwise-cli runs build.sh in a pod of 3 GiB, and an analyzer, a formatter and a test runner of one package each hold
# memory; a bound read from here is what keeps all of them inside it.
#
#   ./scripts/build.test.sh
set -uo pipefail

root="$(git rev-parse --show-toplevel)" || exit 1
fail() { echo "build.test: FAIL — $1"; exit 1; }

# The most packages at once. Cold, under a cgroup of 3 GiB without swap, all eleven were killed for memory (six of them), three at a
# time peaked at 2.2 GiB and four at 2.4 GiB. The number lives in build.sh; this is the budget it is held to.
most=3

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Runs the build script given in a tree of eight packages that carry tests and one that does not. Leaves the exit status in $status,
# the output in $out, the most packages that were analysing at one moment in $peak, and the packages that ran tests in $tested.
# The package named in $2 fails its tests.
run_build() {
  local script="$1" red="${2:-}" repo="$work/repo.$RANDOM"
  mkdir -p "$repo/bin" "$repo/state"
  git -C "$repo" init -q
  for package in pkg-01 pkg-02 pkg-03 pkg-04 pkg-05 pkg-06 pkg-07 pkg-08; do
    mkdir -p "$repo/$package/test"
    : >"$repo/$package/pubspec.yaml"
  done
  mkdir -p "$repo/docs-only"
  : >"$repo/docs-only/pubspec.yaml"
  cp "$script" "$repo/build.sh"
  cat >"$repo/bin/dart" <<'DART'
#!/usr/bin/env bash
case "$1" in
  analyze)
    mkdir "$STATE/running.$$" || exit 1
    ls "$STATE" | grep -c '^running\.' >>"$STATE/seen"
    sleep 0.3
    rmdir "$STATE/running.$$"
    ;;
  test)
    basename "$PWD" >>"$STATE/tested"
    if [ "$(basename "$PWD")" = "$RED" ]; then echo "red: $RED"; exit 1; fi
    ;;
esac
DART
  chmod +x "$repo/bin/dart"
  (cd "$repo" && PATH="$repo/bin:$PATH" STATE="$repo/state" RED="$red" bash build.sh) >"$repo/out" 2>&1
  status=$?
  out="$(cat "$repo/out")"
  peak="$(sort -n "$repo/state/seen" | tail -n 1)"
  tested="$(sort "$repo/state/tested" | tr '\n' ' ')"
}

everything="pkg-01 pkg-02 pkg-03 pkg-04 pkg-05 pkg-06 pkg-07 pkg-08 "

run_build "$root/build.sh"
[ "$status" -eq 0 ] || fail "build.sh of a tree of green packages ended with $status: $out"
[ "$peak" -le "$most" ] || fail "build.sh analysed $peak packages at once, more than the $most the 3 GiB of the release build holds"
[ "$peak" -ge 2 ] || fail "build.sh analysed $peak package at once, so the packages no longer overlap their waits"
[ "$tested" = "$everything" ] || fail "build.sh tested '$tested', not every package that carries tests and no other"
[ "$(grep -o '^build: pkg-[0-9]*' <<<"$out" | sed 's/^build: //' | tr '\n' ' ')" = "$everything" ] || fail "build.sh did not print the log of every package in directory order"
[ "$(tail -n 1 <<<"$out")" = "build: OK — every package of this repository is green" ] || fail "build.sh did not end on its OK line: $out"
echo "build.test: ok — green packages ran at most $peak at once, and every package with tests was tested."

run_build "$root/build.sh" pkg-03
[ "$status" -ne 0 ] || fail "build.sh ended green with a package whose tests fail"
[ "$tested" = "$everything" ] || fail "a red package stopped the others: only '$tested' were tested"
grep -q '^red: pkg-03$' <<<"$out" || fail "build.sh did not print the log of the red package"
[ "$(tail -n 1 <<<"$out")" = "build: FAIL — a package above is red" ] || fail "build.sh did not end on its FAIL line: $out"
echo "build.test: ok — a red package fails the run after every other package was judged."

# Planted defects: the checks above must be able to go red.
for planted in 99 1; do
  sed "s/^jobs=[0-9]*\$/jobs=$planted/" "$root/build.sh" >"$work/planted.sh"
  cmp -s "$root/build.sh" "$work/planted.sh" && fail "the planted bound $planted changed nothing in build.sh, so the checks above prove nothing"
  run_build "$work/planted.sh"
  if [ "$planted" -gt "$most" ]; then
    [ "$peak" -gt "$most" ] || fail "PLANTED DEFECT: a bound of $planted analysed only $peak at once, so a bound above $most would pass unseen"
  else
    [ "$peak" -lt 2 ] || fail "PLANTED DEFECT: a bound of $planted analysed $peak at once, so a build without overlap would pass unseen"
  fi
done
echo "build.test: ok — a bound above $most and a bound of 1 are both seen."
