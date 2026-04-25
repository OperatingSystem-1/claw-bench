#!/bin/bash
# benchmark-providers.sh — Provider × Tool-Use Smoke Test
#
# Tests that each LLM provider correctly supports openclaw's tool-calling
# protocol (exec, file read/write, web_fetch, memory, multi-tool, etc.).
#
# Usage:
#   ./benchmark-providers.sh --k8s <namespace> <agent>    Test on K8s agent
#   ./benchmark-providers.sh --ssh                        Test on SSH host
#   ./benchmark-providers.sh --local                      Test on local clawdbot
#
# Options:
#   --provider <key>    Test only this provider (e.g., "gemini-flash")
#   --no-switch         Skip provider switching (test current config only)
#   --no-restore        Don't restore original config after testing
#   --json              Output results as JSON
#   --tap               Output results as TAP
#
# Examples:
#   # Test all providers on a K8s agent
#   ./benchmark-providers.sh --k8s office-cloud-ridge-8de4eec7 os1-jude
#
#   # Test just Gemini on current agent config (no switching)
#   CLAW_MODE=k8s CLAW_K8S_NAMESPACE=office-cloud-ridge-8de4eec7 CLAW_K8S_AGENT=os1-jude \
#     ./benchmark-providers.sh --no-switch
#
#   # Test specific provider via SSH
#   CLAW_HOST=ubuntu@18.119.97.216 ./benchmark-providers.sh --ssh --provider bedrock-sonnet

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAW_BENCH_DIR="$SCRIPT_DIR"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/k8s-common.sh
source "$SCRIPT_DIR/lib/k8s-common.sh"

PROVIDERS_FILE="${SCRIPT_DIR}/providers-to-test.json"
PROVIDER_FILTER=""
NO_SWITCH=false
NO_RESTORE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --k8s)
      CLAW_MODE="k8s"
      CLAW_K8S_NAMESPACE="${2:-}"
      CLAW_K8S_AGENT="${3:-}"
      shift 3
      ;;
    --ssh)    CLAW_MODE="ssh"; shift ;;
    --local)  CLAW_MODE="local"; shift ;;
    --provider) PROVIDER_FILTER="$2"; shift 2 ;;
    --no-switch) NO_SWITCH=true; shift ;;
    --no-restore) NO_RESTORE=true; shift ;;
    --json)   CLAW_OUTPUT="json"; shift ;;
    --tap)    CLAW_OUTPUT="tap"; shift ;;
    --help)
      head -30 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 3 ;;
  esac
done

export CLAW_MODE CLAW_K8S_NAMESPACE CLAW_K8S_AGENT CLAW_OUTPUT
claw_init

# Load provider tests
PROVIDER_TESTS=()
for f in "$SCRIPT_DIR/tests/provider/"*.sh; do
  [ -f "$f" ] && PROVIDER_TESTS+=("$f")
done

