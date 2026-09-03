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

{
  echo "A1 Event List context diagnostic"
  echo "Goal: inspect Logic's Event List filter controls without changing project data or filter state."
  echo "Keep the corrected golden region active and Event List visible."
  echo

  for query in "${queries[@]}"; do
    echo "=== $query ==="
    swift run logic-lab find "$query" --depth 20 --max-nodes 50000
    echo
  done
} | tee "$OUT_FILE"

echo
echo "Context diagnostic saved in: $OUT_FILE"
