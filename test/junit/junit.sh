# shellcheck shell=sh
# test/junit/junit.sh -- per-script JUnit recording for the proof.yaml test
# commands, so `proof audit` (tests_pass, project.checks.test_results) can
# ingest ONE combined report and evidence packages carry observed
# per-obligation results (REQ:class:evidence tags joined to outcomes).
#
# Sourced (POSIX sh; safe under `set -e`) at the start of a
# project.commands.tests.<id>.command:
#
#   . test/junit/junit.sh; junit_begin <suite-id>
#   junit_run "$B" test/shell.d/foo-test.sh     # run one script = one <testcase>
#   junit_skip test/shell.d/bar-test.sh "requires lua"
#   node --test ... --test-reporter=junit --test-reporter-destination="$JUNIT_PART" ... || junit_fail $?
#   junit_end                                   # write the part, merge, return non-zero on any failure
#
# A failing script does not stop the suite: every script runs and gets its own
# <testcase> (with <failure> and an output excerpt), and junit_end returns 1,
# so the command still exits non-zero (fail-closed).
#
# WHERE THE REPORT GOES. <root>/.proof/test-results/junit.xml, merged from
# <root>/.proof/test-results/parts/<suite-id>.xml (must match
# project.checks.test_results.report_path). <root> is the audited checkout:
#   1. $PROOF_TEST_RESULTS_ROOT when set (explicit override);
#   2. else the nearest ancestor of the working directory holding proof.yaml
#      AND .git (a normal run from the checkout);
#   3. else the nearest such ancestor of an ANCESTOR PROCESS's working directory.
#      proof's bash/qml code-level MC/DC engines run the command inside an
#      instrumented temp copy of the tree (no .git, no .proof), so the report
#      must be written back to the checkout `proof audit` runs in.
# If no root is found the tests still run and gate; only the report is skipped
# (a warning on stderr; tests_pass then reports the missing report).
#
# RUN BOUNDARY. tests_pass deletes the report before a full run. The first
# suite that finds no report clears the stale parts, so the merged report only
# ever holds this run's suites.

_junit_is_root() { [ -f "$1/proof.yaml" ] && [ -e "$1/.git" ]; }

_junit_find_up() {
  _jd=$1
  while [ -n "$_jd" ] && [ "$_jd" != "/" ] && [ "$_jd" != "." ]; do
    if _junit_is_root "$_jd"; then
      printf '%s\n' "$_jd"
      return 0
    fi
    _jd=$(dirname -- "$_jd")
  done
  return 1
}

_junit_proc_cwd() {
  if [ -e "/proc/$1/cwd" ]; then
    readlink "/proc/$1/cwd" 2>/dev/null || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1
  fi
}

junit_root() {
  if [ -n "${PROOF_TEST_RESULTS_ROOT:-}" ]; then
    printf '%s\n' "$PROOF_TEST_RESULTS_ROOT"
    return 0
  fi
  _junit_find_up "$(pwd -P)" && return 0
  _jp=$$
  _ji=0
  while [ "$_ji" -lt 32 ]; do
    _jp=$(ps -o ppid= -p "$_jp" 2>/dev/null | tr -d ' ')
    case $_jp in '' | 0 | 1 | *[!0-9]*) return 1 ;; esac
    _jc=$(_junit_proc_cwd "$_jp")
    if [ -n "$_jc" ] && _junit_find_up "$_jc"; then
      return 0
    fi
    _ji=$((_ji + 1))
  done
  return 1
}

_junit_now() {
  _jn=$(date +%s.%N 2>/dev/null)
  case $_jn in *N* | '') date +%s ;; *) printf '%s\n' "$_jn" ;; esac
}

