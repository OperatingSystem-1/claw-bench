# Browser Speed Benchmark

Benchmark for measuring agent browser task performance on OS-1 VMs. Run this after changing KasmVNC config, model routing, or browser tool settings to validate improvements.

## Prerequisites

- SSH access to a running VM: `ssh -i ~/.ssh/my-gcp-key ubuntu@<IP>`
- Clawdbot gateway running: `sudo systemctl status clawdbot-gateway.service`
- Browser CDP started: `curl -s http://127.0.0.1:18791/ | python3 -m json.tool` (check `cdpReady: true`)

If the browser isn't running, start it manually:

```bash
curl -s -X POST http://127.0.0.1:18791/start -H "Content-Type: application/json" -d '{"profile":"clawd"}' --max-time 30
```

## Test Suite

### Test A: Simple Page Read

Single navigation + extract info. Measures baseline round-trip: model API call + one browser navigate + one snapshot.

```bash
source ~/.nvm/nvm.sh
echo "Start: $(date +%H:%M:%S)"
START=$(date +%s)

clawdbot agent --session-id bench-simple-$(date +%s) --timeout 60 \
  -m "Use your browser tool to navigate to https://news.ycombinator.com and tell me the title of the #1 story."

END=$(date +%s)
echo "=== TEST A (simple page read): $((END - START))s ==="
```

**Target:** <15s

### Test B: Multi-Step Search

Search + navigate + read. Measures web_search → browser navigate → snapshot pipeline.

```bash
source ~/.nvm/nvm.sh
echo "Start: $(date +%H:%M:%S)"
START=$(date +%s)

clawdbot agent --session-id bench-multistep-$(date +%s) --timeout 120 \
  -m "1) Use web_search for 'anthropic model system cards' 2) Navigate to the anthropic.com result with the browser 3) Snapshot and tell me the first paragraph. Be concise — 1-2 sentences max."

END=$(date +%s)
echo "=== TEST B (multi-step search): $((END - START))s ==="
```

**Target:** <20s

### Test C: Model Identity Check

Confirms which model is active and measures raw API latency with no tool calls.

```bash
source ~/.nvm/nvm.sh
START=$(date +%s)

clawdbot agent --session-id bench-model-$(date +%s) --timeout 30 \
  -m "What model are you? Just state your model name, nothing else."

END=$(date +%s)
echo "=== TEST C (model check): $((END - START))s ==="
```

**Target:** <6s (Sonnet), <10s (Opus)

## Analyzing Tool Call Timings

After running tests, extract per-call timings from the gateway log:

```bash
# Get the latest run ID
LATEST_RUN=$(grep 'embedded run done' /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log | tail -1 | grep -oP 'runId=\K[a-f0-9-]+')

# Print all tool calls with timestamps
grep "$LATEST_RUN" /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log | grep -E 'tool (start|end)' | while read -r line; do
  TIME=$(echo "$line" | grep -oP '"time":"\K[^"]+')
  TOOL=$(echo "$line" | grep -oP 'tool=\K\w+')
  TYPE=$(echo "$line" | grep -oP 'tool (start|end)' | awk '{print $2}')
  echo "$TIME  $TYPE  $TOOL"
done

# Total run duration
grep "$LATEST_RUN" /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log | grep 'embedded run done' | grep -oP 'durationMs=\K\d+'
```

### What to look for

- **Browser tool calls** should be <2s each (navigate/click/type). Page loads may take 2-8s.
- **Gap between tool calls** = model API latency. Sonnet ~2-3s, Opus ~4-5s per turn.
- If `tool=web_fetch` appears instead of `tool=browser`, the CDP browser isn't connected.

## Checking System State

Run before and after config changes to compare:

```bash
echo "=== Display Resolution ==="
DISPLAY=:1 xdpyinfo | grep dimensions

echo "=== KasmVNC Encoding Params ==="
ps aux | grep '[X]vnc' | head -1 | grep -oP '(FrameRate|DynamicQualityMin|DynamicQualityMax|RectThreads|MaxVideoResolution|Geometry) \S+' | tr ' ' '='

echo "=== Active Model ==="
grep 'agent model' /tmp/clawdbot.log | tail -1

echo "=== Browser Status ==="
curl -s http://127.0.0.1:18791/ | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'running={d[\"running\"]} cdpReady={d[\"cdpReady\"]} pid={d[\"pid\"]}')"

echo "=== CPU / Memory ==="
ps aux --sort=-%cpu | head -6
free -h | head -3
```

## Results (2026-02-21)

