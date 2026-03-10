#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found"
  exit 1
fi

if [[ ! -d "/home/ubuntu/browser-use-venv" ]]; then
  echo "ERROR: /home/ubuntu/browser-use-venv not found"
  echo "Install with: python3 -m venv /home/ubuntu/browser-use-venv && source /home/ubuntu/browser-use-venv/bin/activate && pip install 'browser-use[all]'"
  exit 1
fi

source /home/ubuntu/browser-use-venv/bin/activate
# Fastest validated default model; override by setting BROWSER_USE_MODEL explicitly.
export BROWSER_USE_MODEL="${BROWSER_USE_MODEL:-claude-sonnet-4-6}"
# 1-minute profile: use fast HTTP fetch path for doc-only tasks.
export BROWSER_USE_FAST_PROFILE="${BROWSER_USE_FAST_PROFILE:-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/browser_use_benchmark.py"
