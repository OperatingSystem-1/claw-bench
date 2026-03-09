#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/clawdbot"
LOG_FILE="$LOG_DIR/clawdbot-$(date +%Y-%m-%d).log"

if ! command -v clawdbot >/dev/null 2>&1; then
  echo "ERROR: clawdbot not found in PATH"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found"
  exit 1
fi

run_test() {
  local name="$1"
  local timeout="$2"
  local prompt="$3"

  local session_id="bench-${name}-$(date +%s)"
  local start
  local end
  local wall

  echo ""
  echo "=== ${name} ==="
  echo "Session: ${session_id}"

  start=$(date +%s)
  clawdbot agent --session-id "${session_id}" --timeout "${timeout}" -m "${prompt}"
  end=$(date +%s)
  wall=$((end - start))

  python3 - "$LOG_FILE" "$wall" << 'PY'
import json
import re
import sys
from pathlib import Path

log_file = Path(sys.argv[1])
wall = int(sys.argv[2])

if not log_file.exists():
    print(f"Wall time: {wall}s (log file not found)")
    sys.exit(0)

text = log_file.read_text(errors="ignore")
run_ids = re.findall(r"runId=([a-f0-9-]+)", text)
if not run_ids:
    print(f"Wall time: {wall}s (no runId found)")
    sys.exit(0)

latest = run_ids[-1]
lines = [line for line in text.splitlines() if latest in line]

# durationMs
m = re.search(r"durationMs=(\d+)", "\n".join(lines))
if m:
    duration_ms = int(m.group(1))
    print(f"Wall time: {wall}s | Gateway: {duration_ms}ms")
else:
    print(f"Wall time: {wall}s | Gateway: n/a")

# tool counts
counts = {}
for line in lines:
    if "tool start" in line:
        m = re.search(r"tool=([a-zA-Z0-9_]+)", line)
        if m:
            tool = m.group(1)
            counts[tool] = counts.get(tool, 0) + 1

total = sum(counts.values())
if total:
    parts = ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
    print(f"Tool calls: {total} ({parts})")
else:
    print("Tool calls: 0 (or not logged)")
PY
}

run_test \
  "research-synthesis" \
  120 \
  "Use web_search for 'RFC 9110 HTTP semantics'. Open the official RFC page and one other authoritative source. Return 3 bullets summarizing key differences between HTTP/1.1 and HTTP/2, and include source URLs."

run_test \
  "form-fill" \
  120 \
  "Use the browser tool to navigate to https://www.selenium.dev/selenium/web/web-form.html, fill the form with realistic values, submit it, then report the confirmation text shown after submission."

run_test \
  "compare-summary" \
  120 \
  "Use web_search for 'PostgreSQL btree vs hash index'. Open 2 sources and produce a concise comparison table (3 rows max). End with a one-sentence recommendation for a general web app. Include source URLs."
