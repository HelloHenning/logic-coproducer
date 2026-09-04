#!/bin/bash
set -euo pipefail

OUT_DIR="${1:-$HOME/Desktop/logic-a1-test}"
OUT_FILE="$OUT_DIR/context-filters.log"
mkdir -p "$OUT_DIR"

queries=(
  "Notes"
  "Prog. Change"
  "Pitch Bend"
  "Controller"
  "Aftertouch"
  "Poly Aftertouch"
  "Syst. Exclusive"
  "Additional Info"
)

swift build --product logic-lab >/dev/null
LAB=".build/debug/logic-lab"

{
  echo "A1 Event List context diagnostic"
  echo "No project data or Event List filter state is changed."
  echo

  for query in "${queries[@]}"; do
    echo "=== $query ==="
    raw="$($LAB find "$query" --depth 20 --max-nodes 50000)"
    echo "$raw" | awk '
      /^query=/ { print; next }
      /^\[[0-9]+\] / { path=$0; next }
      /^  role=/ {
        if (path != "") print path
        print
        path=""
      }
    '
    echo
  done
} | tee "$OUT_FILE"

echo "Context diagnostic saved in: $OUT_FILE"
