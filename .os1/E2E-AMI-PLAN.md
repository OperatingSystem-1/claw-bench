# E2E AMI Benchmark Plan

## Problem

claw-bench currently tests **LLM quality** (tool use, reasoning, response quality) but doesn't validate the **full stack** that ships with each AMI. Recent improvements across repos have added:

- **chat-server**: WhatsApp/Slack relay (session persistence, webhook forwarding)
- **agent-kit**: Task queue, inter-agent messaging, memory persistence
- **image-manager**: env-sync, GUI/VNC desktop skill, patch-config hardening
- **website**: Warm pool, per-bot IAM, TRIBE sync, env-sync push

None of these are covered by claw-bench today. A bad AMI can pass all 46 current tests and still break production.

---

## Goal

Run a **full e2e benchmark on every new AMI** that validates:
1. AMI boots and clawdbot starts
2. Gateway auth works
3. Chat relay integration works
4. Agent-kit features work (task queue, messaging, memory)
5. Env-sync and runtime config patching works
6. GUI/VNC desktop is functional
7. Full provisioning flow (as website would do it) works

**Trigger**: `bake-ami.sh` completes → claw-bench runs → pass/fail gates AMI promotion.

---

## New Test Tiers

### Tier 0: AMI Boot Validation (tests 50-54)

These replace the ad-hoc smoke tests currently in `bake-ami.sh` with standardized, repeatable benchmarks.

| # | Test | What it validates |
|---|------|-------------------|
| 50 | `ami_boot_ready` | Instance boots, UserData runs, clawdbot starts on :18789 within 5 min |
| 51 | `ami_component_check` | node, clawdbot, vncserver, xfce4-session, chromium all present |
| 52 | `ami_config_patching` | `patch-config.sh` replaces `__INSTANCE_SECRET__` correctly |
| 53 | `ami_service_health` | `systemctl status clawdbot` is active, gateway responds to `/` |
| 54 | `ami_clean_state` | No stale sessions, no leaked credentials, no PII from builder |

**Implementation**: Wrap existing `infra/launch-instance.sh` + SSH checks. Each test SSHes into instance and validates.

### Tier 1: Gateway & Auth (tests 55-58)

| # | Test | What it validates |
|---|------|-------------------|
| 55 | `gateway_auth_valid_token` | Request with correct instance-secret → 200 |
| 56 | `gateway_auth_invalid_token` | Request with wrong token → 401 |
| 57 | `gateway_trusted_proxy` | Request from trusted proxy IP accepted |
| 58 | `gateway_session_lifecycle` | Create session → send message → get response → session persists |

### Tier 2: Chat Relay Integration (tests 60-65)

Requires chat-server running (Docker or on-instance).

| # | Test | What it validates |
|---|------|-------------------|
| 60 | `relay_agent_register` | Agent registers with OFFICE_SECRET, receives bearer token |
| 61 | `relay_send_message` | Agent sends message via relay `/api/chat/send` |
| 62 | `relay_webhook_receive` | Inbound message forwarded to agent webhook |
| 63 | `relay_session_persist` | Restart clawdbot → relay sessions survive (zero-downtime) |
| 64 | `relay_multi_agent` | Two agents share relay without cross-talk |
| 65 | `relay_queue_retry` | Send to unreachable → queued → retried on reconnect |

### Tier 3: Agent-Kit Features (tests 70-77)

| # | Test | What it validates |
|---|------|-------------------|
| 70 | `tq_create_claim` | `tq add "task"` → `tq claim` → `tq done` lifecycle |
| 71 | `tq_dependencies` | Task with `--after` dependency blocks until parent done |
| 72 | `tq_worker_dispatch` | Worker auto-claims and executes queued tasks |
| 73 | `messaging_send_receive` | Agent A sends message → Agent B inbox shows it |
| 74 | `messaging_broadcast` | Broadcast to all agents → all receive |
| 75 | `messaging_crypto_verify` | Ed25519-signed message passes verification |
| 76 | `memory_persist_reset` | Write memory → restart agent → memory survives |
| 77 | `session_handoff` | Start task in session A → handoff → complete in session B |

### Tier 4: Runtime Config (tests 80-84)

| # | Test | What it validates |
|---|------|-------------------|
| 80 | `envsync_model_switch` | Push `MODEL_ID=nova-lite` → clawdbot restarts with new model |
| 81 | `envsync_aws_creds` | Push Bedrock creds → agent can call Bedrock |
| 82 | `envsync_bot_name` | Push `BOT_NAME=TestBot` → agent identity updates |
| 83 | `envsync_allowlist` | Push disallowed var → rejected |
| 84 | `tribe_sync` | Push TRIBE auth → `~/.tribe/tutor/auth.json` written, token valid |

### Tier 5: GUI & Desktop (tests 90-93)

| # | Test | What it validates |
|---|------|-------------------|
| 90 | `gui_vnc_start` | `gui-manager.sh start` → VNC on :6901 responds |
| 91 | `gui_desktop_screenshot` | Desktop skill `screenshot` returns valid PNG |
| 92 | `gui_browser_launch` | `chromium-browser` launches, page loads |
| 93 | `gui_xdotool_interact` | `click`/`type`/`keypress` execute without error |

