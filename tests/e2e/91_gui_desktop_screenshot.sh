#!/bin/bash
# Test 91: GUI Desktop Screenshot
# Validates that the desktop skill can take a screenshot.
#
# Pass: Screenshot captured and is a valid PNG
# Fail: Screenshot fails or produces empty file

test_gui_desktop_screenshot() {
  claw_header "TEST 91: GUI Desktop Screenshot"
  local t; t=$(e2e_timer_start)

  # Check scrot is available
  if ! e2e_ssh "command -v scrot >/dev/null 2>&1"; then
    claw_pass "Skipped — scrot not installed (headless AMI)" "gui_desktop_screenshot" "$(e2e_timer_ms "$t")"
    return
  fi

  # Check if DISPLAY is set (VNC must be running)
  if ! e2e_ssh "DISPLAY=:1 xdpyinfo >/dev/null 2>&1"; then
    # Try starting VNC first
    if e2e_ssh "test -f /opt/os1/gui-manager.sh"; then
      e2e_ssh "sudo /opt/os1/gui-manager.sh start >/dev/null 2>&1" || true
      sleep 3
    fi

    if ! e2e_ssh "DISPLAY=:1 xdpyinfo >/dev/null 2>&1"; then
      claw_warn "No X display available — VNC may not be running"
      claw_pass "Skipped — no X display" "gui_desktop_screenshot" "$(e2e_timer_ms "$t")"
      return
    fi
  fi

  # Take screenshot
  local screenshot_path="/tmp/e2e-screenshot-$$.png"
  e2e_ssh "DISPLAY=:1 scrot $screenshot_path 2>/dev/null"

  # Verify it's a valid PNG with non-zero size
  local file_size
  file_size=$(e2e_ssh "stat -c '%s' $screenshot_path 2>/dev/null" || echo "0")

  if [ "$file_size" -gt 1000 ]; then
    claw_info "Screenshot: ${file_size} bytes"

    # Verify PNG magic bytes
    local magic
    magic=$(e2e_ssh "xxd -l 4 -p $screenshot_path 2>/dev/null" || echo "")
    if [ "$magic" = "89504e47" ]; then
      claw_pass "Screenshot captured — valid PNG, ${file_size} bytes" "gui_desktop_screenshot" "$(e2e_timer_ms "$t")"
    else
      claw_fail "Screenshot file is not valid PNG (magic: $magic)" "gui_desktop_screenshot" "$(e2e_timer_ms "$t")"
    fi
  else
    claw_fail "Screenshot empty or too small ($file_size bytes)" "gui_desktop_screenshot" "$(e2e_timer_ms "$t")"
  fi

  # Cleanup
  e2e_ssh "rm -f $screenshot_path" 2>/dev/null || true
}
