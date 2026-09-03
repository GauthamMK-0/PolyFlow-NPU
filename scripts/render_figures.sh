#!/usr/bin/env bash
# Render all architecture figures from Graphviz sources.
# Outputs: <name>.png (raster, 140 dpi) + <name>.svg (vector) per .dot file.
set -euo pipefail
cd "$(dirname "$0")/../figures"

command -v dot >/dev/null 2>&1 || { echo "error: graphviz 'dot' not found" >&2; exit 1; }

for f in *.dot; do
  base="${f%.dot}"
  dot -Tpng -Gdpi=140 "$f" -o "$base.png"
  dot -Tsvg            "$f" -o "$base.svg"
  echo "rendered: $base (.png + .svg)"
done
