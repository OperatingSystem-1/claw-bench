#!/bin/bash
# claw-bench/lib/e2e-common.sh
# Shared helpers for e2e AMI tests
# Provides instance lifecycle management on top of lib/common.sh

#=============================================================================
# Instance Lifecycle
#=============================================================================

# Launch a benchmark instance from an AMI and wait for it to be ready.
# Sets: E2E_INSTANCE_ID, E2E_PUBLIC_IP, E2E_INSTANCE_SECRET
# Usage: e2e_launch_instance [model-id]
e2e_launch_instance() {
  local model_id="${1:-mistral.mistral-large-3-675b-instruct}"

  claw_info "Launching instance from AMI: $E2E_AMI_ID"

  E2E_INSTANCE_ID=$("$CLAW_BENCH_DIR/infra/launch-instance.sh" "$model_id" 2>"$E2E_LOG_DIR/launch.log")
  if [ -z "$E2E_INSTANCE_ID" ] || [ "$E2E_INSTANCE_ID" = "None" ]; then
    claw_critical "Failed to launch instance (see $E2E_LOG_DIR/launch.log)" "instance_launch" "0"
    return 1
  fi

  # Read instance secret from metadata
  E2E_INSTANCE_SECRET=$(jq -r '.instanceSecret' "$CLAW_BENCH_DIR/.instances/$E2E_INSTANCE_ID.json" 2>/dev/null || echo "")

  claw_info "Instance: $E2E_INSTANCE_ID — waiting for ready..."

  E2E_PUBLIC_IP=$("$CLAW_BENCH_DIR/infra/wait-for-ready.sh" "$E2E_INSTANCE_ID" "${E2E_MAX_WAIT:-300}" 2>"$E2E_LOG_DIR/wait.log")
  if [ -z "$E2E_PUBLIC_IP" ]; then
    claw_critical "Instance failed to become ready (see $E2E_LOG_DIR/wait.log)" "instance_ready" "0"
    return 1
  fi

  claw_info "Instance ready: $E2E_PUBLIC_IP"
  export E2E_INSTANCE_ID E2E_PUBLIC_IP E2E_INSTANCE_SECRET
}

# Terminate the current benchmark instance.
# Usage: e2e_terminate_instance
e2e_terminate_instance() {
  if [ -n "${E2E_INSTANCE_ID:-}" ]; then
    claw_info "Terminating instance $E2E_INSTANCE_ID..."
    "$CLAW_BENCH_DIR/infra/terminate-instance.sh" "$E2E_INSTANCE_ID" 2>"$E2E_LOG_DIR/terminate.log" || true
    E2E_INSTANCE_ID=""
  fi
}

# Cleanup trap — always terminate on exit
e2e_cleanup() {
  if [ "${E2E_AUTO_TERMINATE:-true}" = "true" ]; then
    e2e_terminate_instance
  else
    if [ -n "${E2E_INSTANCE_ID:-}" ]; then
      claw_warn "Instance left running: $E2E_INSTANCE_ID ($E2E_PUBLIC_IP)"
    fi
  fi
}

#=============================================================================
# SSH Helpers
#=============================================================================

E2E_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Run a command on the instance via SSH.
# Usage: e2e_ssh "command"
e2e_ssh() {
  local cmd="$1"
  local key="${CLAW_SSH_KEY:-$HOME/.ssh/id_rsa}"
  key="${key/#\~/$HOME}"

  ssh -n -i "$key" $E2E_SSH_OPTS ubuntu@"$E2E_PUBLIC_IP" "$cmd" 2>/dev/null
}

# Run a command and capture exit code (don't fail on error).
# Usage: e2e_ssh_rc "command"
# Returns the remote command's exit code
e2e_ssh_rc() {
  local cmd="$1"
  local key="${CLAW_SSH_KEY:-$HOME/.ssh/id_rsa}"
  key="${key/#\~/$HOME}"

  ssh -n -i "$key" $E2E_SSH_OPTS ubuntu@"$E2E_PUBLIC_IP" "$cmd" 2>/dev/null
  return $?
}

# Copy a file from the instance.
# Usage: e2e_scp_from "/remote/path" "/local/path"
e2e_scp_from() {
  local remote="$1"
  local local_path="$2"
  local key="${CLAW_SSH_KEY:-$HOME/.ssh/id_rsa}"
  key="${key/#\~/$HOME}"

  scp -i "$key" $E2E_SSH_OPTS ubuntu@"$E2E_PUBLIC_IP":"$remote" "$local_path" 2>/dev/null
}

#=============================================================================
# HTTP Helpers (via SSH tunnel)
#=============================================================================

# Make an HTTP request to the gateway from inside the instance.
# Usage: e2e_gateway_curl "/path" [extra-curl-args...]
e2e_gateway_curl() {
  local path="$1"
  shift
  e2e_ssh "curl -sf http://localhost:18789${path} $*"
}

# Make an authenticated HTTP request to the gateway.
# Usage: e2e_gateway_auth_curl "/path" [extra-curl-args...]
e2e_gateway_auth_curl() {
  local path="$1"
  shift
  e2e_ssh "curl -sf -H 'Authorization: Bearer ${E2E_INSTANCE_SECRET}' http://localhost:18789${path} $*"
}

#=============================================================================
# Timing Helpers
#=============================================================================

# Start a timer. Usage: local t; t=$(e2e_timer_start)
e2e_timer_start() {
  date +%s%N
}

# End timer and return duration in ms.
# Usage: local dur; dur=$(e2e_timer_ms "$t")
e2e_timer_ms() {
  local start_ns="$1"
  local end_ns
  end_ns=$(date +%s%N)
  echo $(( (end_ns - start_ns) / 1000000 ))
}

#=============================================================================
# Init
#=============================================================================

e2e_init() {
  # Require AMI ID
  E2E_AMI_ID="${E2E_AMI_ID:?Error: E2E_AMI_ID (or --ami) must be set}"
  export CLAWGO_AMI_ID="$E2E_AMI_ID"

  # Create log dir for this run
  E2E_RUN_ID="e2e-$(date +%Y%m%d-%H%M%S)"
  E2E_LOG_DIR="$CLAW_BENCH_DIR/logs/$E2E_RUN_ID"
  mkdir -p "$E2E_LOG_DIR"
  export E2E_LOG_DIR E2E_RUN_ID

  # Instance state
  E2E_INSTANCE_ID=""
  E2E_PUBLIC_IP=""
  E2E_INSTANCE_SECRET=""

  # Set cleanup trap
  trap e2e_cleanup EXIT
}
