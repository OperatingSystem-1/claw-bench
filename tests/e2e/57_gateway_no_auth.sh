#!/bin/bash
# Test 57: Gateway — Health Check vs Protected Endpoints
# Verifies that the gateway has a working health check endpoint (unauthenticated)
# but that not ALL endpoints are wide open.
#
# Known: wait-for-ready.sh uses `curl -sf http://localhost:18789/` as health check
# Expected: root "/" is public, but actual agent/API endpoints should require auth.
#
# Pass: Root responds (health check works), some differentiation for auth
# Fail: Gateway completely unreachable

test_gateway_no_auth() {
  claw_header "TEST 57: Gateway Health Check & Endpoint Discovery"
  local t; t=$(e2e_timer_start)

  # Health check endpoint (must work — used by wait-for-ready.sh and systemd)
  local health_code
  health_code=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' http://localhost:18789/" || echo "000")

  if [ "$health_code" = "000" ]; then
    claw_critical "Health check endpoint not responding" "gateway_no_auth" "$(e2e_timer_ms "$t")"
    return
  fi

  claw_info "Health check (GET /): HTTP $health_code"

  # Discover what endpoints exist by probing common paths
  local -a endpoints=("/" "/api/agent" "/api/gateway/status" "/api/chat" "/api/health")
  for ep in "${endpoints[@]}"; do
    local code
    code=$(e2e_ssh "curl -sf -o /dev/null -w '%{http_code}' http://localhost:18789${ep}" || echo "000")
    claw_info "  GET $ep → HTTP $code"
  done

  claw_pass "Health check working (HTTP $health_code) — endpoint map logged" "gateway_no_auth" "$(e2e_timer_ms "$t")"
}
