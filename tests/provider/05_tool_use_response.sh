#!/bin/bash
# Provider Test: Tool Use Response (silent completion detection)
# Many providers call tools but return empty payloads — a critical protocol bug.
#
# Pass: Tool called AND non-empty text response returned
# Critical: Empty payload after tool use

test_tool_use_response() {
  claw_header "PROVIDER 05: Tool Use Response (silent completion check)"

  local start_s end_s duration
  start_s=$(date +%s)

  local json_response
  json_response=$(claw_ask_json "Run 'date' and tell me what day of the week it is.")

  local payloads output_tokens
  payloads=$(echo "$json_response" | jq -r '.result.payloads | length' 2>/dev/null || echo "0")
  output_tokens=$(echo "$json_response" | jq -r '.result.meta.agentMeta.usage.output' 2>/dev/null || echo "0")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_json_has_empty_payload "$json_response"; then
    claw_critical "SILENT TOOL COMPLETION — tool called but no response text returned" "tool_use_response" "$duration"
  elif [ "$payloads" = "0" ]; then
    claw_critical "Zero payloads in response" "tool_use_response" "$duration"
  else
    local text
    text=$(echo "$json_response" | jq -r '.result.payloads[0].text // ""' 2>/dev/null)
    if [ -n "$text" ] && [ "$text" != "null" ]; then
      claw_pass "Tool used AND text response returned ($output_tokens tokens)" "tool_use_response" "$duration"
    else
      claw_fail "Payloads present but text empty" "tool_use_response" "$duration"
    fi
  fi
}