# XML-escape stdin; drop control characters XML 1.0 forbids (ANSI escapes).
_junit_esc() {
  tr -d '\000-\010\013\014\016-\037' | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

junit_begin() {
  JUNIT_SUITE=$1
  JUNIT_CASES=""
  JUNIT_TESTS=0
  JUNIT_FAILED=0
  JUNIT_SKIPPED=0
  JUNIT_RC=0
  JUNIT_START=$(_junit_now)
  JUNIT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/junit-$1.XXXXXX")
  JUNIT_ROOT=$(junit_root) || JUNIT_ROOT=""
  if [ -z "$JUNIT_ROOT" ]; then
    echo "junit: no checkout root found (proof.yaml + .git); test-results report not written for suite $1" >&2
    JUNIT_DIR=""
    JUNIT_PART=/dev/null
    return 0
  fi
  JUNIT_DIR="$JUNIT_ROOT/.proof/test-results"
  mkdir -p "$JUNIT_DIR/parts"
  if [ ! -f "$JUNIT_DIR/junit.xml" ]; then
    for _jf in "$JUNIT_DIR"/parts/*.xml; do
      [ -f "$_jf" ] && rm -f "$_jf"
    done
  fi
  JUNIT_PART="$JUNIT_DIR/parts/$1.xml"
  rm -f "$JUNIT_PART"
}

_junit_add_case() {
  # $1 file, $2 seconds, $3 inner xml (already escaped / empty)
  _jname=$(basename -- "$1" | _junit_esc)
  _jfile=$(printf '%s' "$1" | _junit_esc)
  if [ -n "$3" ]; then
    JUNIT_CASES="$JUNIT_CASES    <testcase name=\"$_jname\" classname=\"$JUNIT_SUITE\" file=\"$_jfile\" time=\"$2\">
$3
    </testcase>
"
  else
    JUNIT_CASES="$JUNIT_CASES    <testcase name=\"$_jname\" classname=\"$JUNIT_SUITE\" file=\"$_jfile\" time=\"$2\"/>
"
  fi
  JUNIT_TESTS=$((JUNIT_TESTS + 1))
}

# junit_run <command...>: run one test script; the LAST argument is the
# script path (repo-relative), which names the <testcase>.
junit_run() {
  for _jlast in "$@"; do :; done
  _jout="$JUNIT_TMP/out"
  _jerr="$JUNIT_TMP/err"
  _jt0=$(_junit_now)
  _jrc=0
  "$@" >"$_jout" 2>"$_jerr" || _jrc=$?
  _jt1=$(_junit_now)
  cat "$_jout"
  cat "$_jerr" >&2
  _jsecs=$(awk -v a="$_jt0" -v b="$_jt1" 'BEGIN { printf "%.3f", b - a }')
  if [ "$_jrc" -eq 0 ]; then
    _junit_add_case "$_jlast" "$_jsecs" ""
  else
    JUNIT_FAILED=$((JUNIT_FAILED + 1))
    JUNIT_RC=1
    echo "junit: FAIL $_jlast (exit $_jrc)" >&2
    _jmsg=$( { grep -E 'FAIL|not ok|Error|error:|expected' "$_jout" "$_jerr" 2>/dev/null | head -n 1; } | sed 's/^[^:]*://' | cut -c1-300 | _junit_esc)
    [ -n "$_jmsg" ] || _jmsg="exit status $_jrc"
    _jbody=$(cat "$_jout" "$_jerr" | tail -n 60 | _junit_esc)
    _junit_add_case "$_jlast" "$_jsecs" "      <failure type=\"exit $_jrc\" message=\"$_jmsg\">$_jbody</failure>"
  fi
  return 0
}

# junit_skip <script> <reason>: a script whose runtime is absent here.
junit_skip() {
  echo "SKIP $(basename -- "$1"): $2"
  JUNIT_SKIPPED=$((JUNIT_SKIPPED + 1))
  _junit_add_case "$1" "0" "      <skipped message=\"$(printf '%s' "$2" | _junit_esc)\"/>"
}

# junit_fail <rc>: record a non-zero exit of an external runner (node --test).
junit_fail() {
  JUNIT_RC=${1:-1}
  [ "$JUNIT_RC" -ne 0 ] || JUNIT_RC=1
  return 0
}

junit_end() {
  _jrc=$JUNIT_RC
  if [ -n "$JUNIT_DIR" ]; then
    if [ "$JUNIT_TESTS" -gt 0 ]; then
      _jsecs=$(awk -v a="$JUNIT_START" -v b="$(_junit_now)" 'BEGIN { printf "%.3f", b - a }')
      {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<testsuites>"
        echo "  <testsuite name=\"$JUNIT_SUITE\" tests=\"$JUNIT_TESTS\" failures=\"$JUNIT_FAILED\" errors=\"0\" skipped=\"$JUNIT_SKIPPED\" time=\"$_jsecs\">"
        printf '%s' "$JUNIT_CASES"
        echo "  </testsuite>"
        echo "</testsuites>"
      } >"$JUNIT_PART.tmp" && mv -f "$JUNIT_PART.tmp" "$JUNIT_PART"
    fi
    if ! env -u NODE_OPTIONS node test/junit/merge.mjs "$JUNIT_ROOT" "$JUNIT_DIR"; then
      echo "junit: merging $JUNIT_DIR/parts into junit.xml failed" >&2
      [ "$_jrc" -ne 0 ] || _jrc=1
    fi
  fi
  rm -f "$JUNIT_TMP/out" "$JUNIT_TMP/err"
  rmdir "$JUNIT_TMP" 2>/dev/null || true
  return "$_jrc"
}

