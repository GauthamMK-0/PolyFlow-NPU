#!/usr/bin/env bash
# Render all architecture figures from TikZ (.tex) and Graphviz (.dot) sources.
# Outputs: <name>.pdf (vector PDF), <name>.svg (vector SVG), and <name>.png (300 dpi raster).
set -euo pipefail
cd "$(dirname "$0")/../figures"

echo "=================================================================="
echo " [PolyFlow-NPU] Rendering Architectural Figures"
echo "=================================================================="

# 1. Render TikZ (.tex) Figures
if compgen -G "*.tex" > /dev/null; then
  if command -v pdflatex >/dev/null 2>&1 && command -v pdftocairo >/dev/null 2>&1; then
    for tex in *.tex; do
      base="${tex%.tex}"
      echo -n "Compiling TikZ figure: $tex ... "
      pdflatex -interaction=nonstopmode "$tex" > /dev/null
      pdftocairo -svg "$base.pdf" "$base.svg"
      pdftocairo -png -singlefile -r 300 "$base.pdf" "$base"
      rm -f "$base.aux" "$base.log"
      echo "DONE -> $base.pdf, $base.svg, $base.png"
    done
  else
    echo "Notice: pdflatex or pdftocairo not found, skipping TikZ .tex compilation."
  fi
fi

# 2. Render Graphviz (.dot) Figures
if compgen -G "*.dot" > /dev/null; then
  if command -v dot >/dev/null 2>&1; then
    for dotf in *.dot; do
      base="${dotf%.dot}"
      echo -n "Rendering Graphviz: $dotf ... "
      dot -Tpng -Gdpi=160 "$dotf" -o "$base.png"
      dot -Tsvg "$dotf" -o "$base.svg"
      echo "DONE -> $base.png, $base.svg"
    done
  else
    echo "Notice: Graphviz 'dot' not found, skipping .dot rendering."
  fi
fi

echo "=================================================================="
echo " [SUCCESS] All figures rendered successfully!"
echo "=================================================================="

