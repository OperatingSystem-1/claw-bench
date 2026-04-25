#!/bin/bash
# Provider Test: Web Fetch
# Verifies the web_fetch tool works with this provider.
#
# Pass: Fetched URL and extracted UUID
# Critical: Empty response

test_web_fetch() {
  claw_header "PROVIDER 03: Web Fetch"

  local start_s end_s duration
  start_s=$(date +%s)

  local response
  response=$(claw_ask "Fetch https://httpbin.org/uuid and tell me the UUID value. Include the UUID in your response.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response — web_fetch tool protocol broken" "web_fetch" "$duration"
  elif [[ "$response" =~ [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} ]]; then
    claw_pass "Web fetch works: UUID extracted" "web_fetch" "$duration"
  else
    claw_fail "No UUID in response: ${response:0:300}" "web_fetch" "$duration"
  fi
}
