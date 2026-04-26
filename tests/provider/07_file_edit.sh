#!/bin/bash
# Provider Test: File Edit (write + edit + read)
# Verifies the agent can create a file, edit it, and verify the edit.
#
# Pass: File edited and verified
# Fail: Edit not applied

test_file_edit() {
  claw_header "PROVIDER 07: File Edit (write → edit → read)"

  local start_s end_s duration
  start_s=$(date +%s)

  local test_file="/tmp/provtest-edit-$$.txt"
  local original="line1: hello\nline2: world\nline3: test"
  local expected="EDITED"

  local response
  response=$(claw_ask "Do these steps in order:
1. Write this content to $test_file: line1: hello\nline2: world\nline3: test
2. Edit the file to replace 'world' with 'EDITED' on line 2
3. Read the file back and tell me what line 2 says now")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  # Cleanup
  case "$CLAW_MODE" in
    local) rm -f "$test_file" 2>/dev/null ;;
    ssh) ssh -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" "rm -f '$test_file'" 2>/dev/null ;;
    k8s) kubectl --context "$CLAW_K8S_CONTEXT" -n "$CLAW_K8S_NAMESPACE" exec "${CLAW_K8S_AGENT}-0" -c openclaw -- rm -f "$test_file" 2>/dev/null ;;
  esac

  if claw_is_empty "$response"; then
    claw_critical "Empty response — file edit protocol broken" "file_edit" "$duration"
  elif [[ "$response" == *"$expected"* ]]; then
    claw_pass "File edit works: 'EDITED' found in response" "file_edit" "$duration"
  else
    claw_fail "Edit not verified: ${response:0:300}" "file_edit" "$duration"
  fi
}
