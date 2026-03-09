# E2E Test Suite Audit — Honest Assessment

**Date**: 2026-03-09
**Scope**: All files written in this session for the e2e AMI benchmark suite

---

## What We're Trying to Achieve

Every time `bake-ami.sh` produces a new AMI, we need to know — before it goes to production — that:

1. The AMI boots and clawdbot starts (Tier 0)
2. The gateway rejects unauthorized access (Tier 1)
3. The chat relay works (Tier 2 — planned)
4. Agent-kit features work (Tier 3 — planned)
5. Runtime env-sync updates config correctly (Tier 4)
6. GUI/VNC desktop works (Tier 5)
7. The full website provisioning flow works end-to-end (Tier 6 — planned)

The four repos involved:
- **image-manager** — builds the AMI (`bake-ami.sh`, `patch-config.sh`, `apply-env.sh`)
- **website** — provisions instances from AMI (`provisioner.ts`, `security.ts`, `env-sync.ts`)
- **chat-server** — relay for WhatsApp/Slack (Docker, agent registration)
- **claw-bench** — where these tests live (`run-e2e.sh`, `tests/e2e/`)

---

## Files Written This Session

### Infrastructure
| File | Purpose | Status |
|------|---------|--------|
| `run-e2e.sh` | Entry point with --ami/--tier/--test flags | **Working** — syntax OK, help works |
| `lib/e2e-common.sh` | Instance lifecycle, SSH, HTTP, timing helpers | **Has bugs** (see below) |
| `E2E-AMI-PLAN.md` | Design doc — tiers, CI/CD pipeline, phased impl | **Accurate** |

### Tier 0 — AMI Boot (tests 50-54)
| Test | Verifies | Real Code Path | Verdict |
|------|----------|----------------|---------|
| `50_ami_boot_ready.sh` | `/opt/claw-bench/status` = "ready", gateway :18789 responds | `infra/launch-instance.sh` UserData writes markers; `systemctl start clawdbot` | **CORRECT** but partially redundant — `e2e_launch_instance()` already waits for ready via `wait-for-ready.sh`. If boot fails, we never reach test 50. Still valuable as a recorded test result. |
| `51_ami_component_check.sh` | node, clawdbot, jq, curl, git, python3, vncserver, xfce4, xdotool, scrot | AMI baked by `image-manager/ansible/playbooks/provision.yml` and `bake-ami.sh` smoke tests | **CORRECT** — matches `prepare-golden-ami-v2.sh` validation checklist |
| `52_ami_config_patching.sh` | No `__PLACEHOLDER__` in clawdbot.json, token matches launch secret | `image-manager/defaults/patch-config.sh` replaces `__INSTANCE_SECRET__` | **CORRECT** — tests the output of patch-config.sh correctly |
| `53_ami_service_health.sh` | systemd active, NRestarts < 3, :18789 listening | `image-manager/system/clawdbot.service` + systemd | **CORRECT** |
| `54_ami_clean_state.sh` | No stale sessions, no ~/.claude, no ~/.clawhub, no media | `image-manager/prepare-golden-ami-v2.sh` cleanup | **CORRECT** |

### Tier 1 — Gateway Auth (tests 55-58)
| Test | Verifies | Real Code Path | Verdict |
|------|----------|----------------|---------|
| `55_gateway_auth_valid_token.sh` | `Authorization: Bearer <instance-secret>` → 200 | clawdbot gateway binary (closed source) | **UNCERTAIN** — see Bug #1 |
| `56_gateway_auth_invalid_token.sh` | Wrong token → 401/403 | clawdbot gateway binary | **UNCERTAIN** — see Bug #1 |
| `57_gateway_no_auth.sh` | No token → rejected on `/api/agent` | clawdbot gateway binary | **UNCERTAIN** — see Bug #1 |
| `58_gateway_session_lifecycle.sh` | `claw_ask "7*8"` returns "56" | clawdbot CLI → agent → Bedrock LLM | **CORRECT** — uses proven `claw_ask` pattern from existing tests, bypasses HTTP auth entirely (SSH + CLI) |

