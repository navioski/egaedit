#!/bin/sh
# Capture a fresh set of reference screens from a live tmux session.
# Requires tmux; writes .shots/*.ansi which tools/render-docs.sh turns into PNG.
set -e
cd "$(dirname "$0")/.."

BIN=./build/bin/egaedit
command -v tmux >/dev/null 2>&1 || { echo "tmux is required" >&2; exit 1; }
[ -x "$BIN" ] || { echo "build first: cmake -S . -B build && cmake --build build -j" >&2; exit 1; }

mkdir -p .shots .tmux
export TMUX_TMPDIR="$PWD/.tmux"
tmux kill-server 2>/dev/null || true
tmux new-session -d -s egaedit -x 110 -y 34 "cd '$PWD' && $BIN"
sleep 2

cap() { tmux capture-pane -p -e -t egaedit > ".shots/$1.ansi"; }

cap main

tmux send-keys -t egaedit F10; sleep 0.3
tmux send-keys -t egaedit Down; sleep 0.4
cap menu
tmux send-keys -t egaedit Escape Escape; sleep 0.3

tmux send-keys -t egaedit F1; sleep 0.4
cap keys
tmux send-keys -t egaedit Escape; sleep 0.3

tmux send-keys -t egaedit C-f; sleep 0.4
tmux send-keys -t egaedit "editor"; sleep 0.2
cap find
tmux send-keys -t egaedit Escape; sleep 0.3

tmux send-keys -t egaedit M-o; sleep 0.3
tmux send-keys -t egaedit Down Down Enter; sleep 0.4
cap palette
tmux send-keys -t egaedit Escape; sleep 0.3

tmux send-keys -t egaedit M-h; sleep 0.3
tmux send-keys -t egaedit Down Enter; sleep 0.4
cap about
tmux send-keys -t egaedit Escape; sleep 0.3

tmux kill-server 2>/dev/null || true
echo "captured .shots/*.ansi — now run tools/render-docs.sh"
