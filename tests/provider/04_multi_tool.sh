#!/bin/bash
# Provider Test: Multiple Tool Calls in One Turn
# Verifies the provider handles consecutive tool calls correctly.
#
# Pass: Both tool results present in response
# Critical: Empty response

test_multi_tool() {
  claw_header "PROVIDER 04: Multi-Tool (consecutive calls)"

  local start_s end_s duration
  start_s=$(date +%s)

  local marker_a="PROVMULTI_A_$(date +%s)"
  local marker_b="PROVMULTI_B_$(date +%s)"

  local response
  response=$(claw_ask "Run these two commands and report both results: 1) echo $marker_a  2) echo $marker_b")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response — multi-tool protocol broken" "multi_tool" "$duration"
  elif [[ "$response" == *"$marker_a"* ]] && [[ "$response" == *"$marker_b"* ]]; then
    claw_pass "Multi-tool works: both markers returned" "multi_tool" "$duration"
  elif [[ "$response" == *"$marker_a"* ]] || [[ "$response" == *"$marker_b"* ]]; then
    claw_fail "Only one marker returned (partial tool execution): ${response:0:300}" "multi_tool" "$duration"
  else
    claw_fail "Neither marker found: ${response:0:300}" "multi_tool" "$duration"
  fi
}
