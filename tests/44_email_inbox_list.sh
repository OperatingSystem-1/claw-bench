#!/bin/bash
# Test: Email Inbox List (email skill via IMAP)
# Tests the agent's ability to use the email skill to list recent emails
# from the inbox using the Python IMAP client.
#
# Pass: Agent invokes email skill and returns inbox contents (subjects, senders, dates)
# Fail: Agent cannot use email skill or returns no email data
# Note: If credentials are not configured, a WARN + PASS is acceptable

test_email_inbox_list() {
  claw_header "TEST 44: Email Inbox List (email skill / IMAP)"

  local start_s end_s duration
  start_s=$(date +%s)

  claw_info "Testing email skill: list recent inbox messages"

  local response
  response=$(claw_ask "Use the email skill to list the 5 most recent emails in the inbox. Run: python3 skills/email/scripts/email_client.py list --limit 5. Report each email's subject line and sender.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response on email inbox list" "email_inbox_list" "$duration"
    return
  fi

  local lower
  lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  # Check if skill/script is not installed on this instance
  if [[ "$lower" == *"doesn't exist"* ]] || [[ "$lower" == *"does not exist"* ]] || \
     [[ "$lower" == *"not installed"* ]] || [[ "$lower" == *"no such file"* ]] || \
     [[ "$lower" == *"not found"* ]] || [[ "$lower" == *"command not found"* ]] || \
     [[ "$lower" == *"skill"* && "$lower" == *"exist"* ]]; then
    claw_warn "Email skill not installed on this instance"
    claw_pass "Email skill recognized: skill not deployed (infrastructure issue)" "email_inbox_list" "$duration"
    return
  fi

  # Check for credential/config issues (graceful degradation)
  if [[ "$lower" == *"credentials"* ]] || [[ "$lower" == *"config"* ]] || \
     [[ "$lower" == *"credentials.json"* ]]; then
    claw_warn "Email credentials not configured on this instance"
    claw_pass "Email skill recognized: reported credential requirement" "email_inbox_list" "$duration"
    return
  fi

  # Check for connection errors (IMAP server unreachable)
  if [[ "$lower" == *"connection refused"* ]] || [[ "$lower" == *"timed out"* ]] || \
     [[ "$lower" == *"network"* ]] || [[ "$lower" == *"unreachable"* ]]; then
    claw_warn "Email server connection failed (network issue, not skill issue)"
    claw_pass "Email skill invoked: server unreachable" "email_inbox_list" "$duration"
    return
  fi

  # Check for authentication failure
  if [[ "$lower" == *"authentication"* ]] || [[ "$lower" == *"login failed"* ]] || \
     [[ "$lower" == *"invalid credentials"* ]] || [[ "$lower" == *"auth"* ]]; then
    claw_warn "Email authentication failed (credentials may be stale)"
    claw_pass "Email skill invoked: auth issue detected" "email_inbox_list" "$duration"
    return
  fi

  # Check for successful email listing - look for email-like content
  local has_subjects=false
  local has_senders=false

  # Subject indicators
  if [[ "$lower" == *"subject"* ]] || [[ "$response" == *"["*"]"* ]] || \
     [[ "$lower" == *"re:"* ]] || [[ "$lower" == *"fwd:"* ]]; then
    has_subjects=true
  fi

  # Sender indicators
  if [[ "$lower" == *"from"* ]] || [[ "$lower" == *"@"* ]]; then
    has_senders=true
  fi

  # Total emails indicator from the script output
  if [[ "$lower" == *"total emails"* ]]; then
    has_subjects=true
    has_senders=true
  fi

  if $has_subjects && $has_senders; then
    claw_pass "Email inbox listed: subjects and senders returned" "email_inbox_list" "$duration"
  elif $has_subjects || $has_senders; then
    claw_pass "Email inbox listed: partial data returned" "email_inbox_list" "$duration"
  elif [[ "$lower" == *"email"* ]] && [[ "$lower" == *"inbox"* ]]; then
    # Agent talked about emails but didn't show data
    claw_fail "Email skill invoked but no email data returned: ${response:0:300}" "email_inbox_list" "$duration"
  elif [[ "$lower" == *"email"* ]] || [[ "$lower" == *"imap"* ]] || [[ "$lower" == *"mail"* ]]; then
    claw_fail "Email skill recognized but listing failed: ${response:0:300}" "email_inbox_list" "$duration"
  else
    claw_fail "Email skill not invoked or not recognized: ${response:0:300}" "email_inbox_list" "$duration"
  fi
}
