#!/bin/bash
# Stop hook: Nudge verification when code was written and completion is claimed.
#
# Design principles (learned from clawgo false-positive analysis):
#   - Only trigger when the agent WROTE code (Edit/Write tools used)
#   - Only trigger on strong completion claims in the last 5 lines (not 50)
#   - Only check that tests were RUN — don't demand specific test types
#   - Conversational answers, brainstorming, and Q&A should never trigger
#   - Brainstorming sessions get a soft reminder about plan clarity
#   - Never hard-block — always a suggestion the agent can address or dismiss

read -r INPUT

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Prevent infinite loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# No transcript → allow
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# --- Did the agent actually write code this session? ---
# Look for Edit or Write tool calls (the only tools that modify files)
CODE_WRITTEN=$(grep -cE '"name":"(Edit|Write)"' "$TRANSCRIPT" 2>/dev/null)

if [ "$CODE_WRITTEN" -eq 0 ] 2>/dev/null; then
  # No code was written. Check if this was a brainstorming session.
  # Look for brainstorming/design patterns in recent output
  BRAINSTORM_SIGNAL=$(tail -20 "$TRANSCRIPT" | grep -iE '(brainstorm|design|plan|proposal|approach|architecture|trade-?off)' | head -1)

  if [ -n "$BRAINSTORM_SIGNAL" ]; then
    # Brainstorming session — soft reminder about plan clarity
    PLAN_PRESENTED=$(tail -30 "$TRANSCRIPT" | grep -iE '(summary|next steps|key decisions|to summarize|in summary|the plan is|here.s what)')
    USER_ACK=$(tail -30 "$TRANSCRIPT" | grep -iE '"role":"user"' | grep -iE '(looks good|approved|makes sense|sounds good|go ahead|yes|LGTM|agreed|perfect|implement|ship|confirm)')

    MISSING=""
    [ -z "$PLAN_PRESENTED" ] && MISSING="${MISSING}\n- No plan summary presented"
    [ -z "$USER_ACK" ] && MISSING="${MISSING}\n- No user acknowledgment of the plan"

    if [ -n "$MISSING" ]; then
      cat >&2 << EOF
[BRAINSTORM CHECK] Consider before ending:${MISSING}
Tip: Summarize the plan and confirm the user is aligned.
EOF
    fi
  fi

  # No code written → never block, regardless of what words were used
  exit 0
fi

# --- Code was written. Check for completion claims. ---
# Only look at the LAST 5 lines to avoid catching mid-conversation words
LAST_LINES=$(tail -5 "$TRANSCRIPT" | grep '"type":"text"')
COMPLETION_CLAIM=$(echo "$LAST_LINES" | grep -iE '(work is (complete|done|finished)|all (done|set|complete)|implementation is (complete|done|finished)|changes are (complete|done))')

# No completion claim → allow (agent is mid-conversation or asking a question)
if [ -z "$COMPLETION_CLAIM" ]; then
  exit 0
fi

# --- Completion claimed after writing code. Were tests run? ---
TEST_RAN=$(grep -iE '(npm test|vitest|jest|pytest|go test|cargo test|playwright|test.*pass|PASS|tests? passed|test suite)' "$TRANSCRIPT" 2>/dev/null | tail -1)

if [ -n "$TEST_RAN" ]; then
  # Tests were run — allow
  exit 0
fi

# Tests not run — remind (not block)
cat << EOF
{
  "decision": "block",
  "reason": "You wrote code and claimed completion, but there's no evidence tests were run. Run the project's tests before wrapping up."
}
EOF
exit 2
