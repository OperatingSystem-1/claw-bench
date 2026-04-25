#!/bin/bash
# Provider Test: File Write + Read
# Verifies write and read tools work with this provider.
#
# Pass: File created and read back with matching content
# Critical: Empty response

test_file_write_read() {
  claw_header "PROVIDER 02: File Write + Read"

  local start_s end_s duration
  start_s=$(date +%s)

  local test_value="PROVTEST_FILE_$(date +%s)"
  local test_file="/tmp/provtest-$$.txt"

  local response
  response=$(claw_ask "Write the text '$test_value' to the file $test_file using the write tool. Then read it back with the read tool and tell me what it contains.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  # Cleanup
  case "$CLAW_MODE" in
    local) rm -f "$test_file" 2>/dev/null ;;
    ssh) ssh -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" "rm -f '$test_file'" 2>/dev/null ;;
    k8s) kubectl --context "$CLAW_K8S_CONTEXT" -n "$CLAW_K8S_NAMESPACE" exec "${CLAW_K8S_AGENT}-0" -c openclaw -- rm -f "$test_file" 2>/dev/null ;;
  esac

  if claw_is_empty "$response"; then
    claw_critical "Empty response — file tools protocol broken" "file_write_read" "$duration"
  elif [[ "$response" == *"$test_value"* ]]; then
    claw_pass "File write/read works: value matched" "file_write_read" "$duration"
  elif [[ "$response" == *"PROVTEST_FILE"* ]]; then
    claw_pass "File write/read works: content verified" "file_write_read" "$duration"
  else
    claw_fail "Expected value not in response: ${response:0:300}" "file_write_read" "$duration"
  fi
}
