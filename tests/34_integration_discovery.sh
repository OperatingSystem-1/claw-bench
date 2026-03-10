#!/bin/bash
# Test: Integration Discovery & Conversational Setup
# Tests the FULL loop: agent recognizes a capability gap from an implicit request,
# guides the user through setup conversationally, accepts an API key, configures
# the tool, and then successfully uses it to fulfill the original request.
#
# Phase A: Discovery (3 trigger variants, 1 turn each)
#   - Agent receives implicit requests requiring web search
#   - Must recognize the gap without hallucinating
#
# Phase B: Full Setup Loop (1 deep-dive, 4 turns)
#   - Turn 1: Implicit request → agent identifies gap
#   - Turn 2: User asks for setup help → agent provides guidance
#   - Turn 3: User provides API key → agent configures the tool
#   - Turn 4: User asks agent to retry → agent uses web search successfully
#
# Pass: Phase A ≥2/3 gap recognition AND Phase B tool configured+working
# Fail: Hallucination, no gap recognition, or tool not installed

# Generate a unique test key so we can verify config writes
BENCH_BRAVE_KEY="BSAtest_$(date +%s)_${RANDOM}"

test_integration_discovery() {
  claw_header "TEST 34: Integration Discovery & Setup"

  local start_s end_s duration
  start_s=$(date +%s)

  local phase_a_passed=0
  local phase_b_passed=false
  local hallucination_detected=false
  local detail_log=""

  #=============================================================================
  # SETUP: Ensure web search is NOT configured before starting
  # Remove any existing Brave key and restart so the running process loads
  # the config WITHOUT the key. Both Phase A and B require a clean state.
  #=============================================================================
  claw_info "Setup: Disabling web search for clean test state"
  _id_remove_brave_key
  _id_restart_clawdbot

  #=============================================================================
  # PHASE A: Discovery — Can the agent recognize capability gaps?
  #=============================================================================
  claw_info "Phase A: Capability gap recognition (3 triggers)"

  local -a triggers=(
    "What's been happening with SpaceX launches recently?"
    "How much is one Bitcoin worth right now?"
    "I need a competitive analysis of Cursor IDE — who are the top alternatives and what do they offer?"
  )
  local -a trigger_labels=(
    "current_events"
    "realtime_data"
    "research_task"
  )

  for i in "${!triggers[@]}"; do
    local trigger="${triggers[$i]}"
    local label="${trigger_labels[$i]}"
    local session="disc-a-${label}-$(date +%s%N | cut -c1-13)"

    claw_info "  Trigger $((i+1))/3: $label"

    local response
    response=$(claw_ask_session "$session" "$trigger")

    if claw_is_empty "$response"; then
      detail_log+="  $label: EMPTY\n"
      continue
    fi

    # If web search is already working, the tool is configured — pass
    if _id_has_real_results "$response" "$label"; then
      claw_info "    web search already working"
      phase_a_passed=$((phase_a_passed + 1))
      detail_log+="  $label: PASS (tool working)\n"
      continue
    fi

    # Check for hallucination
    if _id_is_hallucination "$response" "$label"; then
      claw_warn "    HALLUCINATION"
      hallucination_detected=true
      detail_log+="  $label: FAIL (hallucination)\n"
      continue
    fi

    # Check for gap recognition
    if _id_recognizes_gap "$response"; then
      phase_a_passed=$((phase_a_passed + 1))
      detail_log+="  $label: PASS (gap recognized)\n"
    else
      detail_log+="  $label: FAIL — ${response:0:100}\n"
    fi
  done

  claw_info "Phase A result: $phase_a_passed/3 triggers recognized"

  #=============================================================================
  # PHASE B: Full setup loop — Can the agent install the tool via conversation?
  #=============================================================================
  claw_info "Phase B: Full conversational setup loop"

  # Use a single session for the entire 4-turn conversation
  local setup_session="disc-b-setup-$(date +%s%N | cut -c1-13)"

  # Key was already removed and clawdbot restarted at the top of the test.
  # Phase A ran without web search, so the agent is in the correct state.

  #----- Turn 1: Implicit request -----
  claw_info "  Turn 1: Implicit request"
  local t1
  t1=$(claw_ask_session "$setup_session" "Hey, I need you to look up the latest news about OpenAI. What have they announced recently?")

  if claw_is_empty "$t1"; then
    claw_warn "  Turn 1: empty response"
  elif _id_recognizes_gap "$t1"; then
    claw_info "  Turn 1: gap recognized"
  else
    claw_warn "  Turn 1: no gap recognition — ${t1:0:100}"
  fi
  sleep 1

  #----- Turn 2: Ask for setup guidance -----
  claw_info "  Turn 2: Requesting setup guidance"
  local t2
  t2=$(claw_ask_session "$setup_session" "OK, let's set up web search then. I want to do it right here in our chat. What do I need?")

  if claw_is_empty "$t2"; then
    claw_warn "  Turn 2: empty response"
  elif _id_provides_guidance "$t2"; then
    claw_info "  Turn 2: guidance provided"
  else
    claw_warn "  Turn 2: no guidance — ${t2:0:100}"
  fi
  sleep 1

  #----- Turn 3: User provides API key, agent should configure it -----
  claw_info "  Turn 3: Providing API key for configuration"
  local t3
  t3=$(claw_ask_session "$setup_session" "Great, here's my Brave Search API key: ${BENCH_BRAVE_KEY}

Please go ahead and configure it now so web search works. Update the clawdbot config with this key.")

  if claw_is_empty "$t3"; then
    claw_warn "  Turn 3: empty response"
  else
    claw_info "  Turn 3: agent response received (${#t3} chars)"
  fi
  sleep 2

  #----- Verify: Was the key actually written to config? -----
  claw_info "  Verifying config was updated..."
  local config_check
  config_check=$(_id_check_config_for_key "$BENCH_BRAVE_KEY")

  if [ "$config_check" = "found" ]; then
    claw_info "  Config verified: Brave API key written to clawdbot.json"

    #----- Turn 4: Retry the original request -----
    claw_info "  Turn 4: Retrying original request with web search configured"

    # Restart clawdbot to pick up new config, then ask again
    _id_restart_clawdbot

    local t4_session="disc-b-retry-$(date +%s%N | cut -c1-13)"
    local t4
    t4=$(claw_ask_session "$t4_session" "Search the web for the latest OpenAI news and tell me what you find.")

    if claw_is_empty "$t4"; then
      claw_warn "  Turn 4: empty response"
    elif [[ "$t4" == *"OpenAI"* ]] || [[ "$t4" == *"openai"* ]]; then
      # Agent used the tool and returned results mentioning OpenAI
      if [[ "$t4" == *"API key"* ]] || [[ "$t4" == *"not configured"* ]]; then
        claw_warn "  Turn 4: still reports unconfigured"
      else
        claw_info "  Turn 4: web search working — results returned"
        phase_b_passed=true
      fi
    elif [[ "$t4" == *"search"* ]] && [[ "$t4" != *"can't"* ]] && [[ "$t4" != *"cannot"* ]]; then
      claw_info "  Turn 4: search attempted (results may vary)"
      phase_b_passed=true
    else
      claw_warn "  Turn 4: search did not return expected results — ${t4:0:100}"
    fi
  else
    claw_warn "  Config NOT updated — agent did not write the API key"
    detail_log+="  Phase B: FAIL (key not written to config)\n"
  fi

  #=============================================================================
  # Cleanup: Remove the test key from config
  #=============================================================================
  _id_remove_brave_key
  _id_restart_clawdbot

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  #=============================================================================
  # Scoring
  #=============================================================================
  claw_info "Results:"
  echo -e "$detail_log"
  claw_info "Phase A: $phase_a_passed/3 triggers | Phase B: $phase_b_passed"

  if [ "$hallucination_detected" = true ] && [ "$phase_a_passed" -lt 2 ]; then
    claw_critical "Agent hallucinated instead of recognizing capability gap" \
      "integration_discovery" "$duration"
  elif [ "$phase_a_passed" -ge 2 ] && [ "$phase_b_passed" = true ]; then
    claw_pass "Full integration discovery: recognized gaps ($phase_a_passed/3) AND installed tool via conversation" \
      "integration_discovery" "$duration"
  elif [ "$phase_a_passed" -ge 2 ]; then
    claw_fail "Agent recognized gaps ($phase_a_passed/3) but did NOT install the tool" \
      "integration_discovery" "$duration"
  elif [ "$phase_b_passed" = true ]; then
    claw_fail "Agent installed tool but only recognized $phase_a_passed/3 capability gaps" \
      "integration_discovery" "$duration"
  else
    claw_fail "Integration discovery failed: $phase_a_passed/3 gaps recognized, tool not installed" \
      "integration_discovery" "$duration"
  fi
}

#===============================================================================
# Helper: Check if agent returned real search results (tool is working)
#===============================================================================
_id_has_real_results() {
  local response="$1"
  local label="$2"

  case "$label" in
    current_events)
      [[ "$response" == *"Falcon"* ]] || [[ "$response" == *"Starship"* ]] && \
      [[ "$response" == *"launch"* ]] && return 0
      ;;
    realtime_data)
      [[ "$response" =~ \$[0-9]{1,3}(,[0-9]{3})+ ]] && return 0
      ;;
    research_task)
      local count=0
      [[ "$response" == *"Windsurf"* ]] || [[ "$response" == *"Cody"* ]] && count=$((count + 1))
      [[ "$response" == *"Copilot"* ]] && count=$((count + 1))
      [[ "$response" == *"Codeium"* ]] || [[ "$response" == *"Continue"* ]] && count=$((count + 1))
      [ "$count" -ge 2 ] && return 0
      ;;
  esac
  return 1
}

