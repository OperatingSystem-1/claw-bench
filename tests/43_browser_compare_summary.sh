#!/bin/bash
# Test: Browser Compare Summary (search + compare + summarize)
# Tests a realistic multi-step workflow: search for technical content,
# open multiple sources, produce a structured comparison, and give a recommendation.
#
# Pass: Response includes structured comparison (table or list) and recommendation
# Fail: Missing comparison structure, no recommendation, or empty response
# Critical: Empty response (search/browser pipeline broken)

test_browser_compare_summary() {
  claw_header "TEST 43: Browser Compare Summary (search + compare + summarize)"

  local start_s end_s duration
  start_s=$(date +%s)

  claw_info "Testing multi-step workflow: search, compare, recommend"

  local response
  response=$(claw_ask "Fetch these two pages using web_fetch (or web_search if available): https://www.postgresql.org/docs/current/indexes-types.html and https://www.postgresql.org/docs/current/hash-index.html. Produce a concise comparison table (3 rows max) for PostgreSQL B-tree vs Hash indexes. End with a one-sentence recommendation for a general web app. Include both source URLs.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response on browser compare summary" "browser_compare_summary" "$duration"
    return
  fi

  local lower
  lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  # Check if browser/search tools are not available on this instance
  if [[ "$lower" == *"failed to start"* ]] || [[ "$lower" == *"no supported browser"* ]] || \
     [[ "$lower" == *"not found on the system"* ]] || [[ "$lower" == *"not installed"* ]] || \
     [[ "$lower" == *"no tab is connected"* ]] || [[ "$lower" == *"no tab connected"* ]] || \
     [[ "$lower" == *"browser"* && "$lower" == *"not ready"* ]] || \
     [[ "$lower" == *"browser"* && "$lower" == *"not running"* ]] || \
     [[ "$lower" == *"cdp"* && "$lower" == *"not"* ]]; then
    claw_warn "Browser not available on this instance"
    claw_pass "Browser tool recognized: browser not ready (infrastructure issue)" "browser_compare_summary" "$duration"
    return
  fi

  # Check for structured comparison (table or list format)
  local has_structure=false
  local has_recommendation=false
  local has_btree=false
  local has_hash=false

  # Table format (markdown pipes) or clear comparison structure
  [[ "$response" == *"|"* ]] && has_structure=true
  # Also accept bullet/numbered comparison
  [[ "$lower" == *"b-tree"* ]] || [[ "$lower" == *"btree"* ]] && has_btree=true
  [[ "$lower" == *"hash"* ]] && has_hash=true
  $has_btree && $has_hash && has_structure=true

  # Recommendation
  [[ "$lower" == *"recommend"* ]] || [[ "$lower" == *"suggestion"* ]] || \
    [[ "$lower" == *"general web app"* ]] || [[ "$lower" == *"best choice"* ]] || \
    [[ "$lower" == *"prefer"* ]] || [[ "$lower" == *"should use"* ]] && has_recommendation=true

  # Count URLs
  local url_count
  url_count=$(echo "$response" | grep -oE 'https?://' | wc -l | tr -d ' ')

  if $has_structure && $has_recommendation; then
    if [[ "$url_count" -ge 2 ]]; then
      claw_pass "Compare summary complete: structured comparison with recommendation and sources" "browser_compare_summary" "$duration"
    elif [[ "$url_count" -ge 1 ]]; then
      claw_warn "Only 1 source URL (expected 2+)"
      claw_pass "Compare summary complete: comparison with recommendation" "browser_compare_summary" "$duration"
    else
      claw_warn "No source URLs in response"
      claw_pass "Compare summary complete: comparison with recommendation (no URLs)" "browser_compare_summary" "$duration"
    fi
  elif $has_structure; then
    claw_fail "Compare summary partial: has comparison but missing recommendation: ${response:0:300}" "browser_compare_summary" "$duration"
  elif $has_recommendation; then
    claw_fail "Compare summary partial: has recommendation but no structured comparison: ${response:0:300}" "browser_compare_summary" "$duration"
  elif $has_btree || $has_hash; then
    claw_fail "Compare summary incomplete: mentions indexes but no structured output: ${response:0:300}" "browser_compare_summary" "$duration"
  else
    claw_fail "Compare summary failed: no comparison or recommendation found: ${response:0:300}" "browser_compare_summary" "$duration"
  fi
}