### Tier 4 — Runtime Config (tests 80-83)
| Test | Verifies | Real Code Path | Verdict |
|------|----------|----------------|---------|
| `80_envsync_model_switch.sh` | Push MODEL_ID → clawdbot.json updated | `image-manager/defaults/apply-env.sh` `handle_config_json()` | **BUG** — see Bug #2, #3 |
| `81_envsync_aws_creds.sh` | Push AWS creds → ~/.aws/credentials written | `apply-env.sh` `handle_aws_creds()` + `finalize_aws_creds()` | **BUG** — see Bug #2, #3 |
| `82_envsync_bot_name.sh` | Push BOT_NAME → config updated | `apply-env.sh` `handle_identity()` | **BUG** — see Bug #2, #3 |
| `83_envsync_allowlist.sh` | Disallowed vars rejected | **NOTHING** — no allowlist exists here | **WRONG** — see Bug #4 (most serious) |

### Tier 5 — GUI (tests 90-93)
| Test | Verifies | Real Code Path | Verdict |
|------|----------|----------------|---------|
| `90_gui_vnc_start.sh` | `gui-manager.sh start` → :6901 listening | `image-manager/defaults/gui-manager.sh` | **CORRECT** — gracefully skips if headless |
| `91_gui_desktop_screenshot.sh` | scrot → valid PNG | XFCE + scrot on AMI | **CORRECT** — validates PNG magic bytes |
| `92_gui_browser_launch.sh` | Chromium headless loads a page | snap chromium on AMI | **CORRECT** |
| `93_gui_xdotool_interact.sh` | mousemove/key/type succeed | xdotool on AMI | **CORRECT** |

---

## Bugs Found

### Bug #1: Gateway HTTP Auth Format Unknown (Tests 55-57)

**Problem**: Tests send `Authorization: Bearer <raw-instance-secret-UUID>` to the clawdbot gateway. But there are TWO auth systems:

1. **clawdbot gateway auth** — config says `"auth": { "token": "__INSTANCE_SECRET__" }`. The gateway is a closed-source binary. We don't know if it expects `Bearer <token>`, `X-Token: <token>`, query params, or something else.

2. **Website JWT auth** — `website/src/components/gateway-proxy/token.ts` creates HS256 JWTs signed with `RELAY_JWT_SECRET`. The website uses `Authorization: Bearer <JWT>` to talk to the gateway. This is NOT the same as sending the raw secret.

**Evidence**: `wait-for-ready.sh` line 113 hits `curl -sf http://localhost:18789/` with NO auth and expects success — confirming root `/` is unauthenticated. So test 57 checking root `/` would get 200, not 401.

**Impact**: Tests 55-57 may pass or fail unpredictably. They test guessed behavior, not verified behavior.

**Fix**: SSH into a running instance and empirically test what the gateway accepts:
```bash
# What does no-auth return?
curl -v http://localhost:18789/
# What does Bearer <secret> return?
curl -v -H "Authorization: Bearer $SECRET" http://localhost:18789/
# What endpoints exist?
curl -v http://localhost:18789/api/agent
```
Then rewrite tests to match actual behavior.

---

### Bug #2: `--no-restart` Flag Doesn't Exist (Tests 80-83)

**Problem**: All Tier 4 tests call `apply-env.sh --no-restart`. This flag doesn't exist in the script.

**Actual apply-env.sh arg parsing** (`image-manager/defaults/apply-env.sh:246-250`):
```bash
if [ "${1:-}" = "--manifest" ] && [ -f "${2:-}" ]; then
    MANIFEST=$(cat "$2")
elif [ ! -t 0 ]; then
    MANIFEST=$(cat)
fi
```