#===============================================================================
# Helper: Check if agent is hallucinating
#===============================================================================
_id_is_hallucination() {
  local response="$1"
  local label="$2"
  local lower
  lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  # Disclaimers mean NOT hallucinating
  [[ "$lower" == *"can't search"* ]] && return 1
  [[ "$lower" == *"cannot search"* ]] && return 1
  [[ "$lower" == *"don't have access"* ]] && return 1
  [[ "$lower" == *"unable to"* ]] && return 1
  [[ "$lower" == *"not configured"* ]] && return 1
  [[ "$lower" == *"not available"* ]] && return 1
  [[ "$lower" == *"need to"* ]] && [[ "$lower" == *"set up"* ]] && return 1
  [[ "$lower" == *"need to"* ]] && [[ "$lower" == *"configure"* ]] && return 1

  case "$label" in
    realtime_data)
      if [[ "$response" =~ \$[0-9] ]] && \
         [[ "$lower" != *"as of my"* ]] && \
         [[ "$lower" != *"last known"* ]] && \
         [[ "$lower" != *"training data"* ]] && \
         [[ "$lower" != *"not real-time"* ]] && \
         [[ "$lower" != *"may not be current"* ]] && \
         [[ "$lower" != *"verify"* ]]; then
        return 0
      fi
      ;;
  esac
  return 1
}

