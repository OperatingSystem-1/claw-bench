#!/bin/bash
# Test 53: AMI Service Health
# Validates systemd service is active and gateway is healthy.
#
# Pass: clawdbot.service active, gateway responding, no crash loops, wacli-sync installed
# Fail: Service not running, unhealthy, or wacli-sync missing

test_ami_service_health() {
  claw_header "TEST 53: AMI Service Health"
  local t; t=$(e2e_timer_start)
  local failures=0

  # Check systemd service is active
  local svc_state
  svc_state=$(e2e_ssh "systemctl is-active clawdbot 2>/dev/null" || echo "unknown")
  if [ "$svc_state" = "active" ]; then
    claw_info "clawdbot.service: active"
  else
    claw_critical "clawdbot.service is '$svc_state'" "ami_service_active" "$(e2e_timer_ms "$t")"
    # Grab journal for debugging
    e2e_ssh "journalctl -u clawdbot --no-pager -n 30 2>/dev/null" > "$E2E_LOG_DIR/clawdbot-journal.log" 2>/dev/null || true
    return
  fi

  # Check for restart loops (NRestarts > 0 is a warning, > 3 is a fail)
  local restarts
  restarts=$(e2e_ssh "systemctl show clawdbot --property=NRestarts --value 2>/dev/null" || echo "0")
  if [ "$restarts" -gt 3 ]; then
    claw_fail "Service has restarted $restarts times (crash loop)" "ami_service_restarts" "0"
    failures=$((failures + 1))
  elif [ "$restarts" -gt 0 ]; then
    claw_warn "Service has restarted $restarts time(s)"
  fi

  # Check gateway HTTP health
  local gw_response
  gw_response=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' http://localhost:18789/" || echo "000")
  if [ "$gw_response" = "200" ] || [ "$gw_response" = "401" ]; then
    claw_info "Gateway HTTP: $gw_response"
  else
    claw_fail "Gateway HTTP returned $gw_response" "ami_service_gateway_http" "0"
    failures=$((failures + 1))
  fi

  # Check gateway is listening on expected port
  if e2e_ssh "ss -tlnp | grep -q ':18789'"; then
    claw_info "Port 18789: listening"
  else
    claw_fail "Nothing listening on port 18789" "ami_service_port" "0"
    failures=$((failures + 1))
  fi

  # Check wacli-sync.service is installed (user-level)
  # It won't be "active" until WhatsApp is authenticated, but the unit file must exist
  local wacli_svc
  wacli_svc=$(e2e_ssh "systemctl --user is-enabled wacli-sync.service 2>/dev/null" || echo "not-found")
  if [ "$wacli_svc" = "enabled" ]; then
    claw_info "wacli-sync.service: enabled (starts after wacli auth)"
  elif [ "$wacli_svc" = "disabled" ] || [ "$wacli_svc" = "static" ]; then
    claw_warn "wacli-sync.service: installed but not enabled"
  else
    claw_fail "wacli-sync.service: not installed" "ami_service_wacli_sync" "0"
    failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    claw_pass "Service healthy — active, no crash loops, gateway responding" "ami_service_health" "$(e2e_timer_ms "$t")"
  fi
}
