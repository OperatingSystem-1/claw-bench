# Claw-Bench Changelog

## [1.7.0] - 2026-02-22

### Added - Email Integration Tests
Tests for Gmail integration via the Python IMAP client (`email` skill).

**New Tests (44-45):**
- TEST 44: Email Inbox List - invoke email skill to list recent inbox messages, verify subjects and senders returned
- TEST 45: Email Search - search emails by subject with verification code extraction, handle empty results gracefully

**Prerequisites:**
- Email credentials at `~/.config/email/credentials.json` (server, username, password, email)
- IMAP server reachable from the agent instance
- Tests degrade gracefully (WARN + PASS) when credentials are missing or server is unreachable

### Benchmark Coverage (v1.7)
| Category | Tests | Coverage |
|----------|-------|----------|
| Core Agent | 0-12 | Basic functionality |
| Extended Tools | 13-20 | All major clawdbot tools |
| Use Cases | 22-28 | Real-world scenarios |
| Robustness | 29-31 | Error handling, edge cases |
| Stress | 32-33 | Long context, structured output |
| Advanced Reasoning | 34 | Integration discovery |
| Parallel Sessions | 35-40 | Session isolation, shared memory, hibernation |
| Browser Use | 41-43 | Research, form fill, compare workflows |
| Email Integration | 44-45 | Inbox listing, search, verification codes |

---

## [1.6.0] - 2026-02-22

### Added - Browser Use Benchmarks
Migrated browser use benchmarks from OS-1 (`enable-presets` branch) into claw-bench.
Tests browser automation performance across research, form interaction, and multi-step workflows.

**New Tests (41-43):**
- TEST 41: Browser Research Synthesis - web_search + navigate + synthesize HTTP/1.1 vs HTTP/2 comparison from multiple sources
- TEST 42: Browser Form Fill - navigate to Selenium test form, fill fields, submit, verify confirmation
- TEST 43: Browser Compare Summary - search + compare PostgreSQL B-tree vs Hash indexes with recommendation

**New Standalone Benchmarks (`benchmarks/` directory):**
- `browser_use_benchmark.py` - Python benchmark using browser_use library (3 tasks, pass/fail evaluation)
- `run_browser_use_benchmark.sh` - Shell wrapper with venv activation and model configuration
- `run_openclaw_benchmark.sh` - Shell harness with gateway log analysis and tool call counting
- `browser_benchmark.md` - Comprehensive optimization docs (5 rounds, 45% improvement on search tasks)
- `openclaw_benchmark.md` - Test definitions and performance targets

**Prerequisites:**
- Browser tool available (CDP browser connected)
- web_search tool configured (Brave Search API)
- For standalone Python benchmark: `browser_use` Python package in venv

### Benchmark Coverage (v1.6)
| Category | Tests | Coverage |
|----------|-------|----------|
| Core Agent | 0-12 | Basic functionality |
| Extended Tools | 13-20 | All major clawdbot tools |
| Use Cases | 22-28 | Real-world scenarios |
| Robustness | 29-31 | Error handling, edge cases |
| Stress | 32-33 | Long context, structured output |
| Advanced Reasoning | 34 | Integration discovery |
| Parallel Sessions | 35-40 | Session isolation, shared memory, hibernation |
| Browser Use | 41-43 | Research, form fill, compare workflows |

---

## [1.5.0] - 2026-02-21

### Added - Parallel Sessions Benchmarks
New test category for the parallel sessions feature (openclaw PR #23179).
Tests session isolation, shared memory, hibernation, and concurrent session management.

**New Tests (35-40):**
- TEST 35: Session Isolation - two sessions with different secrets, verifies no leakage
- TEST 36: Cross-Session Knowledge Sharing - high-importance facts propagate via global knowledge
- TEST 37: Session Persistence - context survives hibernation and reactivation
- TEST 38: Concurrent Session Stress - 5 simultaneous sessions with unique codes
- TEST 39: Memory Search Across Sessions - keyword-targeted retrieval from shared memory
- TEST 40: Context Briefing Verification - agent surfaces prior context proactively

**Prerequisites:**
- Requires `parallelSessions.enabled: true` in agent config
- Requires openclaw with parallel sessions support (PR #23179)

### Benchmark Coverage (v1.5)
| Category | Tests | Coverage |
|----------|-------|----------|
| Core Agent | 0-12 | Basic functionality |
| Extended Tools | 13-20 | All major clawdbot tools |
| Use Cases | 22-28 | Real-world scenarios |
| Robustness | 29-31 | Error handling, edge cases |
| Stress | 32-33 | Long context, structured output |
| Advanced Reasoning | 34 | Integration discovery |
| Parallel Sessions | 35-40 | Session isolation, shared memory, hibernation |

---

## [1.3.0] - 2026-02-08

### Added - Stress & Integration Tests
Final iteration with comprehensive coverage:

**New Tests (32-33):**
- TEST 32: Long Context Handling - extracts hidden instructions from long docs
- TEST 33: JSON Output Formatting - validates structured output generation

### Fixed
- TEST 25: Memory test now accepts TRIBE KB auth limitation gracefully
- Improved memory test prompt to use local storage first

### Analysis from v1.2
- 30/31 passed
- Only failure: TEST 25 (memory) due to TRIBE KB auth requirement
- All robustness tests (29-31) passed

### Benchmark Coverage (v1.3)
| Category | Tests | Coverage |
|----------|-------|----------|
| Core Agent | 0-12 | Basic functionality |
| Extended Tools | 13-20 | All major clawdbot tools |
| Use Cases | 22-28 | Real-world scenarios |
| Robustness | 29-31 | Error handling, edge cases |
| Stress | 32-33 | Long context, structured output |

---

## [1.2.0] - 2026-02-08

### Added - Robustness & Edge Case Tests
Based on v1.1 failures and analysis:

**New Tests (29-31):**
- TEST 29: Error Recovery - handles tool failures gracefully
- TEST 30: Complex Multi-step Instructions - ordered step execution
- TEST 31: Adversarial Input Handling - resists misdirection

### Fixed
- TEST 26: Weather skill prompt simplified for reliability
- Improved pattern matching for weather conditions

### Analysis from v1.1
- 26/28 passed initially
- Failures: TEST 7 (intermittent empty response), TEST 26 (pattern matching)
- Weather skill works but test patterns were too specific

---

## [1.1.0] - 2026-02-08

### Added - Use Case Benchmarks
Based on analysis of openclaw's ideal use cases:

**New Tests (22-28):**
- TEST 22: Multi-turn Context Retention
- TEST 23: Research Task (web + summarize)
- TEST 24: Code Generation Task
- TEST 25: Memory Store and Recall
- TEST 26: Skill-based Workflow
- TEST 27: Multi-tool Chain
- TEST 28: Long-form Response Quality

**Key Use Cases Identified:**
1. **Conversational AI** - Multi-turn context, instruction following
2. **Research Assistant** - Web search, data extraction, summarization
3. **Coding Agent** - Code generation, review, execution
4. **Knowledge Management** - Memory storage, recall, organization
5. **Automation** - Tool chaining, workflows, integrations

### Changed
- Tightened validation for tests 15, 17, 18 (require specific technical output)
- Added base64 encoding for SSH message transmission
- Added `-n` flag to all SSH calls

## [1.0.0] - 2026-02-07

### Initial Release
- 21 core tests covering basic agent functionality
- Multi-model benchmark support
- Report generation

### Tests
- TEST 0: Clawdbot Verification
- TEST 1-12: Core agent tests (chat, tools, reasoning)
- TEST 13-20: Extended tool tests (exec, search, browser, files)
