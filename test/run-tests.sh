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
  # Like the real `ollama run`, this drains stdin: the CLI must not let it
  # eat the input lines that are still queued.
  run)   printf '%s' "$3" >>"$PROMPT_LOG"; cat >/dev/null; printf 'TRANSLATED\n' ;;
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

test_wrapped_paragraph_is_one_translation() {
  printf 'one\ntwo\n' | "$GBDL" e >/dev/null 2>&1
  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "1" \
    "consecutive lines are translated as a single paragraph"
}

test_paragraph_is_sent_whole_with_line_breaks() {
  printf 'the quick brown\nfox jumps over\n' | "$GBDL" e >/dev/null 2>&1
  local expected='please translate this text in English, and please print out only the result:
the quick brown
fox jumps over'
  assert_equals "$(cat "$PROMPT_LOG")" "$expected" \
    "the whole paragraph reaches the model, line breaks intact"
}

test_blank_lines_are_not_translated() {
  printf '\n   \n' | "$GBDL" >/dev/null 2>&1
  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "0" "blank input does not call the model"
}

test_blank_lines_are_printed_as_blank_lines() {
  # The prompt label is stripped so only the translated text remains.
  local output
  output="$(printf 'one\n\ntwo\n' | "$GBDL" e 2>/dev/null | sed 's/^\[English\] > //')"
  local expected='TRANSLATED

TRANSLATED'
  assert_equals "$output" "$expected" "a blank line is echoed as a blank line"
}

test_consecutive_blank_lines_are_all_kept() {
  local output
  output="$(printf 'one\n\n\ntwo\n' | "$GBDL" e 2>/dev/null | sed 's/^\[English\] > //')"
  local expected='TRANSLATED


TRANSLATED'
  assert_equals "$output" "$expected" "each blank line is preserved"
}

test_translates_every_paragraph_across_blank_lines() {
  printf 'one\n\ntwo\n\n\nthree\n' | "$GBDL" e >/dev/null 2>&1
  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "3" \
    "paragraphs after a blank line are still translated"
}

test_final_line_without_newline_is_translated() {
  printf 'one\n\ntwo' | "$GBDL" e >/dev/null 2>&1
  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "2" \
    "a last line with no trailing newline is not dropped"
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

# Terminal-only regression: readline used to hand over just the first line of
# a multi-line paste and silently drop the rest.
test_multi_line_paste_on_a_terminal() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP: python3 not available\n'
    return 0
  fi

  local text_file="$WORK_DIR/paste.txt"
  cat >"$text_file" <<'TEXT'
the quick brown fox
jumps over the lazy dog

and then it stops
TEXT

  python3 "$TEST_DIR/paste-in-pty.py" "$GBDL" "$text_file" >/dev/null 2>&1

  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "2" \
    "a pasted block is translated as one call per paragraph"
  assert_contains "$(cat "$PROMPT_LOG")" "jumps over the lazy dog" \
    "the second line of a paste is not dropped"
  assert_contains "$(cat "$PROMPT_LOG")" "and then it stops" \
    "text after a blank line is not dropped"
}

# Selecting a paragraph rarely picks up its trailing newline, and a terminal
# in canonical mode holds an unterminated line back. The last line used to be
# left behind in the terminal's buffer, untranslated.
test_paste_without_a_trailing_newline() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP: python3 not available\n'
    return 0
  fi

  local text_file="$WORK_DIR/paste-no-newline.txt"
  printf 'the quick brown fox\njumps over the lazy dog\n\nand then it stops' >"$text_file"

  python3 "$TEST_DIR/paste-in-pty.py" "$GBDL" "$text_file" >/dev/null 2>&1

  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "2" \
    "both paragraphs are translated without a closing newline"
  assert_contains "$(cat "$PROMPT_LOG")" "and then it stops" \
    "the last line is translated even with no newline after it"
}

# The drain must not reach into what the user types next.
test_typed_lines_stay_separate() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP: python3 not available\n'
    return 0
  fi

  python3 "$TEST_DIR/paste-in-pty.py" --typed "$GBDL" >/dev/null 2>&1

  assert_equals "$(grep -c '^run$' "$CALL_LOG")" "2" \
    "two typed lines are two separate translations"
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
