#!/bin/bash
# Test 75: Workspace Deploy + Env Injection + Restart
# Validates the full "update an agent in-place" flow:
#   1. Build workspace tarball from agent-kit templates
#   2. SCP tarball to instance + deploy apply-env.sh
#   3. Extract into ~/clawd/ (swap workspace)
#   4. Inject env vars via apply-env.sh — ALL routing types:
#      - identity (BOT_NAME → .env + IDENTITY.md + agent-kit .env)
#      - config-json (MODEL_ID → .env + clawdbot.json)
#      - agent-kit (AGENT_NEON_URL, AGENT_KNOWN_AGENTS → agent-kit .env)
#   5. Restart clawdbot service
#   6. Verify every destination file is correctly populated
#
# Pass: All files deployed, all env vars routed to correct destinations, gateway healthy
# Fail: Missing files, vars not routed, or gateway doesn't come back

test_workspace_deploy_and_restart() {
  claw_header "TEST 75: Workspace Deploy + Env Injection + Restart"
  local t; t=$(e2e_timer_start)
  local failures=0

  # Paths to agent-kit source (relative to monorepo root)
  local monorepo_root
  monorepo_root="$(cd "$CLAW_BENCH_DIR/.." && pwd)"
  local agent_kit="$monorepo_root/agent-kit"
  local image_mgr="$monorepo_root/image-manager"
  local workspace_tmpl="$agent_kit/templates/workspace"
  local memory_tmpl="$agent_kit/templates/memory"
  local task_queue="$agent_kit/core/task-queue"
  local apply_env_src="$image_mgr/defaults/apply-env.sh"
  local agent_kit_setup_src="$image_mgr/defaults/agent-kit-setup.sh"

  # Verify local sources exist
  if [ ! -d "$workspace_tmpl" ]; then
    claw_critical "agent-kit/templates/workspace not found at $workspace_tmpl" "workspace_deploy" "$(e2e_timer_ms "$t")"
    return
  fi
  if [ ! -f "$apply_env_src" ]; then
    claw_critical "apply-env.sh not found at $apply_env_src" "workspace_deploy" "$(e2e_timer_ms "$t")"
    return
  fi

  #---------------------------------------------------------------------------
  # Step 1: Snapshot baseline
  #---------------------------------------------------------------------------
  claw_info "Step 1: Capturing baseline state"

  local original_model=""
  original_model=$(e2e_ssh "jq -r '.agents.defaults.model.primary // empty' ~/.clawdbot/clawdbot.json") || true
  claw_info "Original model: ${original_model:-none}"

  local original_bot_name=""
  original_bot_name=$(e2e_ssh "sed -n 's/^BOT_NAME=//p' ~/.clawdbot/.env 2>/dev/null") || true
  claw_info "Original BOT_NAME: ${original_bot_name:-none}"

  local original_workspace_files="0"
  original_workspace_files=$(e2e_ssh "ls ~/clawd/ 2>/dev/null | wc -l") || true
  claw_info "Existing workspace has $original_workspace_files files/dirs"

  #---------------------------------------------------------------------------
  # Step 2: Build workspace tarball + deploy apply-env.sh
  #---------------------------------------------------------------------------
  claw_info "Step 2: Building workspace tarball and deploying infra scripts"

  local staging_dir
  staging_dir=$(mktemp -d)
  local tarball="$staging_dir/workspace.tar.gz"

  mkdir -p "$staging_dir/clawd/scripts" "$staging_dir/clawd/memory"

  # Copy workspace templates (strip .tmpl extension)
  for tmpl in "$workspace_tmpl"/*.tmpl; do
    [ -f "$tmpl" ] || continue
    local fname
    fname=$(basename "$tmpl" .tmpl)
    cp "$tmpl" "$staging_dir/clawd/$fname"
  done

  # Copy memory templates
  for f in "$memory_tmpl"/*.json; do
    [ -f "$f" ] || continue
    cp "$f" "$staging_dir/clawd/memory/"
  done

  # Copy task queue scripts
  for f in "$task_queue"/*; do
    [ -f "$f" ] || continue
    cp "$f" "$staging_dir/clawd/scripts/"
  done
  chmod +x "$staging_dir/clawd/scripts/tq" "$staging_dir/clawd/scripts/"*.sh 2>/dev/null || true

  # Create tarball
  tar -czf "$tarball" -C "$staging_dir" clawd/

  local tarball_size
  tarball_size=$(wc -c < "$tarball" | tr -d ' ')
  claw_info "Tarball: ${tarball_size} bytes, $(tar -tzf "$tarball" | grep -v '/$' | wc -l | tr -d ' ') files"

  # SCP workspace tarball
  if ! e2e_scp_to "$tarball" "/tmp/workspace.tar.gz"; then
    claw_fail "Failed to SCP workspace tarball" "workspace_scp" "$(e2e_timer_ms "$t")"
    rm -rf "$staging_dir"
    return
  fi

  # SCP apply-env.sh and agent-kit-setup.sh (may not be baked into this AMI)
  if ! e2e_scp_to "$apply_env_src" "/tmp/apply-env.sh"; then
    claw_fail "Failed to SCP apply-env.sh" "apply_env_scp" "$(e2e_timer_ms "$t")"
    rm -rf "$staging_dir"
    return
  fi
  e2e_scp_to "$agent_kit_setup_src" "/tmp/agent-kit-setup.sh" || true

  # Install scripts and deploy agent-kit core
  local setup_output=""
  setup_output=$(e2e_ssh "sudo mkdir -p /opt/os1/agent-kit/core && sudo cp /tmp/apply-env.sh /opt/os1/apply-env.sh && sudo chmod +x /opt/os1/apply-env.sh && sudo cp /tmp/agent-kit-setup.sh /opt/os1/agent-kit-setup.sh 2>/dev/null; sudo chmod +x /opt/os1/agent-kit-setup.sh 2>/dev/null; rm -f /tmp/apply-env.sh /tmp/agent-kit-setup.sh && echo OK") || true
  if [[ "$setup_output" != *"OK"* ]]; then
    claw_fail "Failed to install scripts on instance" "scripts_install" "$(e2e_timer_ms "$t")"
    rm -rf "$staging_dir"
    return
  fi

  # Deploy agent-kit core files if not already baked
  if ! e2e_ssh "test -x /opt/os1/agent-kit/core/task-queue/tq" 2>/dev/null; then
    claw_info "Agent-kit core not baked — deploying from local repo"
    local ak_tarball="$staging_dir/agent-kit-core.tar.gz"
    tar -czf "$ak_tarball" -C "$agent_kit" core/task-queue core/messaging core/auth-layer 2>/dev/null
    if e2e_scp_to "$ak_tarball" "/tmp/agent-kit-core.tar.gz"; then
      e2e_ssh "cd /opt/os1/agent-kit && sudo tar -xzf /tmp/agent-kit-core.tar.gz 2>/dev/null; sudo chmod +x /opt/os1/agent-kit/core/task-queue/tq /opt/os1/agent-kit/core/task-queue/*.sh 2>/dev/null; cd /opt/os1/agent-kit/core/auth-layer && sudo npm install --production --no-audit --no-fund 2>/dev/null; rm -f /tmp/agent-kit-core.tar.gz" || true
      claw_info "Agent-kit core deployed"
    fi
  fi

  # Create agent-kit .env with defaults if not present
  if ! e2e_ssh "test -f /opt/os1/agent-kit/.env" 2>/dev/null; then
    e2e_ssh "sudo bash -c 'echo \"CLAWDBOT_WORKSPACE_DIR=/home/ubuntu/clawd
TQ_DB=/data/taskq/taskq.db
AGENT_KEY_DIR=/home/ubuntu/.os1/keys\" > /opt/os1/agent-kit/.env' && sudo chown ubuntu:ubuntu /opt/os1/agent-kit/.env && sudo chmod 600 /opt/os1/agent-kit/.env" || true
  fi
  claw_info "apply-env.sh + agent-kit installed"

  #---------------------------------------------------------------------------
  # Step 3: Extract workspace
  #---------------------------------------------------------------------------
  claw_info "Step 3: Deploying workspace to instance"

  local extract_output=""
  extract_output=$(e2e_ssh "cp -a ~/clawd ~/clawd.bak.\$(date +%s) 2>/dev/null; tar -xzf /tmp/workspace.tar.gz -C ~/ && chmod +x ~/clawd/scripts/tq ~/clawd/scripts/*.sh 2>/dev/null; rm -f /tmp/workspace.tar.gz; echo OK") || true
  if [[ "$extract_output" != *"OK"* ]]; then
    claw_fail "Failed to extract workspace" "workspace_extract" "$(e2e_timer_ms "$t")"
    rm -rf "$staging_dir"
    return
  fi
  claw_info "Workspace extracted successfully"

  rm -rf "$staging_dir"

  #---------------------------------------------------------------------------
  # Step 4: Verify workspace files
  #---------------------------------------------------------------------------
  claw_info "Step 4: Verifying deployed workspace files"

  local expected_docs=("SOUL.md" "AGENTS.md" "IDENTITY.md" "HEARTBEAT.md" "TOOLS.md" "MEMORY.md" "USER.md" "EVOLUTION.md")
  for doc in "${expected_docs[@]}"; do
    if ! e2e_ssh "test -f ~/clawd/$doc"; then
      claw_fail "Workspace doc missing: ~/clawd/$doc" "workspace_file_$doc" "0"
      failures=$((failures + 1))
    fi
  done

  local expected_memory=("goals.json" "metrics.json" "streaks.json" "todo.json")
  for mem in "${expected_memory[@]}"; do
    if ! e2e_ssh "test -f ~/clawd/memory/$mem"; then
      claw_fail "Memory template missing: ~/clawd/memory/$mem" "workspace_memory_$mem" "0"
      failures=$((failures + 1))
    fi
  done

  if ! e2e_ssh "test -x ~/clawd/scripts/tq"; then
    claw_fail "tq CLI missing or not executable" "workspace_tq" "0"
    failures=$((failures + 1))
  fi

  if ! e2e_ssh "test -f ~/clawd/scripts/tq-schema.sql"; then
    claw_fail "tq schema missing" "workspace_tq_schema" "0"
    failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    claw_info "All workspace files verified"
  fi

  #---------------------------------------------------------------------------
  # Step 5: Inject env vars — test ALL routing types
  #---------------------------------------------------------------------------
  claw_info "Step 5: Injecting env vars via apply-env.sh (all routing types)"

  local test_bot_name="claw-bench-test-bot"
  local test_model="amazon.nova-lite-v1:0"
  local test_neon_url="postgresql://test:test@neon.example.com/agents"
  local test_known_agents="alice,bob,carol"

  # Build a manifest that exercises identity, config-json, and agent-kit types
  local manifest_json
  manifest_json=$(printf '{"BOT_NAME":"%s","MODEL_ID":"%s","AGENT_NEON_URL":"%s","AGENT_KNOWN_AGENTS":"%s"}' \
    "$test_bot_name" "$test_model" "$test_neon_url" "$test_known_agents")
  local env_manifest
  env_manifest=$(echo "$manifest_json" | base64)

  local apply_output=""
  apply_output=$(e2e_ssh "echo '$env_manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null) || true

  if [[ "$apply_output" == *"ERROR"* ]] || [ -z "$apply_output" ]; then
    claw_fail "apply-env.sh failed: $apply_output" "envsync_apply" "0"
    failures=$((failures + 1))
  else
    claw_info "apply-env.sh output: $(echo "$apply_output" | tr '\n' ' ')"
  fi

  #---------------------------------------------------------------------------
  # Step 6: Verify IDENTITY routing (BOT_NAME → 3 destinations)
  #---------------------------------------------------------------------------
  claw_info "Step 6: Verifying identity routing (BOT_NAME)"

  # 6a. BOT_NAME in .clawdbot/.env
  local env_bot_name=""
  env_bot_name=$(e2e_ssh "sed -n 's/^BOT_NAME=//p' ~/.clawdbot/.env") || true
  if [ "$env_bot_name" = "$test_bot_name" ]; then
    claw_info "  .env BOT_NAME: $env_bot_name"
  else
    claw_fail "BOT_NAME not in .clawdbot/.env: got '$env_bot_name'" "identity_dotenv" "0"
    failures=$((failures + 1))
  fi

  # 6b. AGENT_NAME alias in .clawdbot/.env
  local env_agent_name=""
  env_agent_name=$(e2e_ssh "sed -n 's/^AGENT_NAME=//p' ~/.clawdbot/.env") || true
  if [ "$env_agent_name" = "$test_bot_name" ]; then
    claw_info "  .env AGENT_NAME alias: $env_agent_name"
  else
    claw_fail "AGENT_NAME alias not in .clawdbot/.env: got '$env_agent_name'" "identity_dotenv_alias" "0"
    failures=$((failures + 1))
  fi

  # 6c. IDENTITY.md contains the name
  local identity_md_name=""
  identity_md_name=$(e2e_ssh "grep -o 'Name:.*' ~/clawd/IDENTITY.md 2>/dev/null | head -1") || true
  if [[ "$identity_md_name" == *"$test_bot_name"* ]]; then
    claw_info "  IDENTITY.md: $identity_md_name"
  else
    claw_fail "IDENTITY.md not patched with name: got '$identity_md_name'" "identity_md" "0"
    failures=$((failures + 1))
  fi

  # 6d. Agent-kit .env has AGENT_NAME
  local ak_agent_name=""
  ak_agent_name=$(e2e_ssh "sed -n 's/^AGENT_NAME=//p' /opt/os1/agent-kit/.env") || true
  if [ "$ak_agent_name" = "$test_bot_name" ]; then
    claw_info "  agent-kit .env AGENT_NAME: $ak_agent_name"
  else
    claw_fail "AGENT_NAME not in agent-kit .env: got '$ak_agent_name'" "identity_agent_kit" "0"
    failures=$((failures + 1))
  fi

  #---------------------------------------------------------------------------
  # Step 7: Verify CONFIG-JSON routing (MODEL_ID → .env + clawdbot.json)
  #---------------------------------------------------------------------------
  claw_info "Step 7: Verifying config-json routing (MODEL_ID)"

  # 7a. MODEL_ID in .clawdbot/.env
  local env_model=""
  env_model=$(e2e_ssh "sed -n 's/^MODEL_ID=//p' ~/.clawdbot/.env") || true
  if [ "$env_model" = "$test_model" ]; then
    claw_info "  .env MODEL_ID: $env_model"
  else
    claw_fail "MODEL_ID not in .clawdbot/.env: got '$env_model'" "model_dotenv" "0"
    failures=$((failures + 1))
  fi

  # 7b. clawdbot.json model.primary
  local json_model=""
  json_model=$(e2e_ssh "jq -r '.agents.defaults.model.primary // empty' ~/.clawdbot/clawdbot.json") || true
  if [[ "$json_model" == *"$test_model"* ]]; then
    claw_info "  clawdbot.json model.primary: $json_model"
  else
    claw_fail "model.primary not in clawdbot.json: got '$json_model'" "model_config_json" "0"
    failures=$((failures + 1))
  fi

  # 7c. clawdbot.json bedrock model ID
  local json_bedrock_id=""
  json_bedrock_id=$(e2e_ssh "jq -r '.models.providers[\"amazon-bedrock\"].models[0].id // empty' ~/.clawdbot/clawdbot.json") || true
  if [ "$json_bedrock_id" = "$test_model" ]; then
    claw_info "  clawdbot.json bedrock model id: $json_bedrock_id"
  else
    claw_fail "bedrock model id not set: got '$json_bedrock_id'" "model_bedrock_id" "0"
    failures=$((failures + 1))
  fi

  #---------------------------------------------------------------------------
  # Step 8: Verify AGENT-KIT routing (AGENT_NEON_URL, AGENT_KNOWN_AGENTS)
  #---------------------------------------------------------------------------
  claw_info "Step 8: Verifying agent-kit routing"

  # 8a. AGENT_NEON_URL in agent-kit .env
  local ak_neon=""
  ak_neon=$(e2e_ssh "sed -n 's/^AGENT_NEON_URL=//p' /opt/os1/agent-kit/.env") || true
  if [ "$ak_neon" = "$test_neon_url" ]; then
    claw_info "  agent-kit .env AGENT_NEON_URL: set correctly"
  else
    claw_fail "AGENT_NEON_URL not in agent-kit .env: got '$ak_neon'" "agentkit_neon" "0"
    failures=$((failures + 1))
  fi

  # 8b. AGENT_KNOWN_AGENTS in agent-kit .env
  local ak_agents=""
  ak_agents=$(e2e_ssh "sed -n 's/^AGENT_KNOWN_AGENTS=//p' /opt/os1/agent-kit/.env") || true
  if [ "$ak_agents" = "$test_known_agents" ]; then
    claw_info "  agent-kit .env AGENT_KNOWN_AGENTS: $ak_agents"
  else
    claw_fail "AGENT_KNOWN_AGENTS not in agent-kit .env: got '$ak_agents'" "agentkit_known" "0"
    failures=$((failures + 1))
  fi

  # 8c. AGENT_NEON_URL also in .clawdbot/.env (apply-env.sh writes to both)
  local env_neon=""
  env_neon=$(e2e_ssh "sed -n 's/^AGENT_NEON_URL=//p' ~/.clawdbot/.env") || true
  if [ "$env_neon" = "$test_neon_url" ]; then
    claw_info "  .clawdbot/.env AGENT_NEON_URL: set correctly"
  else
    claw_fail "AGENT_NEON_URL not in .clawdbot/.env: got '$env_neon'" "agentkit_neon_dotenv" "0"
    failures=$((failures + 1))
  fi

  #---------------------------------------------------------------------------
  # Step 9: Restore config for clean restart
  #---------------------------------------------------------------------------
  claw_info "Step 9: Restoring config for clean restart"

  # Restore original model (test model may not be valid for Bedrock)
  if [ -n "$original_model" ]; then
    local restore_model
    restore_model=$(echo "$original_model" | sed 's|.*/||')
    local restore_manifest
    restore_manifest=$(printf '{"MODEL_ID":"%s"}' "$restore_model" | base64)
    e2e_ssh "echo '$restore_manifest' | base64 -d | sudo /opt/os1/apply-env.sh" 2>/dev/null || true
    claw_info "Restored original model: $restore_model"
  fi

  #---------------------------------------------------------------------------
  # Step 10: Restart clawdbot and verify gateway
  #---------------------------------------------------------------------------
  claw_info "Step 10: Restarting clawdbot service"

  e2e_ssh "sudo systemctl restart clawdbot" 2>/dev/null || true

  # Wait for gateway to come back up (poll for up to 30s)
  local gateway_up=false
  for i in $(seq 1 6); do
    sleep 5
    local http_code=""
    http_code=$(e2e_ssh 'curl -sf -o /dev/null -w "%{http_code}" http://localhost:18789/ 2>/dev/null || echo "000"') || true
    if [ "$http_code" = "200" ]; then
      gateway_up=true
      claw_info "Gateway responded 200 after $((i * 5))s"
      break
    fi
  done

  if [ "$gateway_up" = "false" ]; then
    claw_fail "Gateway did not respond after restart (30s timeout)" "restart_gateway" "0"
    failures=$((failures + 1))

    local svc_status=""
    svc_status=$(e2e_ssh "systemctl is-active clawdbot 2>/dev/null || echo 'unknown'") || true
    claw_info "Service status: $svc_status"
    local journal=""
    journal=$(e2e_ssh "sudo journalctl -u clawdbot --no-pager -n 5 2>/dev/null || echo 'no journal'") || true
    claw_info "Journal: $(echo "$journal" | tail -3)"
  fi

  local svc_active=""
  svc_active=$(e2e_ssh "systemctl is-active clawdbot 2>/dev/null || echo 'inactive'") || true
  if [ "$svc_active" = "active" ]; then
    claw_info "clawdbot service: active"
  else
    claw_fail "clawdbot service not active: $svc_active" "restart_service" "0"
    failures=$((failures + 1))
  fi

  #---------------------------------------------------------------------------
  # Result
  #---------------------------------------------------------------------------
  if [ "$failures" -eq 0 ]; then
    claw_pass "Workspace deployed, all env routing verified (identity/config-json/agent-kit), gateway healthy" "workspace_deploy_and_restart" "$(e2e_timer_ms "$t")"
  fi
}
