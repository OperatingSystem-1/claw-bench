#!/bin/bash
# claw-bench/lib/k8s-common.sh
# K8s-specific helpers for provider benchmarking

K8S_CTX="${CLAW_K8S_CONTEXT:-arn:aws:eks:us-east-2:856898221895:cluster/os1-production}"

# Switch the LLM provider on a K8s agent by patching ConfigMap + CRD
# Usage: k8s_switch_provider <namespace> <agent> <provider_json>
#   provider_json: { "provider": "google", "api": "google-generative-ai",
#                    "baseUrl": "...", "modelId": "gemini-2.5-flash",
#                    "modelName": "sonnet", "secretName": "...", "contextWindow": N }
k8s_switch_provider() {
  local namespace="$1"
  local agent="$2"
  local prov_json="$3"

  local provider api base_url model_id model_name secret_name ctx_window max_tokens
  provider=$(echo "$prov_json" | jq -r '.provider')
  api=$(echo "$prov_json" | jq -r '.api')
  base_url=$(echo "$prov_json" | jq -r '.baseUrl')
  model_id=$(echo "$prov_json" | jq -r '.modelId')
  model_name=$(echo "$prov_json" | jq -r '.modelName // "sonnet"')
  secret_name=$(echo "$prov_json" | jq -r '.secretName // empty')
  ctx_window=$(echo "$prov_json" | jq -r '.contextWindow // 200000')
  max_tokens=$(echo "$prov_json" | jq -r '.maxTokens // 8192')

  echo "  Patching ConfigMap ${agent}-gateway-config..."

  # Get current config, swap the model/provider
  local current_config
  current_config=$(kubectl --context "$K8S_CTX" -n "$namespace" \
    get configmap "${agent}-gateway-config" -o jsonpath='{.data.openclaw\.json}' 2>/dev/null)

  if [ -z "$current_config" ]; then
    echo "  ERROR: ConfigMap ${agent}-gateway-config not found" >&2
    return 1
  fi

  local new_config
  new_config=$(echo "$current_config" | python3 -c "
import sys, json
cfg = json.load(sys.stdin)
cfg['agents']['defaults']['model']['primary'] = '${provider}/${model_id}'
cfg['agents']['defaults']['model']['fallbacks'] = []
cfg['models'] = cfg.get('models', {})
cfg['models']['providers'] = {
    '${provider}': {
        'api': '${api}',
        'auth': '$(echo "$prov_json" | jq -r '.auth // "api-key"')',
        'baseUrl': '${base_url}',
        'models': [{
            'id': '${model_id}',
            'name': '${model_name}',
            'contextWindow': ${ctx_window},
            'maxTokens': ${max_tokens}
        }]
    }
}
json.dump(cfg, sys.stdout)
" 2>/dev/null)

  if [ -z "$new_config" ]; then
    echo "  ERROR: Failed to generate new config" >&2
    return 1
  fi

  echo "$new_config" > "/tmp/k8s-bench-${agent}-config.json"

  kubectl --context "$K8S_CTX" -n "$namespace" \
    create configmap "${agent}-gateway-config" \
    --from-file="openclaw.json=/tmp/k8s-bench-${agent}-config.json" \
    --dry-run=client -o yaml | \
    kubectl --context "$K8S_CTX" apply -f - >/dev/null 2>&1

  # Patch CRD env vars
  echo "  Patching CRD env vars..."
  kubectl --context "$K8S_CTX" -n "$namespace" get openclawinstance "$agent" -o json 2>/dev/null | \
    python3 -c "
import sys, json
obj = json.load(sys.stdin)
for e in obj['spec'].get('env', []):
    if e['name'] == 'LLM_PROVIDER': e['value'] = '${provider}'
    if e['name'] == 'LLM_MODEL_TIER': e['value'] = '${model_name}'
json.dump(obj, sys.stdout)
" > "/tmp/k8s-bench-${agent}-crd.json" 2>/dev/null

  kubectl --context "$K8S_CTX" -n "$namespace" apply -f "/tmp/k8s-bench-${agent}-crd.json" >/dev/null 2>&1

  # Mount provider secret if specified
  if [ -n "$secret_name" ]; then
    local already_mounted
    already_mounted=$(kubectl --context "$K8S_CTX" -n "$namespace" get openclawinstance "$agent" -o json 2>/dev/null | \
      python3 -c "
import sys, json
obj = json.load(sys.stdin)
for ef in obj['spec'].get('envFrom', []):
    if ef.get('secretRef', {}).get('name') == '${secret_name}':
        print('yes')
        break
" 2>/dev/null)

    if [ "$already_mounted" != "yes" ]; then
      echo "  Mounting secret $secret_name..."
      kubectl --context "$K8S_CTX" -n "$namespace" \
        patch openclawinstance "$agent" --type='json' \
        -p "[{\"op\":\"add\",\"path\":\"/spec/envFrom/-\",\"value\":{\"secretRef\":{\"name\":\"${secret_name}\",\"optional\":true}}}]" \
        >/dev/null 2>&1
    fi
  fi

  # Restart pod
  echo "  Restarting pod..."
  kubectl --context "$K8S_CTX" -n "$namespace" delete pod "${agent}-0" >/dev/null 2>&1

  # Wait for ready
  k8s_wait_ready "$namespace" "$agent" 120
}

# Wait for agent pod to be fully ready
# Usage: k8s_wait_ready <namespace> <agent> <timeout_seconds>
k8s_wait_ready() {
  local namespace="$1"
  local agent="$2"
  local timeout="${3:-120}"

  echo "  Waiting for ${agent}-0 to be ready (${timeout}s timeout)..."
  local elapsed=0
  while [ $elapsed -lt "$timeout" ]; do
    local ready
    ready=$(kubectl --context "$K8S_CTX" -n "$namespace" get pod "${agent}-0" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null | tr ' ' '\n' | grep -c "true")
    local total
    total=$(kubectl --context "$K8S_CTX" -n "$namespace" get pod "${agent}-0" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null | wc -w | tr -d ' ')

    if [ "$ready" = "$total" ] && [ "$total" -gt 0 ]; then
      echo "  Ready ($ready/$total containers)"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "  WARNING: Pod not ready after ${timeout}s ($ready/$total containers)" >&2
  return 1
}

# Cleanup: restore original provider (call at end of benchmark)
# Saves original config before first switch, restores on exit
k8s_save_original() {
  local namespace="$1"
  local agent="$2"

  kubectl --context "$K8S_CTX" -n "$namespace" \
    get configmap "${agent}-gateway-config" -o jsonpath='{.data.openclaw\.json}' \
    > "/tmp/k8s-bench-${agent}-original-config.json" 2>/dev/null

  kubectl --context "$K8S_CTX" -n "$namespace" \
    get openclawinstance "$agent" -o json \
    > "/tmp/k8s-bench-${agent}-original-crd.json" 2>/dev/null
}

k8s_restore_original() {
  local namespace="$1"
  local agent="$2"

  if [ -f "/tmp/k8s-bench-${agent}-original-config.json" ]; then
    echo "Restoring original config for $agent..."
    kubectl --context "$K8S_CTX" -n "$namespace" \
      create configmap "${agent}-gateway-config" \
      --from-file="openclaw.json=/tmp/k8s-bench-${agent}-original-config.json" \
      --dry-run=client -o yaml | \
      kubectl --context "$K8S_CTX" apply -f - >/dev/null 2>&1
  fi

  if [ -f "/tmp/k8s-bench-${agent}-original-crd.json" ]; then
    kubectl --context "$K8S_CTX" -n "$namespace" \
      apply -f "/tmp/k8s-bench-${agent}-original-crd.json" >/dev/null 2>&1
    kubectl --context "$K8S_CTX" -n "$namespace" delete pod "${agent}-0" >/dev/null 2>&1
  fi
}
