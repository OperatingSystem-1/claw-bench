#!/bin/bash
# Test 52: AMI Config Patching
# Validates that patch-config.sh correctly replaced all placeholders.
#
# Pass: No __PLACEHOLDER__ strings remain in config, instance secret is set
# Fail: Unreplaced placeholders or missing config files

test_ami_config_patching() {
  claw_header "TEST 52: AMI Config Patching"
  local t; t=$(e2e_timer_start)
  local failures=0

  # Check clawdbot.json exists
  if ! e2e_ssh "test -f ~/.clawdbot/clawdbot.json"; then
    claw_critical "~/.clawdbot/clawdbot.json missing" "ami_config_patching" "$(e2e_timer_ms "$t")"
    return
  fi

  # Check for unreplaced placeholders
  local placeholders
  placeholders=$(e2e_ssh "grep -c '__[A-Z_]*__' ~/.clawdbot/clawdbot.json 2>/dev/null" || echo "0")
  if [ "$placeholders" != "0" ]; then
    local found
    found=$(e2e_ssh "grep -o '__[A-Z_]*__' ~/.clawdbot/clawdbot.json | sort -u | head -5" || echo "unknown")
    claw_fail "Found $placeholders unreplaced placeholders: $found" "ami_config_placeholders" "0"
    failures=$((failures + 1))
  else
    claw_info "No unreplaced placeholders in clawdbot.json"
  fi

  # Check instance secret is set (not empty/placeholder)
  local token
  token=$(e2e_ssh "jq -r '.gateway.auth.token // empty' ~/.clawdbot/clawdbot.json 2>/dev/null" || echo "")
  if [ -z "$token" ] || [[ "$token" == *"__"* ]]; then
    claw_fail "Gateway auth token not set correctly" "ami_config_token" "0"
    failures=$((failures + 1))
  else
    claw_info "Gateway auth token: set (${#token} chars)"
  fi

  # Verify token matches what we launched with
  if [ -n "$E2E_INSTANCE_SECRET" ] && [ "$token" = "$E2E_INSTANCE_SECRET" ]; then
    claw_info "Token matches launch secret"
  elif [ -n "$E2E_INSTANCE_SECRET" ]; then
    claw_warn "Token does not match launch secret"
  fi

  # Check .env exists
  if e2e_ssh "test -f ~/.clawdbot/.env"; then
    local env_placeholders
    env_placeholders=$(e2e_ssh "grep -c '__[A-Z_]*__' ~/.clawdbot/.env 2>/dev/null" || echo "0")
    if [ "$env_placeholders" != "0" ]; then
      claw_warn "Found $env_placeholders unreplaced placeholders in .env"
    fi
  fi

  # Check model is configured
  local model
  model=$(e2e_ssh "jq -r '.agents.defaults.model.primary // empty' ~/.clawdbot/clawdbot.json 2>/dev/null" || echo "")
  if [ -n "$model" ]; then
    claw_info "Model configured: $model"
  else
    claw_warn "No model configured in agents.defaults.model.primary"
  fi

  if [ "$failures" -eq 0 ]; then
    claw_pass "Config patching verified — no placeholders, token set" "ami_config_patching" "$(e2e_timer_ms "$t")"
  fi
}
