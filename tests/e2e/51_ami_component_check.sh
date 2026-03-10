#!/bin/bash
# Test 51: AMI Component Check
# Validates all required binaries and services are present on the AMI.
#
# Pass: All components found
# Fail: Any required component missing

test_ami_component_check() {
  claw_header "TEST 51: AMI Component Check"
  local t; t=$(e2e_timer_start)
  local all_pass=true

  # Required binaries
  local -a bins=(
    "node"
    "clawdbot"
    "jq"
    "curl"
    "git"
    "python3"
    "wacli"
  )

  for bin in "${bins[@]}"; do
    if e2e_ssh "command -v $bin >/dev/null 2>&1"; then
      claw_info "$bin: found"
    else
      claw_fail "$bin: NOT FOUND" "ami_component_$bin" "0"
      all_pass=false
    fi
  done

  # GUI components (may not be on all AMIs)
  local -a gui_bins=(
    "vncserver"
    "xfce4-session"
    "xdotool"
    "scrot"
  )

  for bin in "${gui_bins[@]}"; do
    if e2e_ssh "command -v $bin >/dev/null 2>&1"; then
      claw_info "$bin: found"
    else
      claw_warn "$bin: not found (GUI may not work)"
    fi
  done

  # Check node version
  local node_ver
  node_ver=$(e2e_ssh "node --version" || echo "unknown")
  claw_info "Node.js: $node_ver"

  # Check clawdbot version
  local claw_ver
  claw_ver=$(e2e_ssh "clawdbot --version 2>&1" || echo "unknown")
  claw_info "clawdbot: $claw_ver"

  if [ "$all_pass" = true ]; then
    claw_pass "All required components present" "ami_component_check" "$(e2e_timer_ms "$t")"
  fi
}
