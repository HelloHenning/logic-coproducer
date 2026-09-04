#!/bin/bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="${COPRODUCER_TEST_ROOT:-$HOME/Desktop/logic-coproducer-tests}"
OUT_DIR="${1:-$TEST_ROOT/coproducer-core-midi-session}"

mkdir -p "$TEST_ROOT"

EXPECTED="${A1_EXPECTED:-}"
if [[ -z "$EXPECTED" ]]; then
  if [[ -f "$TEST_ROOT/logic-a1-golden-v2.expected.json" ]]; then
    EXPECTED="$TEST_ROOT/logic-a1-golden-v2.expected.json"
  else
    EXPECTED="$(find "$TEST_ROOT" -type f -name 'logic-a1-golden-v2.expected.json' -print -quit 2>/dev/null || true)"
  fi
fi

if [[ -z "$EXPECTED" || ! -f "$EXPECTED" ]]; then
  echo "Could not find logic-a1-golden-v2.expected.json anywhere under:" >&2
  echo "  $TEST_ROOT" >&2
  echo "Move that manifest somewhere inside the test folder and retry." >&2
  exit 2
fi

printf 'Using test root: %s\n' "$TEST_ROOT"
printf 'Using golden manifest: %s\n' "$EXPECTED"
printf 'Evidence output: %s\n\n' "$OUT_DIR"

A1_EXPECTED="$EXPECTED" bash "$SCRIPT_DIR/core-midi-validation-session.sh" "$OUT_DIR"
