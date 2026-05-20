# Bedrock New Models — May 2026 Live Testing

**Date**: 2026-05-19/20
**Environment**: Production EKS (os1-production), Cloud Ridge office
**Agent**: os1-reed on openclaw 2026.4.26
**Test Method**: Live agent pod via `boto3.client('bedrock-runtime').converse()` + openclaw agent CLI + WhatsApp E2E

## Model Availability (us-east-2)

All models tested with IAM policy `clawgo-bedrock-opus-only` v8 (allows all foundation models).

| Model ID | Provider | Status | Latency (simple) | Tool Use | Notes |
|----------|----------|--------|-------------------|----------|-------|
| `qwen.qwen3-235b-a22b-2507-v1:0` | Qwen | ✅ ON_DEMAND | 0.2s | ✅ Via gateway | MoE 235B, strong instruction following |
| `qwen.qwen3-32b-v1:0` | Qwen | ✅ ON_DEMAND | ~0.1s | Untested | Smaller, faster |
| `qwen.qwen3-next-80b-a3b` | Qwen | ✅ ON_DEMAND | ~0.2s | Untested | |
| `qwen.qwen3-coder-480b-a35b-v1:0` | Qwen | ✅ ON_DEMAND | Untested | Untested | Code-focused MoE |
| `zai.glm-4.7` | Z.AI | ✅ ON_DEMAND | 0.2s | ✅ Via gateway | Strong general model |
| `zai.glm-4.7-flash` | Z.AI | ✅ ON_DEMAND | 0.2s | Untested | Faster variant |
| `zai.glm-5` | Z.AI | ✅ ON_DEMAND | Untested | Untested | Latest Z.AI |
| `mistral.mistral-large-3-675b-instruct` | Mistral | ✅ ON_DEMAND | 0.2s | ⚠️ Weak | Poor instruction following for agent tools |
| `mistral.devstral-2-123b` | Mistral | ✅ ON_DEMAND | Untested | Untested | Code-focused |
| `us.anthropic.claude-sonnet-4-6` | Anthropic | ✅ INFERENCE_PROFILE | ~1s | ✅ Best | Requires `us.` prefix. Daily token quota can exhaust. |
| `us.anthropic.claude-opus-4-7` | Anthropic | ✅ INFERENCE_PROFILE | ~3-5s | ✅ Best | Slowest, most capable |

## Self-Improvement E2E Test Results

Tested on os1-reed with each model's ability to autonomously write behavioral rules to `~/.openclaw/.claude/CLAUDE-LEARNED.md`.

### Test Protocol
1. Clear CLAUDE-LEARNED.md
2. Ask agent (via CLI) to write a self-improvement rule using `echo >>`
3. Verify rule was written to file
4. Verify rule is loaded into next prompt (Bedrock direct path)
5. Verify model follows the learned rule
6. Verify file persists on PVC

### Results

| Step | Test | Qwen 3 235B | GLM 4.7 |
|------|------|-------------|---------|
| 1 | Clear file | ✅ | ✅ |
| 2 | CLI writes rule via shell exec | ✅ | ✅ |
| 3 | Rule loaded in next prompt | ✅ | ✅ |
| 4a | Follows weak rule ("always greet by name") | ✅ | ❌ Ignored |
| 4b | Follows strong rule ("CRITICAL RULE: say Hey [name]!") | ✅ | ✅ |
| 5 | Autonomous self-improvement (writes rule without being told how) | ✅ | ✅ |
| 6 | PVC persistence | ✅ | ✅ |

**Key Finding**: GLM 4.7 requires stronger/more explicit rule phrasing than Qwen 3. Vague instructions are ignored. Rules prefixed with "CRITICAL RULE:" or "ALWAYS:" are followed. Claude Sonnet follows even weak rules reliably.

## WhatsApp Dispatch Performance

| Path | Latency | Tool Execution | Identity |
|------|---------|----------------|----------|
| Bedrock direct (dispatchViaBedrock) | ~1-2s | ❌ No shell exec | ✅ From workspace files |
| CLI subprocess (dispatchViaCLI) | ~60-300s | ✅ Full tools | ✅ Full gateway session |
| XMTP gateway (GatewayConnection) | ~60-300s | ✅ Full tools | ✅ Full gateway session |

**Why CLI is slow**: The `openclaw agent` CLI subprocess scans 871MB of plugin dependencies on every invocation. The gateway accepts the request in ~100ms but the CLI process takes 1-5 minutes to complete the full round-trip. This affects ALL Bedrock models equally — it's not model-dependent.

## IAM Policy

All Bedrock models now accessible via policy `clawgo-bedrock-opus-only` v8:
```json
{
  "Effect": "Allow",
  "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
  "Resource": ["arn:aws:bedrock:*::foundation-model/*", "arn:aws:bedrock:*:856898221895:inference-profile/*"]
}
```

Previously restricted to `anthropic.claude-*` only. Updated 2026-05-19.

## Provider Rate Limits (Observed)

| Provider | Limit Type | Observed Behavior |
|----------|-----------|-------------------|
| Anthropic (Bedrock) | Daily token quota | Exhausted after ~4 agents × heavy usage. Resets midnight UTC. |
| Qwen (Bedrock) | ON_DEMAND | No observed rate limits |
| Z.AI/GLM (Bedrock) | ON_DEMAND | No observed rate limits |
| Mistral (Bedrock) | ON_DEMAND | No observed rate limits |
| Anthropic (Claude Code proxy) | OAuth + our rate limiter | 4 req/min caused hard blocks. Raised to 60 rpm. |
| Google Gemini | API key | No observed rate limits on Flash tier |

**Recommendation**: Spread agents across different provider families to avoid quota exhaustion. Don't put all agents on Anthropic/Claude.

## Gateway Sandbox Restrictions

The openclaw gateway blocks HTTP requests to private/internal IPs. This prevents agents from reaching in-cluster proxies (claude-code-proxy, gemini-proxy) via the gateway's URL fetch tool.

**Affected**: Any proxy at `*.svc.cluster.local` addresses
**Workaround**: Use shell CLI tools (`gws`, `gh`, `tq`) instead of HTTP fetch
**Impact**: Models that default to HTTP fetch (Gemini, Mistral) fail at tool use unless explicitly instructed to use CLI
