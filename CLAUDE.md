# Claw-Bench - Operational Directives

## What This Is

Comprehensive benchmark suite with two modes:

1. **LLM Quality Benchmarks** (`run.sh`, `benchmark-models.sh`) — Test LLM models via AWS Bedrock
2. **E2E AMI Validation** (`run-e2e.sh`) — Test complete agent deployment on EC2 instances

---

## Critical Rules

1. **Reports are auto-generated** — Never manually edit `reports/` directory
2. **Keep README in sync** — After `benchmark-models.sh` runs, update README.md scores table
3. **Test locally first** — Run `./run.sh --local` before committing test changes
4. **E2E tests provision real instances** — Expensive! Use `--no-terminate` for debugging only

---

## Directory Structure

```
claw-bench/
├── run.sh                    # LLM benchmark runner (single model)
├── benchmark-models.sh       # Multi-model LLM benchmarking (generates reports/)
├── benchmark-live.sh         # Real-time benchmark scoring
├── benchmark-parallel.sh     # Parallel model testing
├── run-e2e.sh                # E2E AMI validation (provisions real instances)
├── tests/                    # Test cases (NN_test_name.sh: 00-40+)
├── lib/                      # Shared helpers (e2e-common.sh, common.sh)
├── reports/                  # Auto-generated LLM benchmark reports (DO NOT EDIT)
├── models-to-test.json       # Models to benchmark
├── config.example.sh         # Example configuration
└── README.md                 # Scores table + test matrix
```

---

## LLM Benchmarking

### Run Single Model
```bash
./run.sh --local                    # Use local clawdbot
CLAW_HOST="user@ip" ./run.sh --ssh  # Use remote instance via SSH
```

### Run All Models (Generates Reports)
```bash
./benchmark-models.sh               # Creates reports/*-report.md
```

### Update README After Benchmark
```bash
# Extract scores from reports/ and update README.md scores table
# Or use benchmark-live.sh for real-time scoring
./benchmark-live.sh <model-name>
```

---

## E2E AMI Validation

### Test New AMI
```bash
./run-e2e.sh --ami ami-xxxxx           # Smoke + standard tiers
./run-e2e.sh --ami ami-xxxxx --tier 0,1  # Smoke tier only (~3 min)
./run-e2e.sh --ami ami-xxxxx --no-terminate  # Keep instance for debugging
```

### Test Categories
| Tier | Tests | What It Validates |
|------|-------|-------------------|
| 0 | 50-54 | AMI boot, components, config patching, service health |
| 1 | 55-58 | Gateway auth (token probing, rejection, health) |
| 2 | 60-65 | Chat relay integration |
| 3 | 70-77 | Agent-kit features |
| 4 | 80-83 | Runtime env-sync (model switch, AWS creds, routing) |
| 5 | 90-93 | GUI/VNC (desktop, screenshot, browser, xdotool) |

See: [../README.md](../README.md) "E2E AMI Tests" section for full details.

---

## LLM Benchmark Tests (00-40+)

Test files follow pattern: `NN_test_name.sh`

Examples:
- `00_clawdbot_verify.sh` — Agent boot and basic connectivity
- `02_tool_use_response.sh` — Tool invocation capability
- `14_web_search.sh` — Web search API integration
- `19_image_analysis.sh` — Image analysis capabilities

Latest test list: `ls tests/` (40+ tests total)

### Add New Test
1. Create `tests/NN_test_name.sh` (pick next NN number)
2. Use helpers from `lib/common.sh`
3. Document pass/fail criteria in header
4. Test: `./run.sh --local` (will auto-discover new test)

---

## Environment Variables

```bash
# LLM Benchmarking
CLAWGO_AMI_ID=ami-xxxxx              # Which AMI to test (for run-e2e.sh)
CLAW_TIMEOUT=90                      # Test timeout in seconds
CLAW_HOST=ubuntu@1.2.3.4             # For --ssh mode
CLAW_SSH_KEY=~/.ssh/key.pem          # SSH private key

# AWS Access
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-2
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | Some tests failed |
| 2 | Critical failures (DO NOT DEPLOY) |
| 3 | Configuration error |

---

## Troubleshooting

### Tests Timeout
Increase `CLAW_TIMEOUT`:
```bash
CLAW_TIMEOUT=300 ./run.sh --local
```

### Model Returns Empty Responses
Known issue on Bedrock for some models (Kimi K2, Nova). Check: `reports/*-report.md`.

### E2E Tests Fail (Instance Won't Boot)
```bash
# Keep instance for SSH debugging
./run-e2e.sh --ami ami-xxxxx --no-terminate

# SSH into the instance
ssh -i ~/.ssh/key.pem ec2-user@<instance-ip>

# Check cloud-init logs
tail -100 /var/log/cloud-init-output.log
```

### SSH Connection Fails (run-e2e.sh)
```bash
# Verify access before benchmark
ssh -i $CLAW_SSH_KEY $CLAW_HOST "echo ok"

# Check security group allows SSH (port 22)
```

---

## Links

- **E2E Specs**: [README.md](../README.md) — Test tiers, expectations, coverage
- **Testing Framework**: [TESTING.md](../TESTING.md) — KIND and EKS testing
- **Monorepo Guide**: [CLAUDE.md](../CLAUDE.md)
- **Image Manager**: [image-manager/CLAUDE.md](../image-manager/CLAUDE.md)
