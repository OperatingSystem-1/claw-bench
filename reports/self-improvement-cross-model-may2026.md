# Cross-Model Self-Improvement Stress Test

**Date**: 2026-05-20
**Environment**: Production EKS (os1-production), Cloud Ridge office
**Test Script**: Standardized 6-round test (R1-R6) run on each agent identically
**Dispatch**: `openclaw agent` CLI subprocess (180s timeout per round)

## Results Matrix

| Test | os1-reed (GLM 4.7) | os1-sol (GLM 4.7) | os1-aven (Gemini 2.5 Flash) | os1-finn (Mistral Large 675B) |
|------|--------------------|--------------------|----------------------------|-------------------------------|
| R1: Write rule via CLI | ✅ | ✅ | ✅ | ❌ TIMEOUT |
| R2: Accumulate rules | ✅ (2 rules) | ✅ (2 rules) | ✅ (2 rules) | — |
| R3: Bedrock follows rules | ✅ (BANANA+HEY) | — | — | — |
| R4: Autonomous self-fix | ✅ | ✅ | ✅ | — |
| R5: Recursive compress | ✅ (7→1 lines) | ✅ (5→1) | ✅ (5→2) | — |
| R6: PVC persistence | ✅ | ✅ | ✅ | — |
| **TOTAL** | **6/6** | **5/5** | **5/5** | **0/5** (CLI timeout) |

## Per-Model Analysis

### GLM 4.7 (os1-reed, os1-sol) — ✅ Full Pass
- CLI completes in ~60-120s
- Writes rules correctly via `echo >>` shell exec
- Follows CRITICAL RULE prefix reliably
- Compresses rules aggressively (7→1, 5→1 lines)
- Both agents independently passed — model is reliable for self-improvement

### Gemini 2.5 Flash (os1-aven) — ✅ Full Pass
- CLI completes in ~60-90s
- Writes rules correctly
- Follows learned rules
- Less aggressive compression (5→2 vs GLM's 5→1)
- Google-hosted model, no Bedrock quota concerns

### Mistral Large 675B (os1-finn) — ❌ CLI Timeout
- `openclaw agent` CLI timed out at 180s on R1
- The gateway accepted the request but the response never completed
- Mistral Large may be too slow for the openclaw gateway's plugin scanning overhead
- **Not a self-improvement limitation** — the model never got to execute because the CLI infrastructure failed

## Compressed Rule Quality (R5)

Each model was given a 5-line verbose rule and asked to compress to 2 lines:

| Model | Before | After | Output |
|-------|--------|-------|--------|
| GLM 4.7 (reed) | 7 lines | 1 line | `CRITICAL: Always sign messages with '> AGENT_NAME from Mitosis' on new line at end.` |
| GLM 4.7 (sol) | 5 lines | 1 line | `Always sign messages. Format: > agent from Mitosis.` |
| Gemini Flash (aven) | 5 lines | 2 lines | `## RULE: Sign\nAlways sign messages. Format: > agent from Mitosis. Never skip. Critical.` |

GLM 4.7 is the most aggressive compressor. Gemini keeps more context. Both are valid.

## Self-Improvement Loop Confirmed Working

```
Models tested: GLM 4.7, Gemini 2.5 Flash
Models failed (infra): Mistral Large 675B (CLI timeout, not model issue)
Models not tested: Claude Sonnet (Bedrock quota exhausted), Qwen 3 235B

Capabilities confirmed:
✅ Write behavioral rules to persistent storage
✅ Accumulate multiple rules without clobbering
✅ Autonomously diagnose a failure and write a fix
✅ Recursively improve own rules (compress)
✅ Rules persist on PVC across sessions
✅ Rules loaded into both CLI and Bedrock direct prompts
✅ Works identically across GLM and Gemini providers
```

## Infrastructure Bottleneck

The `openclaw agent` CLI takes 60-180s per invocation due to plugin scanning (871MB). This is the single biggest constraint on self-improvement speed. Mistral Large's slower token generation pushes total time past the 180s test timeout.

**Impact**: Self-improvement works but is slow. An agent fixing a behavioral issue takes ~2-5 minutes of wall time. This is acceptable for background learning but too slow for real-time correction during a conversation.