Configuration: t3.large (2 vCPU, 8GB), KasmVNC 1.3.3, Clawdbot 2026.1.24-3

### Round 1 — CDP + Sonnet (baseline)

| Test | Opus + no CDP | Opus + CDP | Sonnet + CDP |
|------|--------------|-----------|-------------|
| A: Simple page read | 31s | 15s | **10s** |
| B: Multi-step search | N/A (xdotool) | 47s | **43s** |
| C: Model check | ~8-10s | ~8-10s | **5.8s** |

### Round 2 — + Ad blocking, images disabled, trimmed prompt

| Test | Round 1 | Round 2 | Improvement |
|------|---------|---------|-------------|
| A: Simple page read | 10s | **10s** | — |
| B: Multi-step search | 43s | **31s** | **28% faster** |
| C: Model check | 5.8s | **5.2s** | 10% faster |

**Test B breakdown (Round 2):**

| Metric | Round 1 | Round 2 |
|--------|---------|---------|
| Browser tool calls | 7-8 @ 18s total | 7 @ 4.8s total |
| Model API latency | ~3.1s/call | ~2.2s/call |
| Agent run time | 40.2s | 28.2s |

### Optimization changelog

| Round | Changes |
|-------|---------|
| 1 | KasmVNC 720p/24fps, CDP browser tool, Sonnet default, context pruning 30m |
| 2 | Ad/tracker blocking (38 domains via /etc/hosts), Chromium images disabled (policy), CLAUDE.md trimmed 85→34 lines, batch action instructions |

### Config at time of Round 2

| Setting | Value |
|---------|-------|
| Resolution | 1280x720 |
| Frame rate | 24 fps |
| Quality | 5-7 |
| Compress threads | 2 |
| Default model | anthropic/claude-sonnet-4-6 |
| Browser | CDP (headless=false, images disabled, ads blocked) |
| Context pruning | cache-ttl, 30m |
| CLAUDE.md | 34 lines (trimmed) |
| Blocked domains | 38 (ads/trackers via /etc/hosts) |

### Round 3 — Token reduction + tool pruning

| Change | Before | After | Token Impact |
|--------|--------|-------|--------------|
| Tool definitions | 23 tools (~16K tokens/call) | 8 tools (~5.6K tokens/call) | **-10K tokens/call** |
| CLAUDE.md | 100+ lines (~2.5K tokens) | 13 lines (~300 tokens) | **-2.2K tokens/call** |
| Workspace deploy | 6 files (AGENTS 5KB, BRIEFING 8KB) | 4 files (no AGENTS/BRIEFING) | **-13KB first-turn** |
| Startup file reads | 4 mandatory reads on session start | 0 (read on demand only) | **-2 API round trips** |
| Sonnet maxTokens | 8192 | 4096 | Shorter responses |
| Chromium flags | none | 9 performance flags | Faster page loads |

### Round 4 — Headless mode + maxTokens reduction

**Changes applied:**

| Change | Before | After | Impact |
|--------|--------|-------|--------|
| Browser mode | headless=false (visible in KasmVNC) | **headless=true** | Eliminates GPU process, X11 rendering, ~200MB RAM saved |
| Sonnet maxTokens | 4096 | **2048** | Shorter responses, less output token generation |
| --disable-gpu flag | not set | **set** | No GPU process spawned |
| enableNoVnc | true | **false** | No VNC overhead for browser window |

**Experiment: `mode=efficient` (interactive-only snapshots)**

Tested `snapshotDefaults.mode=efficient` which filters snapshots to interactive elements only:

| Mode | Google.com size | Anthropic.com size | Can read content? |
|------|----------------|-------------------|-------------------|
| Full AI snapshot | 3,507 chars | 16,033 chars | Yes |
| Compact (no interactive) | ~3,200 chars | 13,696 chars | Yes |
| Efficient (interactive only) | 652 chars | 2,897 chars | **No** |

**Result: mode=efficient is TOO aggressive.** It strips ALL text content (headings, paragraphs), forcing the agent to use extra `web_fetch` calls to read page content. Test B went from 28s → 68s with efficient mode enabled. **Reverted.**

**Results (headless + maxTokens=2048, no efficient mode):**

| Test | Round 2 | Round 4 | Notes |
|------|---------|---------|-------|
| A: Simple page read | 10s | **11s** | Same (model API latency variance) |
| B: Multi-step search | 31s | **39-42s** | Slower — page load variance, not config |
| C: Model check | 5.2s | **5s** | Same |

