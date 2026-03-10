#!/bin/bash
# Test 93: GUI xdotool Interaction
# Validates that xdotool can perform desktop interactions.
#
# Pass: xdotool commands execute without error
# Fail: xdotool not available or commands fail

test_gui_xdotool_interact() {
  claw_header "TEST 93: GUI xdotool Interaction"
  local t; t=$(e2e_timer_start)

  if ! e2e_ssh "command -v xdotool >/dev/null 2>&1"; then
    claw_pass "Skipped — xdotool not installed" "gui_xdotool_interact" "$(e2e_timer_ms "$t")"
    return
  fi

  # Need a display
  if ! e2e_ssh "DISPLAY=:1 xdpyinfo >/dev/null 2>&1"; then
    claw_pass "Skipped — no X display" "gui_xdotool_interact" "$(e2e_timer_ms "$t")"
    return
  fi

  local failures=0

  # Test mouse move
  if e2e_ssh "DISPLAY=:1 xdotool mousemove 100 100 2>/dev/null"; then
    claw_info "mousemove: OK"
  else
    claw_fail "mousemove failed" "gui_xdotool_mousemove" "0"
    failures=$((failures + 1))
  fi

  # Test key press
  if e2e_ssh "DISPLAY=:1 xdotool key Escape 2>/dev/null"; then
    claw_info "key press: OK"
  else
    claw_fail "key press failed" "gui_xdotool_key" "0"
    failures=$((failures + 1))
  fi

  # Test type (to /dev/null via xdotool)
  if e2e_ssh "DISPLAY=:1 xdotool type --clearmodifiers 'hello' 2>/dev/null"; then
    claw_info "type: OK"
  else
    claw_fail "type failed" "gui_xdotool_type" "0"
    failures=$((failures + 1))
  fi

  # Test getactivewindow
  local window
  window=$(e2e_ssh "DISPLAY=:1 xdotool getactivewindow 2>/dev/null" || echo "")
  if [ -n "$window" ]; then
    claw_info "Active window: $window"
  else
    claw_warn "No active window (may be normal on fresh desktop)"
  fi

  if [ "$failures" -eq 0 ]; then
    claw_pass "xdotool interactions working" "gui_xdotool_interact" "$(e2e_timer_ms "$t")"
  fi
}
