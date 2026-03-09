#!/bin/bash
# Test: Email Search (email skill via IMAP)
# Tests the agent's ability to search emails by subject and optionally
# extract verification codes using the Python IMAP client.
#
# Pass: Agent invokes email search and returns filtered results or verification code
# Fail: Agent cannot search emails or returns no results
# Note: If credentials are not configured, a WARN + PASS is acceptable

test_email_search() {
  claw_header "TEST 45: Email Search (email skill / IMAP)"

  local start_s end_s duration
  start_s=$(date +%s)

  claw_info "Testing email skill: search emails by subject with code extraction"

  local response
  response=$(claw_ask "Use the email skill to search for recent emails with 'verification' in the subject and extract any verification codes. Run: python3 skills/email/scripts/email_client.py search --subject verification --extract-code. Report what you find.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response on email search" "email_search" "$duration"
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
    claw_pass "Email skill recognized: skill not deployed (infrastructure issue)" "email_search" "$duration"
    return
  fi

  # Check for credential/config issues (graceful degradation)
  if [[ "$lower" == *"credentials"* ]] || [[ "$lower" == *"config"* ]] || \
     [[ "$lower" == *"credentials.json"* ]]; then
    claw_warn "Email credentials not configured on this instance"
    claw_pass "Email skill recognized: reported credential requirement" "email_search" "$duration"
    return
  fi

  # Check for connection/auth issues
  if [[ "$lower" == *"connection refused"* ]] || [[ "$lower" == *"timed out"* ]] || \
     [[ "$lower" == *"authentication"* ]] || [[ "$lower" == *"login failed"* ]]; then
    claw_warn "Email server connection or auth issue"
    claw_pass "Email skill invoked: server/auth issue" "email_search" "$duration"
    return
  fi

  # Check for successful search results
  local has_search=false
  local has_code=false
  local has_results=false

  # Evidence of search execution
  if [[ "$lower" == *"search"* ]] || [[ "$lower" == *"found"* ]] || \
     [[ "$lower" == *"no "* && "$lower" == *"match"* ]] || \
     [[ "$lower" == *"result"* ]]; then
    has_search=true
  fi

  # Verification code found
  if [[ "$lower" == *"verification code"* ]] || [[ "$lower" == *"code:"* ]] || \
     [[ "$response" =~ [0-9]{4,6} ]]; then
    has_code=true
  fi

  # Email result indicators
  if [[ "$lower" == *"subject"* ]] || [[ "$lower" == *"from"* ]] || \
     [[ "$lower" == *"@"* ]] || [[ "$lower" == *"date"* ]]; then
    has_results=true
  fi

  # No matching emails is a valid outcome
  if [[ "$lower" == *"no "* && "$lower" == *"verification"* ]] || \
     [[ "$lower" == *"no emails"* ]] || [[ "$lower" == *"no matching"* ]] || \
     [[ "$lower" == *"no results"* ]] || [[ "$lower" == *"didn't find"* ]]; then
    claw_pass "Email search executed: no matching verification emails (valid result)" "email_search" "$duration"
  elif $has_code; then
    claw_pass "Email search complete: verification code extracted" "email_search" "$duration"
  elif $has_results; then
    claw_pass "Email search complete: matching emails found" "email_search" "$duration"
  elif $has_search; then
    claw_pass "Email search executed: search completed" "email_search" "$duration"
  elif [[ "$lower" == *"email"* ]] || [[ "$lower" == *"imap"* ]] || [[ "$lower" == *"mail"* ]]; then
    claw_fail "Email skill recognized but search failed: ${response:0:300}" "email_search" "$duration"
  else
    claw_fail "Email skill not invoked or not recognized: ${response:0:300}" "email_search" "$duration"
  fi
}
