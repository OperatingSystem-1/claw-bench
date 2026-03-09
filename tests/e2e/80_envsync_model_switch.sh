#!/bin/bash
# Test 80: Env-Sync Model Switch
# Validates that pushing a new MODEL_ID via apply-env.sh updates the config.
#
# Pass: Model ID changes in clawdbot.json after apply-env.sh
# Fail: Config unchanged or script errors

test_envsync_model_switch() {
  claw_header "TEST 80: Env-Sync Model Switch"
  local t; t=$(e2e_timer_start)

  # Get current model
  local original_model
  original_model=$(e2e_ssh "jq -r '.agents.defaults.model.primary // empty' ~/.clawdbot/clawdbot.json" || echo "")
  claw_info "Original model: ${original_model:-none}"

  # Check if apply-env.sh exists
  if ! e2e_ssh "test -f /opt/os1/apply-env.sh"; then
    claw_warn "apply-env.sh not found at /opt/os1/ — skipping"
    claw_info "This AMI may not support runtime env-sync"
    # Not a failure — older AMIs may not have this
    claw_pass "Skipped — apply-env.sh not present (pre-env-sync AMI)" "envsync_model_switch" "$(e2e_timer_ms "$t")"
    return
  fi

  # Push a model change (use a known model ID)
  local test_model="amazon.nova-lite-v1:0"
  local manifest
  manifest=$(printf '{"MODEL_ID":"%s"}' "$test_model" | base64)

  e2e_ssh "echo '$manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null

  # Verify model changed
  local new_model
  new_model=$(e2e_ssh "jq -r '.agents.defaults.model.primary // empty' ~/.clawdbot/clawdbot.json" || echo "")

  if [[ "$new_model" == *"$test_model"* ]] || [[ "$new_model" == *"nova-lite"* ]]; then
    claw_pass "Model switched to $new_model" "envsync_model_switch" "$(e2e_timer_ms "$t")"
  else
    claw_fail "Model unchanged: $new_model (expected $test_model)" "envsync_model_switch" "$(e2e_timer_ms "$t")"
  fi

  # Restore original model (best effort)
  if [ -n "$original_model" ]; then
    local restore_model
    restore_model=$(echo "$original_model" | sed 's|.*/||')
    local restore_manifest
    restore_manifest=$(printf '{"MODEL_ID":"%s"}' "$restore_model" | base64)
    e2e_ssh "echo '$restore_manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null || true
  fi
}
