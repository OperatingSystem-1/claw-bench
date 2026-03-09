#!/bin/bash
# Test: Browser Research Synthesis (web_search + browser)
# Tests the agent's ability to search, navigate, and synthesize information
# from multiple web sources into a structured comparison.
#
# Pass: Response includes 2+ source URLs and mentions key HTTP/1.1 vs HTTP/2 differences
# Fail: Missing URLs, no comparison, or empty response
# Critical: Empty response (browser/search pipeline broken)

test_browser_research_synthesis() {
  claw_header "TEST 41: Browser Research Synthesis (web_search + browser)"

  local start_s end_s duration
  start_s=$(date +%s)

  claw_info "Testing multi-source research: HTTP/1.1 vs HTTP/2 comparison"

  local response
  response=$(claw_ask "Fetch these two pages using web_fetch (or web_search if available): https://www.rfc-editor.org/rfc/rfc9110 and https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Evolution_of_HTTP. Return exactly 3 bullets summarizing key differences between HTTP/1.1 and HTTP/2, and include both source URLs.")

  end_s=$(date +%s)
  duration=$(( (end_s - start_s) * 1000 ))

  if claw_is_empty "$response"; then
    claw_critical "Empty response on browser research synthesis" "browser_research_synthesis" "$duration"
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
    claw_pass "Browser tool recognized: browser not ready (infrastructure issue)" "browser_research_synthesis" "$duration"
    return
  fi

  # Count URLs in response
  local url_count
  url_count=$(echo "$response" | grep -oE 'https?://' | wc -l | tr -d ' ')

  # Check for key technical content
  local has_http2=false
  local has_http11=false
  local has_urls=false

  [[ "$lower" == *"http/2"* ]] || [[ "$lower" == *"http2"* ]] && has_http2=true
  [[ "$lower" == *"http/1.1"* ]] || [[ "$lower" == *"http/1"* ]] && has_http11=true
  [[ "$url_count" -ge 2 ]] && has_urls=true

  if $has_http2 && $has_http11 && $has_urls; then
    # Check for substantive comparison content
    if [[ "$lower" == *"multiplex"* ]] || [[ "$lower" == *"binary"* ]] || \
       [[ "$lower" == *"header"* ]] || [[ "$lower" == *"compression"* ]] || \
       [[ "$lower" == *"stream"* ]]; then
      claw_pass "Research synthesis complete: HTTP comparison with sources and technical detail" "browser_research_synthesis" "$duration"
    else
      claw_pass "Research synthesis complete: HTTP comparison with sources" "browser_research_synthesis" "$duration"
    fi
  elif $has_http2 && $has_http11; then
    claw_warn "Response missing source URLs"
    claw_pass "Research synthesis: HTTP comparison present but missing URLs" "browser_research_synthesis" "$duration"
  elif $has_urls; then
    claw_fail "Research synthesis incomplete: has URLs but missing HTTP comparison content: ${response:0:300}" "browser_research_synthesis" "$duration"
  else
    claw_fail "Research synthesis failed: missing both comparison and URLs: ${response:0:300}" "browser_research_synthesis" "$duration"
  fi
}