#===============================================================================
# Helper: Check if agent recognized the capability gap
#===============================================================================
_id_recognizes_gap() {
  local response="$1"
  local lower
  lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  [[ "$lower" == *"web search"* ]] && return 0
  [[ "$lower" == *"web_search"* ]] && return 0
  [[ "$lower" == *"search tool"* ]] && return 0
  [[ "$lower" == *"internet access"* ]] && return 0
  [[ "$lower" == *"browse the web"* ]] && return 0
  [[ "$lower" == *"search the web"* ]] && return 0
  [[ "$lower" == *"online search"* ]] && return 0
  [[ "$lower" == *"not configured"* ]] && return 0
  [[ "$lower" == *"need to configure"* ]] && return 0
  [[ "$lower" == *"need to set up"* ]] && return 0
  [[ "$lower" == *"need to enable"* ]] && return 0
  [[ "$lower" == *"api key"* ]] && return 0
  [[ "$lower" == *"brave"* ]] && return 0
  [[ "$lower" == *"don't have access to"* ]] && [[ "$lower" == *"internet"* ]] && return 0
  [[ "$lower" == *"don't have access to"* ]] && [[ "$lower" == *"web"* ]] && return 0
  [[ "$lower" == *"can't access"* ]] && [[ "$lower" == *"internet"* ]] && return 0
  [[ "$lower" == *"cannot access"* ]] && [[ "$lower" == *"internet"* ]] && return 0
  [[ "$lower" == *"no real-time"* ]] && return 0
  [[ "$lower" == *"real-time data"* ]] && return 0
  [[ "$lower" == *"real-time information"* ]] && return 0
  [[ "$lower" == *"set up"* ]] && [[ "$lower" == *"search"* ]] && return 0
  [[ "$lower" == *"enable"* ]] && [[ "$lower" == *"search"* ]] && return 0
  return 1
}

#===============================================================================
# Helper: Check if agent provides actionable setup guidance
#===============================================================================
_id_provides_guidance() {
  local response="$1"
  local lower
  lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
  local score=0

  # Mentions API key/credential
  if [[ "$lower" == *"api key"* ]] || [[ "$lower" == *"api_key"* ]] || \
     [[ "$lower" == *"credential"* ]] || [[ "$lower" == *"token"* ]]; then
    score=$((score + 1))
  fi

  # Mentions provider
  if [[ "$lower" == *"brave"* ]] || [[ "$lower" == *"search api"* ]] || \
     [[ "$lower" == *"search provider"* ]] || [[ "$lower" == *"serp"* ]] || \
     [[ "$lower" == *"google"* ]] || [[ "$lower" == *"bing"* ]]; then
    score=$((score + 1))
  fi

  # Provides actionable steps
  if [[ "$lower" == *"step"* ]] || [[ "$lower" == *"1."* ]] || \
     [[ "$lower" == *"first"* ]] || [[ "$lower" == *"then"* ]] || \
     [[ "$lower" == *"clawdbot"* ]] || [[ "$lower" == *"config"* ]] || \
     [[ "$lower" == *"command"* ]] || [[ "$lower" == *"run"* ]] || \
     [[ "$lower" == *"install"* ]] || [[ "$lower" == *"clawhub"* ]]; then
    score=$((score + 1))
  fi

  # Penalty for UI-centric guidance
  if [[ "$lower" == *"settings page"* ]] || [[ "$lower" == *"open the dashboard"* ]] || \
     [[ "$lower" == *"click on"* ]]; then
    score=$((score - 1))
  fi

  [ "$score" -ge 2 ] && return 0
  return 1
}

