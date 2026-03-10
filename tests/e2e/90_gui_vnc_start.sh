#!/bin/bash
# Test 90: GUI VNC Start
# Validates that gui-manager.sh can start VNC and the desktop is accessible.
#
# Pass: VNC starts and port 6901 responds
# Fail: VNC fails to start or port not listening

test_gui_vnc_start() {
  claw_header "TEST 90: GUI VNC Start"
  local t; t=$(e2e_timer_start)

  # Check if gui-manager.sh exists
  if ! e2e_ssh "test -f /opt/os1/gui-manager.sh"; then
    claw_pass "Skipped — gui-manager.sh not present (headless AMI)" "gui_vnc_start" "$(e2e_timer_ms "$t")"
    return
  fi

  # Start VNC
  local output
  output=$(e2e_ssh "sudo /opt/os1/gui-manager.sh start 2>&1" || echo "error")

  # Wait a moment for VNC to initialize
  sleep 3

  # Check port 6901 is listening
  if e2e_ssh "ss -tlnp | grep -q ':6901'"; then
    claw_info "VNC listening on :6901"
  else
    # Also check :5901 (some configs)
    if e2e_ssh "ss -tlnp | grep -q ':5901'"; then
      claw_info "VNC listening on :5901"
    else
      claw_fail "VNC not listening on expected ports" "gui_vnc_start" "$(e2e_timer_ms "$t")"
      return
    fi
  fi

  # Check VNC process is running
  if e2e_ssh "pgrep -f 'vnc' >/dev/null 2>&1"; then
    claw_pass "VNC started successfully" "gui_vnc_start" "$(e2e_timer_ms "$t")"
  else
    claw_fail "VNC process not found" "gui_vnc_start" "$(e2e_timer_ms "$t")"
  fi
}
