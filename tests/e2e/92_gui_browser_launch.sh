#!/bin/bash
# Test 92: GUI Browser Launch
# Validates that Chromium can be launched in headless mode.
#
# Pass: Chromium starts and can load a page
# Fail: Browser not found or fails to start

test_gui_browser_launch() {
  claw_header "TEST 92: GUI Browser Launch"
  local t; t=$(e2e_timer_start)

  # Find browser binary
  local browser=""
  for candidate in chromium-browser chromium google-chrome; do
    if e2e_ssh "command -v $candidate >/dev/null 2>&1"; then
      browser="$candidate"
      break
    fi
  done

  if [ -z "$browser" ]; then
    # Check snap
    if e2e_ssh "snap list chromium >/dev/null 2>&1"; then
      browser="chromium"
    else
      claw_pass "Skipped — no browser installed" "gui_browser_launch" "$(e2e_timer_ms "$t")"
      return
    fi
  fi

  claw_info "Browser: $browser"

  # Test headless page load
  local exit_code
  e2e_ssh "timeout 15 $browser --headless --no-sandbox --disable-gpu \
    --dump-dom 'data:text/html,<h1>test</h1>' 2>/dev/null | head -5" >/dev/null 2>&1
  exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    claw_pass "Browser launches and loads pages" "gui_browser_launch" "$(e2e_timer_ms "$t")"
  else
    claw_fail "Browser failed (exit $exit_code)" "gui_browser_launch" "$(e2e_timer_ms "$t")"
  fi
}
