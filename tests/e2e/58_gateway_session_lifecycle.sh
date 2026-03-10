#!/bin/bash
# Test 58: Gateway Session Lifecycle
# Validates that a session can be created, a message sent, and a response received.
# This is the first true end-to-end test — LLM must actually respond.
#
# Pass: Agent responds with correct answer
# Fail: Empty response, timeout, or wrong answer

test_gateway_session_lifecycle() {
  claw_header "TEST 58: Gateway Session Lifecycle"
  local t; t=$(e2e_timer_start)

  # Use claw_ask over SSH (already configured by run-e2e.sh)
  local response
  response=$(claw_ask "What is 7 * 8? Reply with just the number.")

  if claw_is_empty "$response"; then
    claw_critical "Empty response — LLM not responding through gateway" "gateway_session_lifecycle" "$(e2e_timer_ms "$t")"
  elif [[ "$response" == *"56"* ]]; then
    claw_pass "Session lifecycle works — sent message, got correct response (56)" "gateway_session_lifecycle" "$(e2e_timer_ms "$t")"
  else
    claw_fail "Expected 56, got: $response" "gateway_session_lifecycle" "$(e2e_timer_ms "$t")"
  fi
}
