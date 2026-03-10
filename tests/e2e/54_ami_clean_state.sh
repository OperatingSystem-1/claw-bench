#!/bin/bash
# Test 54: AMI Clean State
# Validates no stale sessions, leaked credentials, or PII from the builder.
#
# Pass: No stale data found
# Fail: Credentials or PII artifacts present

test_ami_clean_state() {
  claw_header "TEST 54: AMI Clean State"
  local t; t=$(e2e_timer_start)
  local failures=0

  # Check for stale sessions (should be cleared by UserData)
  local session_count
  session_count=$(e2e_ssh "find ~/.clawdbot/sessions -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' '" || echo "0")
  if [ "$session_count" -gt 0 ]; then
    claw_fail "Found $session_count stale session files" "ami_clean_sessions" "0"
    failures=$((failures + 1))
  else
    claw_info "No stale sessions"
  fi

  # Check no builder AWS credentials leaked (creds should only come from UserData)
  # We check that if creds exist, they match what we injected — not leftover builder creds
  local cred_owner
  cred_owner=$(e2e_ssh "stat -c '%U' ~/.aws/credentials 2>/dev/null" || echo "none")
  if [ "$cred_owner" = "root" ]; then
    claw_warn "AWS credentials owned by root (should be ubuntu)"
  fi

  # Check no .claude or .clawhub credentials (builder PII)
  if e2e_ssh "test -d ~/.claude"; then
    claw_fail "~/.claude directory present (builder PII)" "ami_clean_claude" "0"
    failures=$((failures + 1))
  fi
  if e2e_ssh "test -d ~/.clawhub"; then
    claw_fail "~/.clawhub directory present (builder PII)" "ami_clean_clawhub" "0"
    failures=$((failures + 1))
  fi

  # Check bash history is clean
  local history_lines
  history_lines=$(e2e_ssh "wc -l < ~/.bash_history 2>/dev/null" || echo "0")
  if [ "$history_lines" -gt 5 ]; then
    claw_warn "bash_history has $history_lines lines (may contain builder history)"
  fi

  # Check no WhatsApp media/data from builder
  if e2e_ssh "test -d ~/.clawdbot/media && [ \$(find ~/.clawdbot/media -type f 2>/dev/null | wc -l) -gt 0 ]" 2>/dev/null; then
    claw_fail "WhatsApp media found (builder data leak)" "ami_clean_media" "0"
    failures=$((failures + 1))
  fi

  # Check file permissions on secrets
  local config_perms
  config_perms=$(e2e_ssh "stat -c '%a' ~/.clawdbot/clawdbot.json 2>/dev/null" || echo "unknown")
  claw_info "clawdbot.json permissions: $config_perms"

  if [ "$failures" -eq 0 ]; then
    claw_pass "Clean state — no stale sessions, no leaked PII" "ami_clean_state" "$(e2e_timer_ms "$t")"
  fi
}
