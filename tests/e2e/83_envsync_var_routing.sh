#!/bin/bash
# Test 83: Env-Sync Variable Routing
# Validates that apply-env.sh routes vars to the correct destinations:
#   - Known vars (MODEL_ID) → clawdbot.json + .env
#   - Unknown vars → .env ONLY (not clawdbot.json, not ~/.aws/credentials)
#
# NOTE: The allowlist that blocks arbitrary vars lives in the WEBSITE
# (env-sync.ts ALLOWED_ENV_VARS), not in apply-env.sh. This test verifies
# the routing layer, not the filtering layer.
#
# Pass: Unknown vars isolated to .env, not leaked to config or credentials
# Fail: Unknown vars end up in clawdbot.json or ~/.aws/credentials

test_envsync_var_routing() {
  claw_header "TEST 83: Env-Sync Variable Routing"
  local t; t=$(e2e_timer_start)

  if ! e2e_ssh "test -f /opt/os1/apply-env.sh"; then
    claw_pass "Skipped — apply-env.sh not present" "envsync_var_routing" "$(e2e_timer_ms "$t")"
    return
  fi

  # Push a mix of known + unknown vars
  local manifest
  manifest=$(printf '{"UNKNOWN_TEST_VAR":"should-only-be-in-env","MODEL_ID":"amazon.nova-lite-v1:0"}' | base64)

  e2e_ssh "echo '$manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null

  local failures=0

  # MODEL_ID (known) should be in clawdbot.json
  local model_in_config
  model_in_config=$(e2e_ssh "jq -r '.agents.defaults.model.primary // empty' ~/.clawdbot/clawdbot.json" || echo "")
  if [[ "$model_in_config" == *"nova-lite"* ]]; then
    claw_info "MODEL_ID correctly routed to clawdbot.json"
  else
    claw_fail "MODEL_ID not found in clawdbot.json (got: $model_in_config)" "envsync_routing_known" "0"
    failures=$((failures + 1))
  fi

  # UNKNOWN_TEST_VAR should be in .env
  if e2e_ssh "grep -q 'UNKNOWN_TEST_VAR=should-only-be-in-env' ~/.clawdbot/.env 2>/dev/null"; then
    claw_info "UNKNOWN_TEST_VAR correctly routed to .env (env-only)"
  else
    claw_fail "UNKNOWN_TEST_VAR not found in .env" "envsync_routing_unknown_env" "0"
    failures=$((failures + 1))
  fi

  # UNKNOWN_TEST_VAR must NOT be in clawdbot.json
  if e2e_ssh "grep -q 'UNKNOWN_TEST_VAR' ~/.clawdbot/clawdbot.json 2>/dev/null"; then
    claw_critical "UNKNOWN_TEST_VAR leaked into clawdbot.json — routing broken" "envsync_routing_leak_config" "0"
    failures=$((failures + 1))
  else
    claw_info "UNKNOWN_TEST_VAR correctly absent from clawdbot.json"
  fi

  # UNKNOWN_TEST_VAR must NOT be in ~/.aws/credentials
  if e2e_ssh "grep -q 'UNKNOWN_TEST_VAR' ~/.aws/credentials 2>/dev/null"; then
    claw_critical "UNKNOWN_TEST_VAR leaked into AWS credentials — routing broken" "envsync_routing_leak_aws" "0"
    failures=$((failures + 1))
  else
    claw_info "UNKNOWN_TEST_VAR correctly absent from AWS credentials"
  fi

  # Cleanup test var from .env
  e2e_ssh "sed -i '/UNKNOWN_TEST_VAR/d' ~/.clawdbot/.env" 2>/dev/null || true

  if [ "$failures" -eq 0 ]; then
    claw_pass "Variable routing correct — known→config, unknown→env-only" "envsync_var_routing" "$(e2e_timer_ms "$t")"
  fi
}
