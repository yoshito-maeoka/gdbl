#!/usr/bin/env bash
#
# Tests for gbdl. Runs the CLI against a stub `ollama` binary, so no model
# and no real server are required.

set -uo pipefail

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly GBDL="$TEST_DIR/../gbdl"

TESTS_RUN=0
TESTS_FAILED=0

# --- harness ----------------------------------------------------------------

setup() {
  WORK_DIR="$(mktemp -d)"
  STUB_DIR="$WORK_DIR/bin"
  mkdir -p "$STUB_DIR"

  PROMPT_LOG="$WORK_DIR/prompt.log"
  CALL_LOG="$WORK_DIR/calls.log"
  SERVER_STATE="$WORK_DIR/server.state"
  : >"$PROMPT_LOG"
  : >"$CALL_LOG"

  cat >"$STUB_DIR/ollama" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$CALL_LOG"
case "$1" in
  ps)    [[ -f "$SERVER_STATE" ]] && exit 0 || exit 1 ;;
  serve) touch "$SERVER_STATE"; exit 0 ;;
  list)  printf 'gemma3:12b\tabc123\t8.1 GB\n' ;;
  run)   printf '%s' "$3" >>"$PROMPT_LOG"; printf 'TRANSLATED\n' ;;
esac
STUB
  chmod +x "$STUB_DIR/ollama"

  export CALL_LOG PROMPT_LOG SERVER_STATE
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$WORK_DIR"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL: %s\n' "$*" >&2
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  [[ "$haystack" == *"$needle"* ]] && return 0
  fail "$message (expected to contain '$needle', got '$haystack')"
}

assert_equals() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] && return 0
  fail "$message (expected '$expected', got '$actual')"
}

run_test() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  printf -- '- %s\n' "$name"
  setup
  "$name"
  teardown
}

# --- tests ------------------------------------------------------------------

test_defaults_to_japanese() {
  printf 'hello\n' | "$GBDL" >/dev/null 2>&1
  assert_contains "$(cat "$PROMPT_LOG")" "in Japanese" "default language is Japanese"
}

test_english_option() {
  printf 'hallo\n' | "$GBDL" e >/dev/null 2>&1
  assert_contains "$(cat "$PROMPT_LOG")" "in English" "'e' selects English"
}

test_german_option() {
  printf 'hello\n' | "$GBDL" g >/dev/null 2>&1
  assert_contains "$(cat "$PROMPT_LOG")" "in German" "'g' selects German"
}

test_dash_and_long_options() {
  printf 'hello\n' | "$GBDL" --german >/dev/null 2>&1
  assert_contains "$(cat "$PROMPT_LOG")" "in German" "'--german' selects German"
}

test_prompt_harness_format() {
  printf 'guten Tag\n' | "$GBDL" j >/dev/null 2>&1
  local expected='please translate this text in Japanese, and please print out only the result:
guten Tag'
  assert_equals "$(cat "$PROMPT_LOG")" "$expected" "prompt harness text is exact"
}

test_prints_translation_result() {
  local output
  output="$(printf 'hello\n' | "$GBDL" 2>/dev/null)"
  assert_contains "$output" "TRANSLATED" "model output is printed"
}

test_reprompts_after_each_translation() {
  printf 'one\ntwo\n' | "$GBDL" e >/dev/null 2>&1
  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "2" "each input line triggers one translation"
}

test_blank_lines_are_skipped() {
  printf '\n   \n' | "$GBDL" >/dev/null 2>&1
  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "0" "blank input does not call the model"
}

test_eof_exits_cleanly() {
  printf '' | "$GBDL" >/dev/null 2>&1
  assert_equals "$?" "0" "EOF (Ctrl-D) exits with status 0"
}

test_starts_server_when_not_running() {
  printf '' | "$GBDL" >/dev/null 2>&1
  assert_contains "$(cat "$CALL_LOG")" "serve" "server is started when not running"
}

test_does_not_start_server_when_already_running() {
  touch "$SERVER_STATE"
  printf '' | "$GBDL" >/dev/null 2>&1
  assert_equals "$(grep -c '^serve$' "$CALL_LOG")" "0" "running server is reused"
}

test_unknown_option_fails() {
  printf '' | "$GBDL" x >/dev/null 2>&1
  assert_equals "$?" "2" "unknown option exits with usage error"
}

test_too_many_arguments_fail() {
  printf '' | "$GBDL" e g >/dev/null 2>&1
  assert_equals "$?" "2" "more than one argument exits with usage error"
}

test_help_option() {
  local output
  output="$("$GBDL" --help 2>&1)"
  assert_contains "$output" "Usage: gbdl" "--help prints usage"
}

test_model_is_overridable() {
  printf 'hello\n' | GBDL_MODEL="tiny:1b" "$GBDL" >/dev/null 2>&1
  assert_contains "$(cat "$PROMPT_LOG")" "please translate" "custom model still translates"
}

# --- main -------------------------------------------------------------------

for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$test_name"
done

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
