#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# EDIT: RUN the test runner that mayhem/build.sh produced, then map its output to counts.
#   ctest:        (cd build-tests && ctest) ; parse "<P> tests passed, <F> failed out of <T>"
#   gtest binary: ./build-tests/<prog> ; parse "[==========] N ... ran." / "[  PASSED  ] P" / "[ SKIPPED ] S"
#   make/minunit: ./out/<runner> ; parse its pass/fail/total
# Do NOT compile here — if the runner is absent, fail (build.sh should have produced it).

# Run the prebuilt libtest binaries (built by mayhem/build.sh with normal flags,
# recorded in mayhem/test-bins.txt) and sum their libtest summaries:
#   test result: ok. <P> passed; <F> failed; <I> ignored; ...
# A binary that emits no parseable libtest summary counts as a failure (a neutered
# exit(0) binary produces no summary, so the oracle fails — behavioral, not exit-0).
[ -f mayhem/test-bins.txt ] || { echo "FATAL: mayhem/test-bins.txt missing — build.sh did not build the test suite" >&2; emit_ctrf cargo-test 0 1; exit 1; }

TP=0; TF=0; TI=0
while IFS= read -r bin; do
  [ -n "$bin" ] || continue
  if [ ! -x "$bin" ]; then echo "MISSING test binary: $bin" >&2; TF=$((TF+1)); continue; fi
  out="$("$bin" 2>&1)"; rc=$?
  echo "$out" | tail -5
  sum="$(echo "$out" | grep -E '^test result:' | tail -1)"
  if [ -z "$sum" ]; then
    echo "NO libtest summary from $bin (rc=$rc) — counting as failure" >&2
    TF=$((TF+1)); continue
  fi
  p="$(echo "$sum" | sed -nE 's/.* ([0-9]+) passed.*/\1/p')"
  f="$(echo "$sum" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
  i="$(echo "$sum" | sed -nE 's/.* ([0-9]+) ignored.*/\1/p')"
  TP=$((TP+${p:-0})); TF=$((TF+${f:-0})); TI=$((TI+${i:-0}))
  [ "$rc" -eq 0 ] || TF=$((TF+1))
done < mayhem/test-bins.txt

# Guard: upstream ships a real unit-test suite; if nothing ran, something is broken.
if [ "$TP" -eq 0 ] && [ "$TF" -eq 0 ]; then
  echo "FATAL: zero tests executed" >&2
  emit_ctrf cargo-test 0 1; exit 1
fi

# NOTE: upstream doc tests are not run here (rustdoc compiles them at run time,
# violating the no-compile contract); they are counted as skipped.
emit_ctrf cargo-test "$TP" "$TF" "$TI"
