# Local Self-Improvement E2E Test

**Date**: 2026-05-20
**Environment**: Local Colima k3s, office-test-bench namespace
**Agent**: test-reed-0 (5/5 Running)
**Model**: GLM 4.7 (amazon-bedrock/zai.glm-4.7)
**Dispatch**: `openclaw agent` CLI (embedded fallback, 90s timeout)

## Results

| Test | Result | Notes |
|------|--------|-------|
| R1: Write rule via CLI | ✅ | BANANA rule appended + merged |
| R2: Accumulate rules | ✅ | 2 rules, no clobbering |
| R3: Rules followed in new session | ✅ | Both BANANA + HEY present |
| R4: Autonomous self-fix | ✅ | Timezone fix rule written |
| R5: Recursive compress | ✅ | 4→3 lines (verbose→concise) |
| R6: PVC persistence | ✅ | File on PVC, survives restarts |
| **TOTAL** | **6/6** | |

## Key Fix: `merge-learned-rules`

The original self-improvement pipeline had a **critical gap**: agents write rules to `CLAUDE-LEARNED.md`, but the openclaw gateway only reads `CLAUDE.md`. Non-Claude models (GLM, Gemini) running through the embedded agent fallback don't auto-load `.claude/` directory files as project context.

### Before (broken)
1. Agent writes rule to `~/.openclaw/.claude/CLAUDE-LEARNED.md`
2. Gateway starts new session, loads `~/.openclaw/.claude/CLAUDE.md`
3. **CLAUDE-LEARNED.md is NOT loaded** → rules have no effect

### After (fixed)
1. Agent writes rule to `~/.openclaw/.claude/CLAUDE-LEARNED.md`
2. Agent runs `merge-learned-rules`
3. Script **prepends** rules to both CLAUDE.md copies:
   - `~/.openclaw/.claude/CLAUDE.md` (gateway project context)
   - `~/.openclaw/workspace/CLAUDE.md` (workspace file for tool-call reads)
4. Next gateway session sees learned rules at the top of CLAUDE.md

### Boot-time merge
The entrypoint (`entrypoint.sh`) also runs the merge at pod startup, so rules from previous sessions are always active after a restart.

### Why prepend (not append)?
With a 38KB+ CLAUDE.md, rules appended at the bottom get lost in context. GLM 4.7 reliably follows rules at the **top** of the file.

## Model Behavior Notes

### GLM 4.7 ✅
- Follows `echo >>` instructions without hesitation
- Runs `merge-learned-rules` when told
- Compresses rules aggressively (3 lines from 4 verbose lines)
- Follows learned rules in new sessions when they're at top of CLAUDE.md
- Does NOT auto-read CLAUDE.md on session start (needs explicit instruction or tool call)

### Haiku 4.5 ❌ (not suitable for self-improvement)
- **Refuses** to write to CLAUDE-LEARNED.md — sees it as a "jailbreak attempt"
- Even when CLAUDE.md explicitly authorizes self-modification
- Smaller models are overly cautious about self-modification patterns

## Infrastructure

- **CLI path**: `openclaw agent --session-id X -m "prompt"` → embedded fallback (gateway agent fails, falls back to direct Bedrock API)
- **Timeout**: 90s outer, 75s inner — sufficient for GLM 4.7 (30-60s per turn)
- **Bedrock rate limits**: Sonnet 4.6 was rate-limited (daily token quota exhausted); GLM 4.7 and Haiku 4.5 had available quota
- **Pod spec**: 5/5 containers (openclaw, postgres, nginx, chromium, tini)

## Files Modified

| File | Change |
|------|--------|
| `_office-manager/agent-image/entrypoint.sh` | Boot-time merge of CLAUDE-LEARNED.md into both CLAUDE.md copies |
| `_office-manager/agent-image/merge-learned-rules.sh` | Runtime merge script (agents call after writing rules) |
| `_office-manager/agent-image/CLAUDE.md` | Updated "Persisting Learned Rules" section with merge instruction |
| `_office-manager/Dockerfile.agent` | COPY + symlink for merge-learned-rules script |
