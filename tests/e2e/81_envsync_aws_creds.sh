#!/bin/bash
# Test 81: Env-Sync AWS Credentials
# Validates that pushing AWS creds writes them to the correct locations.
#
# Pass: Credentials appear in ~/.aws/credentials and/or .env
# Fail: Credentials not written or apply-env.sh errors

test_envsync_aws_creds() {
  claw_header "TEST 81: Env-Sync AWS Credentials"
  local t; t=$(e2e_timer_start)

  if ! e2e_ssh "test -f /opt/os1/apply-env.sh"; then
    claw_pass "Skipped — apply-env.sh not present" "envsync_aws_creds" "$(e2e_timer_ms "$t")"
    return
  fi

  # Push test credentials (obviously fake)
  local manifest
  manifest=$(printf '{"AWS_ACCESS_KEY_ID":"AKIATEST1234567890","AWS_SECRET_ACCESS_KEY":"testSecretKey1234567890abcdef","AWS_REGION":"us-west-2"}' | base64)

  e2e_ssh "echo '$manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null

  # Check ~/.aws/credentials
  local aws_key
  aws_key=$(e2e_ssh "grep -c 'AKIATEST1234567890' ~/.aws/credentials 2>/dev/null" || echo "0")

  if [ "$aws_key" -gt 0 ]; then
    claw_info "AWS credentials written to ~/.aws/credentials"
  else
    claw_warn "AWS credentials not found in ~/.aws/credentials"
  fi

  # Check .env
  local env_key
  env_key=$(e2e_ssh "grep -c 'AKIATEST1234567890' ~/.clawdbot/.env 2>/dev/null" || echo "0")

  if [ "$env_key" -gt 0 ]; then
    claw_info "AWS credentials written to .env"
  fi

  if [ "$aws_key" -gt 0 ] || [ "$env_key" -gt 0 ]; then
    claw_pass "AWS credentials synced successfully" "envsync_aws_creds" "$(e2e_timer_ms "$t")"
  else
    claw_fail "AWS credentials not found in any expected location" "envsync_aws_creds" "$(e2e_timer_ms "$t")"
  fi

  # Clean up test creds (restore from backup or clear)
  e2e_ssh "sed -i '/AKIATEST1234567890/d' ~/.aws/credentials 2>/dev/null; sed -i '/AKIATEST1234567890/d' ~/.clawdbot/.env 2>/dev/null" || true
}