### Tier 6: Full Provisioning Flow (tests 95-99)

Simulates exactly what the website does.

| # | Test | What it validates |
|---|------|-------------------|
| 95 | `provision_cold_start` | Generate UserData → launch instance → wait for ready callback |
| 96 | `provision_iam_isolation` | Per-bot IAM user created, can only access assigned model |
| 97 | `provision_ready_callback` | Instance POSTs to `/api/bots/{id}/ready` with correct secret |
| 98 | `provision_terminal_relay` | SSH-over-WebSocket terminal session connects |
| 99 | `provision_full_lifecycle` | Provision → online → send message → get response → terminate |

---

## CI/CD Integration

### Trigger: Post-AMI Bake

```
bake-ami.sh completes
  → outputs AMI_ID
  → calls: ./run-e2e.sh --ami $AMI_ID --tier 0,1,4,5
  → if pass: tag AMI "e2e-validated=true"
  → if fail: tag AMI "e2e-validated=false", block promotion
```

### New Entry Point: `run-e2e.sh`

```bash
./run-e2e.sh --ami ami-xxxxx                    # All tiers
./run-e2e.sh --ami ami-xxxxx --tier 0,1         # Boot + auth only (fast, ~3 min)
./run-e2e.sh --ami ami-xxxxx --tier 0,1,2,3,4,5 # Full suite (~15 min)
./run-e2e.sh --ami ami-xxxxx --tier 6           # Provisioning flow (~8 min)
./run-e2e.sh --compare ami-old ami-new          # Regression comparison
```

### AMI Promotion Pipeline

```
bake-ami.sh → AMI created (unvalidated)
    │
    ├─→ run-e2e.sh --tier 0,1 (fast gate, ~3 min)
    │     ├─ PASS → tag "smoke=pass"
    │     └─ FAIL → tag "smoke=fail", alert, STOP
    │
    ├─→ run-e2e.sh --tier 0,1,2,3,4,5 (full gate, ~15 min)
    │     ├─ PASS → tag "e2e=pass"
    │     └─ FAIL → tag "e2e=fail", alert, STOP
    │
    ├─→ benchmark-live.sh (existing LLM quality, ~10 min)
    │     ├─ PASS → tag "llm=pass"
    │     └─ FAIL → tag "llm=fail", alert
    │
    └─→ All gates pass → update CLAWGO_AMI_ID on Railway
```

---

## Implementation Order

### Phase 1: Foundation (now)
1. Create `run-e2e.sh` entry point with `--ami` and `--tier` flags
2. Add `lib/e2e-common.sh` with instance lifecycle helpers (launch, ssh, wait, terminate)
3. Implement Tier 0 tests (50-54) — reuse `infra/` scripts
4. Implement Tier 1 tests (55-58) — gateway HTTP checks

### Phase 2: Runtime Config
5. Implement Tier 4 tests (80-84) — env-sync via SSH
6. Implement Tier 5 tests (90-93) — GUI/VNC over SSH

### Phase 3: Agent Features
7. Implement Tier 3 tests (70-77) — agent-kit on instance
8. Implement Tier 2 tests (60-65) — requires chat-server Docker on instance or sidecar

### Phase 4: Full Flow
9. Implement Tier 6 tests (95-99) — mock website provisioning
10. Wire `bake-ami.sh` → `run-e2e.sh` → AMI tagging

### Phase 5: Reporting
11. JSON + TAP output for all e2e tiers (extend existing `lib/common.sh`)
12. AMI comparison reports (diff two AMI benchmark results)
13. Historical tracking (store results per AMI version)

---

## Infrastructure Requirements

| Requirement | Status | Notes |
|-------------|--------|-------|
| AWS credentials with EC2 + IAM access | Exists | In `.env` for benchmark-live |
| Security group allowing :18789, :22, :6901 | Exists | `CLAWGO_SECURITY_GROUP_ID` |
| SSH key pair | Exists | `CLAWGO_KEY_PAIR_NAME` |
| chat-server Docker image | Needs build | Or: install on instance via UserData |
| agent-kit on AMI | Partially baked | `tq` binary needed, messaging scripts need install |
| Mock callback server | New | Lightweight HTTP server to receive ready callbacks |

---

## Exit Codes (Extended)

| Code | Meaning |
|------|---------|
| 0 | All tiers passed |
| 1 | Non-critical failures (Tier 2-5) |
| 2 | Critical failure (Tier 0 or 1) — DO NOT PROMOTE AMI |
| 3 | Configuration error |
| 4 | Infrastructure error (couldn't launch instance) |

---

## Cost Estimate

| Tier | Instance Time | Estimated Cost |
|------|--------------|----------------|
| 0-1 (smoke) | ~3 min | ~$0.01 |
| 0-5 (full) | ~15 min | ~$0.05 |
| 6 (provisioning) | ~8 min | ~$0.03 |
| + LLM benchmark | ~10 min | ~$0.50 (model inference) |
| **Total per AMI** | **~25 min** | **~$0.60** |

Auto-terminates instances after each run. No ongoing costs.
