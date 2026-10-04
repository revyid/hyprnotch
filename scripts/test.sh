#!/usr/bin/env sh
# HyprNotch dev test runner — static QML sanity checks, no Qt toolchain needed.
# Usage: ./scripts/test.sh            (from anywhere)
set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> HyprNotch sanity checks (scripts/check_hyprnotch.py)"
python3 scripts/check_hyprnotch.py "$REPO_ROOT"

echo ""
echo "==> All checks passed. Shell is safe to start (./start.sh)."
