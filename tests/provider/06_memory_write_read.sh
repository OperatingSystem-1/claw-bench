#!/bin/bash
# Provider Test: Memory Write + Search
# Verifies the memory tools work with this provider.
#
# Pass: Fact stored and recalled
# Fail: Memory not recalled

test_memory_write_read() {
  claw_header "PROVIDER 06: Memory Write + Search"

  local start_s end_s duration
  start_s=$(date +%s)

  local fact="The provider test secret code is PROVMEM$(date +%s)"

  # Store a fact
  local store_response
  store_response=$(claw_ask "Use the memory tool to remember this fact: $fact")

  if claw_is_empty "$store_response"; then
    end_s=$(date +%s)
    duration=$(( (end_s - start_s) * 1000 ))
    claw_critical "Empty response on memory store" "memory_write_read" "$duration"
    return
  fi

  # Recall it (new session to avoid context cheating)
  local recall_response
  recall_response=$(claw_ask "Search your memory for 'provider test secret code' and tell me the code.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$recall_response"; then
    claw_fail "Empty response on memory recall" "memory_write_read" "$duration"
  elif [[ "$recall_response" == *"PROVMEM"* ]]; then
    claw_pass "Memory write/search works: fact recalled" "memory_write_read" "$duration"
  else
    claw_fail "Fact not recalled: ${recall_response:0:300}" "memory_write_read" "$duration"
  fi
}