**Test B breakdown (Round 4, run 3 = 39s):**

| Metric | Round 2 | Round 4 |
|--------|---------|---------|
| Browser tool calls | 7 @ 4.8s | 7 @ 12.9s |
| Model API latency | ~2.2s/call | ~2.4s/call |
| Agent run time | 28.2s | 35.1s |

The slowdown is entirely from **page load variance** (Google SERP took 8s in this run vs ~1s in Round 2). Browser tool call count is identical.

### Bottleneck Analysis

Where time goes in a 7-step browser task (Test B):

| Component | Time | % | Can we reduce? |
|-----------|------|---|---------------|
| Model reasoning (7 turns) | ~17s | 44% | Reduce tool calls, smaller context |
| Page loads (navigate/click) | ~13s | 33% | Mostly network-bound, limited control |
| Final response generation | ~5s | 13% | Lower maxTokens, terser prompts |
| Model initial planning | ~4s | 10% | Minimal overhead |

**Key finding: The bottleneck is round trips, not snapshot size.** Each model reasoning turn adds ~2.5s regardless of snapshot size. Reducing 7 tool calls to 3 saved ~10s.

### Round 5 — web_search + browser (search + navigate + read)

**Changes applied:**

| Change | Before | After | Impact |
|--------|--------|-------|--------|
| Search method | Browser → Google → type → snapshot → click | **web_search** (Brave API, instant) | Eliminates 4 browser tool calls |
| TOOLS.md | "browser for all web tasks" | **"web_search for searching, browser for interaction"** | Agent uses right tool for job |
| Brave Search API | Not configured | **Configured** | Enables web_search tool |

**Results:**

| Test | Round 2 (baseline) | Round 5 | Improvement |
|------|-------------------|---------|-------------|
| A: Simple page read | 10s | **8s** | 20% faster |
| B: Multi-step search | 31s | **16-18s** | **45% faster** |
| C: Model check | 5.2s | **5s** | — |

**Test B breakdown (Round 5, 3-run average = 17s):**

| Metric | Round 2 | Round 5 |
|--------|---------|---------|
| Tool calls | 7 (all browser) | **3** (1 web_search + 2 browser) |
| Browser tool time | 4.8s | **2.5s** |
| Model reasoning turns | 7 × 2.2s = 15.4s | **3 × 2.5s = 7.5s** |
| Internal run time | 28.2s | **12.4-14.0s** |
| Wall clock | 31s | **16-18s** |

### Remaining optimization opportunities

| Optimization | Est. savings | Difficulty |
|-------------|-------------|-----------|
| Navigate auto-returns snapshot (eliminates separate snapshot call) | **~2.5s** | Clawdbot feature |
| Use Haiku for simple browser steps (faster inference) | **~1-2s** | Model routing |
| Batch multiple browser actions in one tool call | **~2.5s** | Clawdbot feature |

### Optimization changelog (updated)

| Round | Changes |
|-------|---------|
| 1 | KasmVNC 720p/24fps, CDP browser tool, Sonnet default, context pruning 30m |
| 2 | Ad/tracker blocking (38 domains via /etc/hosts), Chromium images disabled (policy), CLAUDE.md trimmed 85→34 lines, batch action instructions |
| 3 | Tool list 23→8 (-65%), CLAUDE.md 100→13 lines (-87%), removed AGENTS.md/BRIEFING.md deploy, removed mandatory startup file reads, Sonnet maxTokens 8192→4096, 9 Chromium performance flags |
| 4 | Headless mode (headless=true, --disable-gpu), Sonnet maxTokens 4096→2048, enableNoVnc=false. Tested and reverted mode=efficient (too aggressive) |
| 5 | Brave Search API configured, TOOLS.md updated to prefer web_search over Google navigation, updated Test B prompt. **Test B: 31s → 17s (45% faster)** |

### Config at time of Round 5

| Setting | Value |
|---------|-------|
| Default model | anthropic/claude-sonnet-4-6 |
| Sonnet maxTokens | 2048 |
| Browser | CDP (headless=true, --disable-gpu, images disabled, ads blocked) |
| Snapshot mode | Default AI (accessibility tree, full content) |
| Web search | Brave Search API (enabled, 10 results, 30s timeout) |
| Context pruning | cache-ttl, 30m |
| Allowed tools | 8 (browser, exec, read, write, edit, web_search, web_fetch, memory_search) |
| Blocked domains | 50 (ads/trackers via /etc/hosts) |
| KasmVNC | Still running for non-browser desktop tasks |
