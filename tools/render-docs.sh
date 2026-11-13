#!/bin/sh
# Render .shots/*.ansi into docs/screenshot-*.png.
# Requires Pillow:  python3 -m pip install pillow
set -e
cd "$(dirname "$0")/.."

PY=${PYTHON:-python3}
$PY -c "import PIL" 2>/dev/null || { echo "Pillow is required (pip install pillow)" >&2; exit 1; }

for pair in \
    main:screenshot-main \
    menu:screenshot-menu \
    find:screenshot-find \
    about:screenshot-about \
    keys:screenshot-keys \
    palette:screenshot-palette
do
    src=${pair%%:*}
    dst=${pair##*:}
    [ -f ".shots/$src.ansi" ] || { echo "missing .shots/$src.ansi" >&2; exit 1; }
    $PY tools/ansi2png.py ".shots/$src.ansi" 110 34 "docs/$dst.png" tools/fonts/PxPlus_IBM_VGA8.ttf 16
done
