#!/bin/bash
# claw-bench - E2E AMI Benchmark Suite
# Validates a full AMI across boot, auth, config, GUI, and provisioning tiers.
#
# Usage:
#   ./run-e2e.sh --ami ami-xxxxx                      All tiers
#   ./run-e2e.sh --ami ami-xxxxx --tier 0,1            Boot + auth only (~3 min)
#   ./run-e2e.sh --ami ami-xxxxx --tier 0,1,2,3,4,5    Full suite (~15 min)
#   ./run-e2e.sh --ami ami-xxxxx --test 52              Single test
#   ./run-e2e.sh --ami ami-xxxxx --json                 JSON output
#   ./run-e2e.sh --ami ami-xxxxx --no-terminate         Keep instance after run

set -euo pipefail

CLAW_BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAW_BENCH_DIR

# Parse arguments
E2E_AMI_ID=""
E2E_TIERS=""
E2E_TEST_FILTER=""
E2E_AUTO_TERMINATE="true"
CLAW_OUTPUT="human"

usage() {
  cat <<EOF
claw-bench E2E - AMI Validation Suite

Usage:
  ./run-e2e.sh --ami <ami-id> [options]

Required:
  --ami <ami-id>     AMI to test

Options:
  --tier 0,1,4       Comma-separated tiers to run (default: all)
  --test N            Run only test number N
  --json              Output results as JSON
  --tap               Output results as TAP
  --no-terminate      Keep instance running after tests
  --help              Show this help

Tiers:
  0  AMI Boot Validation     (tests 50-54)
  1  Gateway & Auth           (tests 55-58)
  2  Chat Relay Integration   (tests 60-65)  [Phase 3]
  3  Agent-Kit Features       (tests 70-77)  [Phase 3]
  4  Runtime Config           (tests 80-84)
  5  GUI & Desktop            (tests 90-93)
  6  Full Provisioning Flow   (tests 95-99)  [Phase 4]

Examples:
  # Quick smoke test (~3 min)
  ./run-e2e.sh --ami ami-032b488fc8129bd8d --tier 0,1

  # Full validation
  ./run-e2e.sh --ami ami-032b488fc8129bd8d

  # JSON for CI
  ./run-e2e.sh --ami ami-032b488fc8129bd8d --json > results.json

EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --ami)
      E2E_AMI_ID="$2"
      shift 2
      ;;
    --tier)
      E2E_TIERS="$2"
      shift 2
      ;;
    --test)
      E2E_TEST_FILTER="$2"
      shift 2
      ;;
    --json)
      CLAW_OUTPUT="json"
      shift
      ;;
    --tap)
      CLAW_OUTPUT="tap"
      shift
      ;;
    --no-terminate)
      E2E_AUTO_TERMINATE="false"
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage" >&2
      exit 3
      ;;
  esac
done

if [ -z "$E2E_AMI_ID" ]; then
  echo "Error: --ami is required" >&2
  echo "Use --help for usage" >&2
  exit 3
fi

export E2E_AMI_ID E2E_AUTO_TERMINATE CLAW_OUTPUT

# Tier → test number range mapping
tier_includes_test() {
  local test_num="$1"

  # If no tier filter, run all
  if [ -z "$E2E_TIERS" ]; then
    return 0
  fi

  # Determine which tier this test belongs to
  local tier=-1
  if [ "$test_num" -ge 50 ] && [ "$test_num" -le 54 ]; then tier=0
  elif [ "$test_num" -ge 55 ] && [ "$test_num" -le 58 ]; then tier=1
  elif [ "$test_num" -ge 60 ] && [ "$test_num" -le 65 ]; then tier=2
  elif [ "$test_num" -ge 70 ] && [ "$test_num" -le 77 ]; then tier=3
  elif [ "$test_num" -ge 80 ] && [ "$test_num" -le 84 ]; then tier=4
  elif [ "$test_num" -ge 90 ] && [ "$test_num" -le 93 ]; then tier=5
  elif [ "$test_num" -ge 95 ] && [ "$test_num" -le 99 ]; then tier=6
  fi

  # Check if tier is in the requested list
  echo ",$E2E_TIERS," | grep -q ",$tier,"
}

# Load libraries
# shellcheck source=lib/common.sh
source "$CLAW_BENCH_DIR/lib/common.sh"
# shellcheck source=lib/e2e-common.sh
source "$CLAW_BENCH_DIR/lib/e2e-common.sh"

# We set CLAW_MODE to bypass claw_init's mode validation
CLAW_MODE="ssh"
export CLAW_MODE

# Initialize e2e (sets up logging, trap, etc.)
e2e_init

# Header
if [ "$CLAW_OUTPUT" = "human" ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║                   CLAW-BENCH E2E v1.0                           ║"
  echo "║                AMI Validation Suite                              ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  AMI:     $E2E_AMI_ID"
  echo "║  Tiers:   ${E2E_TIERS:-all}"
  echo "║  Run ID:  $E2E_RUN_ID"
  echo "║  Time:    $(date '+%Y-%m-%d %H:%M:%S')"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
fi

# Phase 1: Launch instance
if [ "$CLAW_OUTPUT" = "human" ]; then
  echo "Launching benchmark instance..."
fi

if ! e2e_launch_instance; then
  echo "Failed to launch instance. Aborting." >&2
  case "$CLAW_OUTPUT" in
    json) claw_summary_json ;;
    tap)  claw_summary_tap ;;
    *)    claw_summary_human ;;
  esac
  exit 4
fi

# Configure SSH mode for any tests that use claw_ask
CLAW_HOST="ubuntu@$E2E_PUBLIC_IP"
CLAW_SESSION="e2e-$$-$(date +%s)"
export CLAW_HOST CLAW_SESSION

# Phase 2: Run tests
for test_file in "$CLAW_BENCH_DIR"/tests/e2e/*.sh; do
  [ -f "$test_file" ] || continue

  # Extract test number
  test_num=$(basename "$test_file" .sh | grep -o '^[0-9]*')

  # Apply --test filter
  if [ -n "$E2E_TEST_FILTER" ] && [ "$test_num" != "$E2E_TEST_FILTER" ]; then
    continue
  fi

  # Apply --tier filter
  if ! tier_includes_test "$test_num"; then
    continue
  fi

  # Source and run
  # shellcheck source=/dev/null
  source "$test_file"

  test_name=$(basename "$test_file" .sh | sed 's/^[0-9]*_//')
  test_func="test_${test_name}"

  if declare -f "$test_func" > /dev/null; then
    "$test_func"
  fi
done

# Phase 3: Output summary
case "$CLAW_OUTPUT" in
  json) claw_summary_json ;;
  tap)  claw_summary_tap ;;
  *)    claw_summary_human ;;
esac

# Save results
if [ "$CLAW_OUTPUT" != "json" ]; then
  claw_summary_json > "$E2E_LOG_DIR/results.json"
fi

# Exit (cleanup trap handles termination)
claw_exit
