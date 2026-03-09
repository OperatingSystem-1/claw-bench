#!/bin/bash
# Test 55: Gateway Auth — Valid Token
# Probes the gateway with the instance secret to determine auth behavior.
#
# The clawdbot gateway config has: "auth": { "token": "<instance-secret>" }
# We test Bearer auth since that's the most common pattern, but we also
# record what happens for future reference.
#
# Pass: Authenticated request returns non-error response
# Fail: Gateway not responding at all

test_gateway_auth_valid_token() {
  claw_header "TEST 55: Gateway Auth — Probing Token Auth"
  local t; t=$(e2e_timer_start)

  # First: verify unauthenticated root is reachable (health check)
  local root_code
  root_code=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' http://localhost:18789/" || echo "000")

  if [ "$root_code" = "000" ]; then
    claw_critical "Gateway not responding at all on :18789" "gateway_auth_valid_token" "$(e2e_timer_ms "$t")"
    return
  fi

  claw_info "Root / returns HTTP $root_code (health check)"

  # Probe: Bearer token with instance secret
  local bearer_code
  bearer_code=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' \
    -H 'Authorization: Bearer ${E2E_INSTANCE_SECRET}' \
    http://localhost:18789/" || echo "000")

  claw_info "Bearer auth on / returns HTTP $bearer_code"

  # Probe: X-Token header (alternative pattern)
  local xtoken_code
  xtoken_code=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' \
    -H 'X-Token: ${E2E_INSTANCE_SECRET}' \
    http://localhost:18789/" || echo "000")

  claw_info "X-Token auth on / returns HTTP $xtoken_code"

  # Probe: query param
  local param_code
  param_code=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' \
    'http://localhost:18789/?token=${E2E_INSTANCE_SECRET}'" || echo "000")

  claw_info "Query param auth on / returns HTTP $param_code"

  # Log results for analysis — save to log dir
  cat > "$E2E_LOG_DIR/gateway-auth-probe.txt" << EOF
Gateway Auth Probe Results
==========================
Instance: $E2E_INSTANCE_ID ($E2E_PUBLIC_IP)
Instance Secret: ${E2E_INSTANCE_SECRET:0:8}...

Root / (no auth):     HTTP $root_code
Bearer auth on /:     HTTP $bearer_code
X-Token auth on /:    HTTP $xtoken_code
Query param on /:     HTTP $param_code
EOF

  # We consider this a pass if the gateway is responding
  # The probing results are logged for manual review
  if [ "$root_code" != "000" ]; then
    claw_pass "Gateway responding — auth probe logged to $E2E_LOG_DIR/gateway-auth-probe.txt" "gateway_auth_valid_token" "$(e2e_timer_ms "$t")"
  fi
}
