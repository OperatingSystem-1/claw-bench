# Recursive Self-Improvement Stress Test

**Date**: 2026-05-20
**Agent**: os1-reed (Cloud Ridge office, production EKS)
**Model**: GLM 4.7 (`zai.glm-4.7`) via Bedrock ON_DEMAND
**Gateway**: openclaw 2026.4.26
**Dispatch**: `openclaw agent` CLI subprocess (540s timeout)

## Test Protocol

Clear `~/.openclaw/.claude/CLAUDE-LEARNED.md`, then progressively test the agent's ability to:
1. Write behavioral rules when told to
2. Accumulate multiple rules
3. Follow its own learned rules
4. Autonomously diagnose a failure and write a fix
5. Verify the fix works on the next call
6. Recursively improve its own rules (compress, optimize)

## Results

| Round | Test | Result | Time | Detail |
|-------|------|--------|------|--------|
| 1 | Write rule via CLI (`echo >>`) | ✅ PASS | ~60s | Wrote: "ALWAYS include today's date" |
| 2 | Write SECOND rule (accumulate) | ✅ PASS | ~60s | Wrote: "NEVER guess file contents — always cat first". Both rules present. |
| 3a | Bedrock direct follows date rule | ❌ FAIL | ~1s | GLM 4.7 ignored the weak phrasing |
| 3b | Bedrock direct follows file rule | ✅ PASS | ~1s | Used `cat /etc/hostname` correctly |
| 3c | Bedrock direct follows STRONG date rule | ✅ PASS | ~1s | "CRITICAL RULE:" prefix → followed |
| 4 | Autonomous diagnosis + self-fix | ✅ PASS | ~120s | Agent wrote a 30-line detailed rule with checklist and examples |
| 5 | Verify self-written fix works | ✅ PASS | ~60s | Agent ran date verification on next call |
| 6 | Recursive improvement (compress own rule) | ✅ PASS | ~60s | Compressed from 30 lines to 2 lines on command |

## Key Findings

### 1. Self-improvement works end-to-end
The agent can:
- Write rules to `CLAUDE-LEARNED.md` via shell exec (CLI gateway path)
- Rules persist on PVC across sessions (ext4 mount at `/home/openclaw/.openclaw`)
- Rules are loaded into both Bedrock direct and CLI gateway prompts
- Subsequent behavior changes based on learned rules

### 2. Rule strength matters for non-Claude models
GLM 4.7 ignores vague rules like "always include the date." It follows explicit rules prefixed with:
- `CRITICAL RULE:` ✅
- `## RULE:` with `MUST`/`NEVER` keywords ✅
- Soft suggestions ("try to include...") ❌

**Recommendation**: Self-improvement rules should use structured format:
```
## RULE: [title]
[one-line explanation]
BEFORE: [wrong behavior]
AFTER: [correct behavior]
```

### 3. Recursive self-improvement confirmed
The agent successfully:
1. Diagnosed its own failure (Round 4: "you hallucinate dates instead of checking")
2. Wrote a detailed fix with examples and checklist
3. Followed its own fix on the next call (Round 5)
4. Compressed its own rule from 30 lines to 2 lines when asked (Round 6)

This is genuine recursive self-improvement — the agent modifies its own instruction set, verifies the modification works, and can optimize the modifications.

### 4. Limitations

| Limitation | Impact | Workaround |
|-----------|--------|-----------|
| Bedrock direct path can't exec shell | Can't write rules from WhatsApp fast path | CLI fallback can write; rules from XMTP apply to WhatsApp too |
| GLM ignores weak rules | Rules need strong phrasing | Use "CRITICAL RULE:" or "## RULE:" format |
| No rule validation | Agent can write bad/contradictory rules | Manual review of CLAUDE-LEARNED.md |
| 49K char system prompt | Rules accumulate unboundedly | Agent can self-compress (Round 6 proved this) |
| CLI takes 60-120s per call | Self-improvement is slow | Bedrock direct handles simple chat; CLI only for tool use |

### 5. Self-improvement flow

```
Problem detected (by user or agent)
  ↓
Agent runs: echo "## RULE: ..." >> ~/.openclaw/.claude/CLAUDE-LEARNED.md
  ↓
Rule written to PVC (survives pod restarts)
  ↓
Next message loads CLAUDE-LEARNED.md into system prompt
  ↓
Agent behavior changes
  ↓
If rule is too verbose → agent can self-compress (recursive improvement)
```

## Raw Outputs

### Round 4: Agent's self-written rule (before compression)
```
## RULE: Never Answer Date/Time Questions Without Verification

**CRITICAL ERROR PATTERN (detected: 2026-05-20):** You repeatedly answer
date/time questions without running verification commands.

### THE FIX
Before answering ANY date/time question, you MUST run ONE of:
- `session_status` or `date` (exec) for system time
- Never rely on system prompt timestamps or assumptions

### MANDATORY CHECKLIST:
1. Did I run `session_status` or `date`?
2. Is the timestamp in my answer FROM the actual command output?
3. Did I not guess or approximate?
```

### Round 6: After recursive compression
```
## RULE: Never Answer Date/Time Questions Without Verification
Date/time is mutable state. Before answering, run `session_status` or
`date` — never rely on system prompts or assumptions.
```