if [ ${#PROVIDER_TESTS[@]} -eq 0 ]; then
  echo "Error: No provider tests found in tests/provider/" >&2
  exit 3
fi

echo -e "${BOLD}Provider × Tool-Use Smoke Test${NC}"
echo "Mode: $CLAW_MODE | Tests: ${#PROVIDER_TESTS[@]}"
[ "$CLAW_MODE" = "k8s" ] && echo "Agent: $CLAW_K8S_NAMESPACE/$CLAW_K8S_AGENT"
echo ""

# Save original config for restoration
if [ "$CLAW_MODE" = "k8s" ] && [ "$NO_SWITCH" = false ] && [ "$NO_RESTORE" = false ]; then
  k8s_save_original "$CLAW_K8S_NAMESPACE" "$CLAW_K8S_AGENT"
  trap 'echo ""; echo "Restoring original config..."; k8s_restore_original "$CLAW_K8S_NAMESPACE" "$CLAW_K8S_AGENT"' EXIT
fi

# Load test functions
for test_file in "${PROVIDER_TESTS[@]}"; do
  source "$test_file"
done

run_provider_tests() {
  local provider_key="$1"
  echo -e "\n${BOLD}═══ Provider: ${provider_key} ═══${NC}\n"

  for test_file in "${PROVIDER_TESTS[@]}"; do
    local test_name
    test_name=$(basename "$test_file" .sh | sed 's/^[0-9]*_//')
    local func_name="test_${test_name}"

    if declare -f "$func_name" >/dev/null 2>&1; then
      $func_name
    else
      echo -e "${YELLOW}SKIP${NC} $test_name (function $func_name not found)"
    fi
    echo ""
  done
}

# ── No-switch mode: just run tests against current config ──
if [ "$NO_SWITCH" = true ]; then
  run_provider_tests "current"
  echo ""
  claw_summary_"${CLAW_OUTPUT:-human}"
  claw_exit
fi

# ── Provider matrix mode ──
if [ ! -f "$PROVIDERS_FILE" ]; then
  echo "Error: $PROVIDERS_FILE not found" >&2
  exit 3
fi

# Read provider list
provider_count=$(jq '.providers | length' "$PROVIDERS_FILE")
echo "Providers to test: $provider_count"

# Resolve {officeId} placeholder in secret names
office_id=""
if [ "$CLAW_MODE" = "k8s" ]; then
  # Extract office ID from namespace (office-<name>-<suffix> → look up in DB)
  # For now, use the namespace as-is in secret names
  office_id=$(kubectl --context "$K8S_CTX" -n "$CLAW_K8S_NAMESPACE" get openclawinstance "$CLAW_K8S_AGENT" -o json 2>/dev/null | \
    python3 -c "import sys,json; [print(e['value']) for e in json.load(sys.stdin)['spec'].get('env',[]) if e.get('name')=='OFFICE_ID']" 2>/dev/null | head -1)
fi

for i in $(seq 0 $((provider_count - 1))); do
  prov_json=$(jq -c ".providers[$i]" "$PROVIDERS_FILE")
  prov_key=$(echo "$prov_json" | jq -r '.key')

  # Apply filter
  if [ -n "$PROVIDER_FILTER" ] && [ "$prov_key" != "$PROVIDER_FILTER" ]; then
    continue
  fi

  # Resolve {officeId} in secretName
  if [ -n "$office_id" ]; then
    prov_json=$(echo "$prov_json" | sed "s/{officeId}/$office_id/g")
  fi

  echo -e "\n${BLUE}━━━ Switching to: $prov_key ━━━${NC}"

  case "$CLAW_MODE" in
    k8s)
      k8s_switch_provider "$CLAW_K8S_NAMESPACE" "$CLAW_K8S_AGENT" "$prov_json"
      ;;
    ssh)
      local model_id api
      model_id=$(echo "$prov_json" | jq -r '.modelId')
      local provider_id
      provider_id=$(echo "$prov_json" | jq -r '.provider')
      api=$(echo "$prov_json" | jq -r '.api')
      local base_url
      base_url=$(echo "$prov_json" | jq -r '.baseUrl')

      ssh -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" -n "
        jq '.models.providers = {\"${provider_id}\": {\"api\": \"${api}\", \"auth\": \"api-key\", \"baseUrl\": \"${base_url}\", \"models\": [{\"id\": \"${model_id}\", \"name\": \"$(echo "$prov_json" | jq -r '.modelName // "sonnet"')\"}]}} | .agents.defaults.model.primary = \"${provider_id}/${model_id}\"' ~/.clawdbot/clawdbot.json > /tmp/clawdbot.json.new && mv /tmp/clawdbot.json.new ~/.clawdbot/clawdbot.json
        rm -rf ~/.clawdbot/sessions/* ~/.clawdbot/agents/*/sessions/* 2>/dev/null || true
        sudo systemctl restart clawdbot
        sleep 10
        for i in \$(seq 1 15); do curl -sf http://localhost:18789/ >/dev/null 2>&1 && exit 0; sleep 2; done
        exit 1
      " 2>&1
      ;;
    local)
      echo "  Local mode: manually configure your clawdbot to use $prov_key before running"
      ;;
  esac

  run_provider_tests "$prov_key"
done

echo ""
echo -e "${BOLD}═══ Summary ═══${NC}"
claw_summary_"${CLAW_OUTPUT:-human}"
claw_exit