Only `--manifest <path>` is supported. `--no-restart` is silently ignored because stdin is piped (the `elif` branch reads from stdin regardless of args).

**Impact**: Tests work by accident. The `--no-restart` is cosmetic noise — `apply-env.sh` never restarts anything. Restart is handled by the website's `env-sync.ts` which appends `sudo systemctl restart clawdbot` to the relay-exec command.

**Fix**: Remove `--no-restart` from all test invocations. Just pipe JSON directly.

---

### Bug #3: apply-env.sh Not Baked Into Current AMIs (Tests 80-83)

**Problem**: `image-manager` git status shows `apply-env.sh` as untracked:
```
?? defaults/apply-env.sh
```

This means it hasn't been committed to image-manager, let alone baked into any AMI. All Tier 4 tests will hit the skip path: "apply-env.sh not present."

**Impact**: Tests are correct but untestable until `apply-env.sh` is committed and a new AMI is baked.

**Fix**: This is expected for now — the skip logic handles it gracefully. But we should note that Tier 4 tests are forward-looking and won't produce results until the next AMI bake after `apply-env.sh` is committed.

---

### Bug #4: Test 83 (Allowlist) Tests The Wrong Layer — WILL FALSE-POSITIVE (CRITICAL)

**Problem**: Test 83 assumes `apply-env.sh` has an allowlist that rejects unknown vars. **It doesn't.**

The actual `var_type()` function in `apply-env.sh:33-48`:
```bash
var_type() {
    case "$1" in
        BOT_NAME|AGENT_NAME)          echo "identity" ;;
        AWS_ACCESS_KEY_ID)            echo "aws-creds" ;;
        # ... known vars ...
        *)                            echo "env-only" ;;   # ← ACCEPTS EVERYTHING
    esac
}
```

Any unknown key falls through to `env-only`, which writes it to `~/.clawdbot/.env`. This is BY DESIGN — `apply-env.sh` is a low-level tool that trusts its caller.

The actual allowlist enforcement happens in the **website** at `website/src/components/ec2/env-sync.ts:7-22`:
```typescript
const ALLOWED_ENV_VARS = new Set([
  'BOT_NAME', 'AGENT_NAME', 'OWNER_NUMBERS', 'MODEL_ID', ...
]);
```

The website filters vars BEFORE calling relay-exec → apply-env.sh.

**Impact**: Test 83 would:
1. Push `EVIL_INJECT`, `PATH`, `LD_PRELOAD` to `apply-env.sh`
2. All three get written to `.env` as `env-only` type
3. Test greps `~/.clawdbot/` and finds `EVIL_INJECT` in `.env`
4. Test reports **CRITICAL: EVIL_INJECT var written to config — allowlist bypass**
5. This is a **FALSE POSITIVE** — the AMI is working correctly

**Fix**: Two options:
- **Option A**: Rewrite test 83 to test the correct assertion — that `env-only` vars end up in `.env` but NOT in `clawdbot.json` or `~/.aws/credentials` (the routing works correctly)
- **Option B**: Move this test to Tier 6 (full provisioning flow) and test the website→relay-exec→apply-env.sh pipeline where the allowlist actually lives

---

### Bug #5: Tests Don't Match Production Env-Sync Path

**Problem**: The real env-sync flow is:
```
website env-sync.ts
  → filter through ALLOWED_ENV_VARS
  → base64-encode JSON
  → relayExec(SSH command: "echo '<b64>' | base64 -d | /opt/os1/apply-env.sh")
  → also merges into /opt/os1/env-manifest.json
  → optionally: "sudo systemctl restart clawdbot && sleep 3"
```

My tests do:
```
local base64 → SSH → "echo '<b64>' | base64 -d | sudo /opt/os1/apply-env.sh --no-restart"
```

Missing:
- No allowlist filtering (website layer)
- No env-manifest.json merge step
- `sudo` (apply-env.sh runs as root in production via relay-exec)
- Service restart verification

