#!/bin/bash
# Provider Test: Structured JSON Output
# Verifies the agent can produce valid JSON when asked.
# This tests instruction following + tool use (exec to validate JSON).
#
# Pass: Valid JSON produced
# Fail: Invalid or missing JSON

test_json_output() {
  claw_header "PROVIDER 08: Structured JSON Output"

  local start_s end_s duration
  start_s=$(date +%s)

  local response
  response=$(claw_ask 'Run this command and tell me the result: echo '\''{"status":"ok","provider_test":true,"timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'\'' | python3 -m json.tool')

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response on JSON output test" "json_output" "$duration"
  elif [[ "$response" == *"provider_test"* ]] && [[ "$response" == *"true"* ]]; then
    claw_pass "JSON output works: structured data returned" "json_output" "$duration"
  elif [[ "$response" == *"status"* ]] && [[ "$response" == *"ok"* ]]; then
    claw_pass "JSON output works: status ok" "json_output" "$duration"
  else
    claw_fail "JSON not found in response: ${response:0:300}" "json_output" "$duration"
  fi
}
