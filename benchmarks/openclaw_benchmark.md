# OpenClaw Capability Benchmark Suite

Goal: measure **speed + reliability** for complex, human-like tasks (research, form fill, multi-step workflows). This suite complements `benchmarks/browser_benchmark.md` and is designed to reveal bottlenecks in model routing, tool choice, and browser automation.

## How to run

From a VM with OpenClaw installed:

```bash
bash benchmarks/run_openclaw_benchmark.sh
```

The runner prints per-test wall time, tool counts, and (if available) the gateway `durationMs` from `/tmp/clawdbot/clawdbot-YYYY-MM-DD.log`.

## Tests

### Test 1 — Research + Synthesis (web_search + web_fetch)

**Goal:** reduce round trips by using search + fetch instead of browser.

**Prompt (runner uses this):**
- Search for "RFC 9110 HTTP semantics".
- Open the official RFC page and a second authoritative source.
- Return 3 bullets summarizing key differences between HTTP/1.1 and HTTP/2.
- Include source URLs.

**Pass criteria (manual):**
- Output includes at least 2 source URLs.
- Mentions at least 2 real differences (e.g., multiplexing, header compression).

**Target:** <18s wall clock, ≤4 tool calls.

### Test 2 — Form Fill (browser interaction)

**Goal:** measure interactive browser performance and reliability.

**Prompt:**
- Navigate to `https://www.selenium.dev/selenium/web/web-form.html`.
- Fill the form with realistic values.
- Submit, then report the confirmation text shown after submission.

**Pass criteria (automated-ish):**
- Response includes the word "Received".

**Target:** <25s wall clock, ≤6 tool calls.

### Test 3 — Multi-Step Workflow (search → compare → summarize)

**Goal:** measure a realistic multi-step task and encourage batching.

**Prompt:**
- Use `web_search` for "PostgreSQL btree vs hash index".
- Open 2 sources and produce a concise comparison table (3 rows max).
- End with a one-sentence recommendation for a general web app.

**Pass criteria (manual):**
- Includes a table or clearly structured comparison.
- Gives a recommendation.

**Target:** <22s wall clock, ≤5 tool calls.

## Metrics captured

- Wall time (start → end of `clawdbot agent` command)
- Gateway run duration (`durationMs` when available)
- Total tool calls and breakdown per tool (browser/web_search/web_fetch)

## What to optimize if slow

- Too many tool calls → update CLAUDE/TOOLS to encourage batching.
- High model latency → reduce prompt size, avoid Opus unless needed.
- Slow page loads → block ads/images, prefer web_fetch, headless browser.