---

## What's Actually Correct

**Tier 0 (tests 50-54)**: All five tests are solid. They verify the exact outputs of `patch-config.sh`, `prepare-golden-ami-v2.sh`, and the systemd service. These are the highest-value tests — a failed Tier 0 means the AMI is fundamentally broken.

**Test 58 (session lifecycle)**: Correct. Uses the battle-tested `claw_ask` pattern from existing benchmarks. SSH + CLI bypasses HTTP auth uncertainty.

**Tier 5 (tests 90-93)**: All four tests are correct. They gracefully skip when components aren't present and verify real functionality (VNC ports, PNG validity, xdotool commands).

**Infrastructure (run-e2e.sh, e2e-common.sh)**: The runner, tier filtering, instance lifecycle, and cleanup trap are solid. The architecture of launching one instance and running all tiers against it is correct and cost-efficient.

---

## What's Missing Entirely

| Gap | Why It Matters | Which Repo |
|-----|---------------|------------|
| **Bedrock health check** | Test 58 conflates gateway + LLM. Need isolated Bedrock test. | website (`ready/route.ts` does this) |
| **patch-config.sh direct test** | We test its output (test 52) but not the script itself with various inputs | image-manager |
| **Warm pool claim flow** | Most common production path — `pool.ts` atomically claims pooled bots | website |
| **Ready callback** | Instance POSTs to `/api/bots/{id}/ready` with `x-instance-secret` header | website + image-manager |
| **env-manifest.json persistence** | env-sync.ts merges manifests so vars survive reboots | website + image-manager |
| **Service restart after env-sync** | `systemctl restart clawdbot` + wait for gateway ready | image-manager |
| **Chat relay integration** | Agent registration, message send/receive, session persistence | chat-server |
| **Agent-kit features** | Task queue, inter-agent messaging, memory persistence | agent-kit |
| **IMDSv2 enforcement** | `HttpTokens=required` — prevents SSRF credential theft | image-manager + website |
| **Multi-tier cost/model isolation** | Different tiers get different instance types and models | website (`types.ts`) |

---

## Fixes Required (Priority Order)

### P0 — Must Fix Before Running

1. **Delete or rewrite test 83** — will false-positive on correct AMIs
2. **Remove `--no-restart`** from tests 80-82 — flag doesn't exist
3. **Verify gateway HTTP auth format** empirically before trusting tests 55-57

### P1 — Should Fix Soon

4. **Rewrite tests 55-57** after determining actual gateway auth mechanism
5. **Add Bedrock health check test** (separate from session lifecycle)
6. **Test the actual env-sync.ts flow** including allowlist, manifest merge, and restart

### P2 — Next Phase

7. Implement Tier 2 (chat relay) — requires chat-server Docker
8. Implement Tier 3 (agent-kit) — requires tq binary on AMI
9. Implement Tier 6 (provisioning flow) — requires mock callback server
10. Wire `bake-ami.sh` → `run-e2e.sh` → AMI tagging

---

## Summary

**17 tests written. 9 are correct. 4 are uncertain. 4 have bugs.**

| Category | Tests | Correct | Buggy | Uncertain |
|----------|-------|---------|-------|-----------|
| Tier 0 (Boot) | 50-54 | 5 | 0 | 0 |
| Tier 1 (Auth) | 55-58 | 1 | 0 | 3 |
| Tier 4 (Config) | 80-83 | 0 | 4 | 0 |
| Tier 5 (GUI) | 90-93 | 4 | 0 | 0 |
| **Total** | **17** | **10** | **4** | **3** |

The infrastructure (`run-e2e.sh`, `e2e-common.sh`) is sound. The test framework works. The problem is that I wrote Tier 1 and Tier 4 tests against assumed behavior rather than verified behavior. Tier 0 and Tier 5 are solid because they test observable system state (files exist, ports listen, binaries run) rather than protocol details.
