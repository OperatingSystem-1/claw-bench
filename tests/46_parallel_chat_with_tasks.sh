#!/bin/bash
# Test: Parallel Chat with Dependent Tasks
# Verifies that an agent can maintain a chat session while tracking
# dependent background tasks via file-based context handoff.
#
# Uses ACTIVE_WORK.md and LAST_SESSION.md for cross-session context:
# - Session CHAT establishes context and assigns Task A
# - Session WORKER reads ACTIVE_WORK.md and knows about Task A
# - WORKER completes A, starts dependent Task B, writes handoff
# - CHAT resumes and picks up both updates
#
# Pass: Bidirectional context handoff works (CHAT knows A done + B running)
# Fail: Sessions cannot share task state via handoff files

# Helper: run a command on the target (local or SSH)
_claw_remote() {
  local cmd="$1"
  case "$CLAW_MODE" in
    local) eval "$cmd" ;;
    ssh) ssh -n -i "$CLAW_SSH_KEY" $CLAW_SSH_OPTS "$CLAW_HOST" "$cmd" 2>/dev/null ;;
  esac
}

test_parallel_chat_with_tasks() {
  claw_header "TEST 46: Parallel Chat with Dependent Tasks"

  local start_s end_s duration
  start_s=$(date +%s)

  local chat_session="chat-$(date +%s)-${RANDOM}"
  local worker_session="worker-$(date +%s)-${RANDOM}"
  local task_a="TaskAlpha_${RANDOM}"
  local task_b="TaskBravo_${RANDOM}"

  # Setup: Clear any stale handoff files from previous runs
  _claw_remote "rm -f ~/clawd/memory/ACTIVE_WORK.md ~/clawd/memory/LAST_SESSION.md"

  # Phase 1: CHAT session establishes context and assigns Task A
  claw_info "Phase 1: CHAT assigns $task_a"
  local chat1_resp
  chat1_resp=$(claw_ask_session "$chat_session" \
    "We're starting a new project. I need you to track task progress. Write the following to memory/ACTIVE_WORK.md (create it if needed):

# Active Work
[RUNNING] $task_a - Build the authentication module

Confirm when the file is written.")

  if claw_is_empty "$chat1_resp"; then
    end_s=$(date +%s)
    duration=$(( (end_s - start_s) * 1000 ))
    claw_critical "Empty response from CHAT session establishing context" "parallel_chat_with_tasks" "$duration"
    return
  fi

  sleep 2

  # Verify Phase 1 wrote the file; if not, seed it so we can still test the READ path
  local phase1_wrote=true
  local file_check
  file_check=$(_claw_remote "cat ~/clawd/memory/ACTIVE_WORK.md 2>/dev/null")
  if [[ "$file_check" != *"$task_a"* ]]; then
    phase1_wrote=false
    claw_warn "CHAT did not write ACTIVE_WORK.md — seeding file to test READ path"
    _claw_remote "mkdir -p ~/clawd/memory && printf '# Active Work\n[RUNNING] $task_a - Build the authentication module\n' > ~/clawd/memory/ACTIVE_WORK.md"
  else
    claw_info "CHAT wrote ACTIVE_WORK.md successfully"
  fi

  # Phase 2: WORKER session reads context and knows about Task A
  claw_info "Phase 2: WORKER checks active tasks"
  local worker1_resp
  worker1_resp=$(claw_ask_session "$worker_session" \
    "Read the file memory/ACTIVE_WORK.md and tell me: what tasks are currently in progress? List them with their status.")

  if claw_is_empty "$worker1_resp"; then
    end_s=$(date +%s)
    duration=$(( (end_s - start_s) * 1000 ))
    claw_critical "Empty response from WORKER session" "parallel_chat_with_tasks" "$duration"
    return
  fi

  # Score Phase 2: Does WORKER know about Task A?
  local worker_knows_a=false
  if [[ "$worker1_resp" == *"$task_a"* ]] || \
     [[ "$worker1_resp" == *"Alpha"* ]] || \
     [[ "$worker1_resp" == *"authentication"* ]] || \
     [[ "$worker1_resp" == *"RUNNING"* ]] || \
     [[ "$worker1_resp" == *"in progress"* ]] || \
     [[ "$worker1_resp" == *"active"* ]]; then
    worker_knows_a=true
    claw_info "WORKER found Task A context"
  else
    claw_warn "WORKER did not mention Task A (response: ${worker1_resp:0:150})"
  fi

  # Phase 3: WORKER completes Task A, starts dependent Task B
  claw_info "Phase 3: WORKER completes $task_a, starts $task_b"
  local worker2_resp
  worker2_resp=$(claw_ask_session "$worker_session" \
    "$task_a is now complete. Do these two file updates:

1. Update memory/ACTIVE_WORK.md to contain:
# Active Work
[DONE] $task_a - Build the authentication module
[RUNNING] $task_b - Integrate OAuth tokens (depends on $task_a output)

2. Write memory/LAST_SESSION.md with:
# Last Session
Completed $task_a (auth module). Started $task_b (OAuth integration, depends on $task_a).

Confirm when both files are written.")

  if claw_is_empty "$worker2_resp"; then
    end_s=$(date +%s)
    duration=$(( (end_s - start_s) * 1000 ))
    claw_critical "Empty response from WORKER completing tasks" "parallel_chat_with_tasks" "$duration"
    return
  fi

  sleep 2

  # Verify Phase 3 wrote the files
  local phase3_check
  phase3_check=$(_claw_remote "cat ~/clawd/memory/ACTIVE_WORK.md 2>/dev/null; echo '|||'; cat ~/clawd/memory/LAST_SESSION.md 2>/dev/null")

  local phase3_wrote=true
  if [[ "$phase3_check" != *"$task_b"* ]]; then
    phase3_wrote=false
    claw_warn "WORKER did not write handoff files — seeding for Phase 4"
    _claw_remote "printf '# Active Work\n[DONE] $task_a - Build the authentication module\n[RUNNING] $task_b - Integrate OAuth tokens\n' > ~/clawd/memory/ACTIVE_WORK.md"
    _claw_remote "printf '# Last Session\nCompleted $task_a (auth module). Started $task_b (OAuth integration).\n' > ~/clawd/memory/LAST_SESSION.md"
  else
    claw_info "WORKER wrote handoff files successfully"
  fi

  # Phase 4: CHAT resumes and should pick up context from handoff files
  claw_info "Phase 4: CHAT resumes, checks for updates"
  local chat2_resp
  chat2_resp=$(claw_ask_session "$chat_session" \
    "I'm back. Read memory/LAST_SESSION.md and memory/ACTIVE_WORK.md and tell me: what's the latest? What tasks completed and what's still running?")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$chat2_resp"; then
    claw_critical "Empty response from CHAT resuming" "parallel_chat_with_tasks" "$duration"
    return
  fi

  # Score Phase 4: Does CHAT know about both task updates?
  local context_hits=0

  # Check: CHAT mentions Task A
  if [[ "$chat2_resp" == *"$task_a"* ]] || [[ "$chat2_resp" == *"Alpha"* ]] || \
     [[ "$chat2_resp" == *"authentication"* ]]; then
    context_hits=$((context_hits + 1))
  fi
  # Check: CHAT knows Task A is done
  if [[ "$chat2_resp" == *"complete"* ]] || [[ "$chat2_resp" == *"DONE"* ]] || \
     [[ "$chat2_resp" == *"finished"* ]] || [[ "$chat2_resp" == *"done"* ]]; then
    context_hits=$((context_hits + 1))
  fi
  # Check: CHAT mentions Task B
  if [[ "$chat2_resp" == *"$task_b"* ]] || [[ "$chat2_resp" == *"Bravo"* ]] || \
     [[ "$chat2_resp" == *"OAuth"* ]]; then
    context_hits=$((context_hits + 1))
  fi
  # Check: CHAT knows Task B is running
  if [[ "$chat2_resp" == *"RUNNING"* ]] || [[ "$chat2_resp" == *"in progress"* ]] || \
     [[ "$chat2_resp" == *"running"* ]] || [[ "$chat2_resp" == *"active"* ]]; then
    context_hits=$((context_hits + 1))
  fi

  # Bonus scoring info
  local write_score=0
  [ "$phase1_wrote" = true ] && write_score=$((write_score + 1))
  [ "$phase3_wrote" = true ] && write_score=$((write_score + 1))

  # Final scoring — focus on Phase 4 read-back (the core handoff test)
  if [ "$context_hits" -ge 3 ]; then
    if [ "$worker_knows_a" = true ] && [ "$write_score" -eq 2 ]; then
      claw_pass "Parallel chat excellent: full bidirectional handoff, agents wrote+read files (${context_hits}/4 hits, ${write_score}/2 writes)" "parallel_chat_with_tasks" "$duration"
    else
      claw_pass "Parallel chat working: CHAT read ${context_hits}/4 context hits (writes: ${write_score}/2, worker_read: $worker_knows_a)" "parallel_chat_with_tasks" "$duration"
    fi
  elif [ "$context_hits" -ge 2 ]; then
    claw_pass "Parallel chat basic: CHAT got ${context_hits}/4 context hits (writes: ${write_score}/2)" "parallel_chat_with_tasks" "$duration"
  elif [ "$context_hits" -ge 1 ]; then
    claw_warn "Partial handoff: CHAT only got ${context_hits}/4 context hits"
    claw_fail "Parallel chat weak: insufficient context handoff (${context_hits}/4)" "parallel_chat_with_tasks" "$duration"
  else
    claw_fail "Parallel chat failed: CHAT has no awareness of task updates (0/4 hits)" "parallel_chat_with_tasks" "$duration"
  fi
}

# Helper function for multi-turn with shared session
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
