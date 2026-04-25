#!/bin/bash
# Provider Test: Shell Execution
# Verifies the exec/shell tool works with this provider's tool-calling protocol.
#
# Pass: Agent executed command and returned the marker string
# Critical: Empty response (tool protocol broken)

test_shell_exec() {
  claw_header "PROVIDER 01: Shell Execution (exec)"

  local start_s end_s duration
  start_s=$(date +%s)

  local marker="PROVTEST_EXEC_$(date +%s)"
  local response
  response=$(claw_ask "Run this exact shell command and tell me its output: echo $marker")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response — exec tool protocol likely broken" "shell_exec" "$duration"
  elif [[ "$response" == *"$marker"* ]]; then
    claw_pass "Shell exec works: marker returned" "shell_exec" "$duration"
  else
    claw_fail "Marker not found in response: ${response:0:300}" "shell_exec" "$duration"
  fi
}