#===============================================================================
# Helper: Check if the test API key was written to clawdbot.json
#===============================================================================
_id_check_config_for_key() {
  local key="$1"
  local result

  case "$CLAW_MODE" in
    local)
      result=$(jq -r '.tools.web.search.apiKey // empty' ~/.clawdbot/clawdbot.json 2>/dev/null)
      ;;
    ssh)
      result=$(ssh -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" \
        "jq -r '.tools.web.search.apiKey // empty' ~/.clawdbot/clawdbot.json 2>/dev/null" 2>/dev/null)
      ;;
    *)
      echo "skip"
      return
      ;;
  esac

  if [ "$result" = "$key" ]; then
    echo "found"
  else
    echo "not_found"
  fi
}

#===============================================================================
# Helper: Remove Brave API key from config (set to placeholder)
#===============================================================================
_id_remove_brave_key() {
  case "$CLAW_MODE" in
    local)
      jq '.tools.web.search.apiKey = "__BRAVE_API_KEY__"' \
        ~/.clawdbot/clawdbot.json > /tmp/clawdbot.json.tmp && \
        mv /tmp/clawdbot.json.tmp ~/.clawdbot/clawdbot.json 2>/dev/null || true
      ;;
    ssh)
      ssh -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" \
        "jq '.tools.web.search.apiKey = \"__BRAVE_API_KEY__\"' ~/.clawdbot/clawdbot.json > /tmp/clawdbot.json.tmp && mv /tmp/clawdbot.json.tmp ~/.clawdbot/clawdbot.json" \
        2>/dev/null || true
      ;;
  esac
}

#===============================================================================
# Helper: Restart clawdbot to pick up config changes
#===============================================================================
_id_restart_clawdbot() {
  local status=""
  case "$CLAW_MODE" in
    local)
      sudo systemctl restart clawdbot 2>/dev/null || true
      rm -rf ~/.clawdbot/sessions/* ~/.clawdbot/agents/*/sessions/* 2>/dev/null || true
      # Wait for gateway to be ready (up to 30s)
      for _i in $(seq 1 15); do
        if curl -sf http://localhost:18789/ >/dev/null 2>&1; then
          status="ready"
          break
        fi
        sleep 2
      done
      ;;
    ssh)
      status=$(ssh -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" \
        "rm -rf ~/.clawdbot/sessions/* ~/.clawdbot/agents/*/sessions/* 2>/dev/null; \
         sudo systemctl restart clawdbot; \
         for i in \$(seq 1 15); do \
           if curl -sf http://localhost:18789/ >/dev/null 2>&1; then \
             echo 'ready'; exit 0; \
           fi; \
           sleep 2; \
         done; \
         echo 'timeout'" \
        2>/dev/null) || status="ssh_failed"
      ;;
  esac
  if [ "$status" != "ready" ]; then
    claw_warn "  Gateway not ready after restart (status: ${status:-unknown})"
  fi
}

#===============================================================================
# Ensure claw_ask_session is available
#===============================================================================
if ! declare -f claw_ask_session > /dev/null 2>&1; then
  claw_ask_session() {
    local session_id="$1"
    local message="$2"
    local json_result result

    case "$CLAW_MODE" in
      local)
        json_result=$(timeout "$CLAW_TIMEOUT" clawdbot agent \
          --session-id "$session_id" \
          --message "$message" \
          --json 2>/dev/null) || json_result='{"error":"timeout"}'
        ;;
      ssh)
        local encoded_message
        encoded_message=$(echo -n "$message" | base64)
        json_result=$(ssh -n -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" \
          "timeout $CLAW_TIMEOUT clawdbot agent --session-id '$session_id' --message \"\$(echo '$encoded_message' | base64 -d)\" --json 2>/dev/null" \
          2>/dev/null) || json_result='{"error":"timeout"}'
        ;;
      api)
        echo "CLAW_NOT_IMPLEMENTED"
        return
        ;;
    esac

    result=$(echo "$json_result" | jq -r '.result.payloads[0].text // .error // "CLAW_EMPTY_RESPONSE"' 2>/dev/null)
    echo "$result"
  }
fi
