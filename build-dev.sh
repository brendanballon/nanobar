#!/usr/bin/env bash
# Builds NanoBar in DEBUG mode and (re)starts it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "── NanoBar (debug) ──"
(cd "$ROOT" && swift build 2>&1 | grep -E "error:|Build complete|warning:")

echo "── starting ──"
pkill -x NanoBar 2>/dev/null || true
sleep 0.3
"$ROOT/.build/debug/NanoBar" 2>&1 | tee /tmp/nanobar-debug.log &
echo "PID $!  |  log: /tmp/nanobar-debug.log"
