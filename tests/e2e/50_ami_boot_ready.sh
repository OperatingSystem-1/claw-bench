#!/bin/bash
# Test 50: AMI Boot Ready
# Validates that the instance booted, UserData ran, and clawdbot gateway is listening.
# This is implicitly tested by e2e_launch_instance, but we verify the markers.
#
# Pass: /opt/claw-bench/status contains "ready", gateway responds on :18789
# Fail: Missing markers or gateway unreachable

test_ami_boot_ready() {
  claw_header "TEST 50: AMI Boot Ready"
  local t; t=$(e2e_timer_start)

  # Check boot marker
  local status
  status=$(e2e_ssh "cat /opt/claw-bench/status 2>/dev/null" || echo "missing")

  if [ "$status" != "ready" ]; then
    claw_critical "Boot status is '$status', expected 'ready'" "ami_boot_ready" "$(e2e_timer_ms "$t")"
    return
  fi

  # Double-check gateway responds
  if ! e2e_ssh "curl -sf http://localhost:18789/ >/dev/null"; then
    claw_critical "Gateway not responding on :18789" "ami_boot_ready" "$(e2e_timer_ms "$t")"
    return
  fi

  # Check boot time was reasonable
  local launch_time
  launch_time=$(e2e_ssh "cat /opt/claw-bench/launch-time 2>/dev/null" || echo "")
  if [ -n "$launch_time" ]; then
    claw_info "Boot marker time: $launch_time"
  fi

  claw_pass "Instance booted and gateway ready" "ami_boot_ready" "$(e2e_timer_ms "$t")"
}
