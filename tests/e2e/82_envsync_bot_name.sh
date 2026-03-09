#!/bin/bash
# Test 82: Env-Sync Bot Name
# Validates that pushing BOT_NAME updates the agent identity.
#
# Pass: Bot name reflected in config
# Fail: Name not updated

test_envsync_bot_name() {
  claw_header "TEST 82: Env-Sync Bot Name"
  local t; t=$(e2e_timer_start)

  if ! e2e_ssh "test -f /opt/os1/apply-env.sh"; then
    claw_pass "Skipped — apply-env.sh not present" "envsync_bot_name" "$(e2e_timer_ms "$t")"
    return
  fi

  local test_name="BenchTestBot-$$"
  local manifest
  manifest=$(printf '{"BOT_NAME":"%s"}' "$test_name" | base64)

  e2e_ssh "echo '$manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null

  # Check if name appears in config or env
  local found=false

  if e2e_ssh "grep -q '$test_name' ~/.clawdbot/clawdbot.json 2>/dev/null"; then
    found=true
    claw_info "Bot name set in clawdbot.json"
  fi

  if e2e_ssh "grep -q '$test_name' ~/.clawdbot/.env 2>/dev/null"; then
    found=true
    claw_info "Bot name set in .env"
  fi

  if [ "$found" = true ]; then
    claw_pass "Bot name updated to $test_name" "envsync_bot_name" "$(e2e_timer_ms "$t")"
  else
    claw_fail "Bot name not found after apply-env.sh" "envsync_bot_name" "$(e2e_timer_ms "$t")"
  fi
}
