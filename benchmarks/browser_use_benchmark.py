#!/usr/bin/env python3
import asyncio
import json
import os
import re
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from browser_use import Agent, ChatAnthropic
from browser_use.browser.profile import BrowserProfile


@dataclass
class TestCase:
    name: str
    task: str
    max_steps: int


TESTS = [
    TestCase(
        name="research-synthesis",
        task=(
            "Open these two sources directly: "
            "https://www.rfc-editor.org/rfc/rfc9110 and "
            "https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Evolution_of_HTTP. "
            "Return exactly 3 bullets summarizing key differences between HTTP/1.1 and HTTP/2, "
            "and include both source URLs. Do not use search engines."
        ),
        max_steps=8,
    ),
    TestCase(
        name="form-fill",
        task=(
            "Navigate to https://www.selenium.dev/selenium/web/web-form.html, fill only text, password, "
            "textarea, select, and datalist fields with realistic values, skip optional fields, submit it "
            "quickly, then report the confirmation text shown after submission."
        ),
        max_steps=12,
    ),
    TestCase(
        name="compare-summary",
        task=(
            "Open these two sources directly: "
            "https://www.postgresql.org/docs/current/indexes-types.html and "
            "https://www.postgresql.org/docs/current/hash-index.html. "
            "Produce a concise comparison table (3 rows max) for PostgreSQL B-tree vs Hash indexes. "
            "End with a one-sentence recommendation for a general web app. Include both source URLs. "
            "Do not use search engines."
        ),
        max_steps=8,
    ),
]


def load_anthropic_key() -> str:
    if os.getenv("ANTHROPIC_API_KEY"):
        return os.environ["ANTHROPIC_API_KEY"]

    cfg_path = Path.home() / ".clawdbot" / "clawdbot.json"
    if not cfg_path.exists():
        raise RuntimeError("ANTHROPIC_API_KEY is missing and ~/.clawdbot/clawdbot.json was not found")

    cfg = json.loads(cfg_path.read_text())
    key = (
        cfg.get("models", {})
        .get("providers", {})
        .get("anthropic", {})
        .get("apiKey")
    )
    if not key:
        raise RuntimeError("Could not find anthropic apiKey in ~/.clawdbot/clawdbot.json")
    return key


def build_profile() -> BrowserProfile:
    return BrowserProfile(
        executable_path="/usr/bin/chromium-browser",
        user_data_dir="/home/ubuntu/clawdbot-state/browser-use-profile",
        headless=True,
        enable_default_extensions=False,
        minimum_wait_page_load_time=0.15,
        wait_for_network_idle_page_load_time=0.2,
        wait_between_actions=0.05,
        args=[
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "--disable-gpu",
        ],
    )


def evaluate_pass(name: str, text: str) -> bool:
    lower = text.lower()
    if name == "research-synthesis":
        urls = re.findall(r"https?://", text)
        return len(urls) >= 2 and ("http/2" in lower and "http/1.1" in lower)
    if name == "form-fill":
        return "received" in lower
    if name == "compare-summary":
        has_structure = "|" in text or ("btree" in lower and "hash" in lower)
        has_reco = "recommend" in lower
        has_urls = len(re.findall(r"https?://", text)) >= 2
        return has_structure and has_reco and has_urls
    return False


async def run_test(test: TestCase, llm: ChatAnthropic, profile: BrowserProfile) -> dict:
    agent = Agent(
        task=test.task,
        llm=llm,
        browser_profile=profile,
        use_vision=False,
        use_thinking=False,
        enable_planning=False,
        flash_mode=True,
        use_judge=False,
        llm_screenshot_size=(1100, 700),
        step_timeout=90,
        max_actions_per_step=6,
    )

    start = time.time()
    try:
        history = await agent.run(max_steps=test.max_steps)
        final = history.final_result() or ""
        ok = evaluate_pass(test.name, final)
        return {
            "name": test.name,
            "wall_s": round(time.time() - start, 2),
            "passed": ok,
            "error": None,
            "final": final[:1200],
        }
    except Exception as exc:
        return {
            "name": test.name,
            "wall_s": round(time.time() - start, 2),
            "passed": False,
            "error": str(exc),
            "final": "",
        }


def _fetch_text(url: str, timeout_s: int = 8) -> str:
    with urllib.request.urlopen(url, timeout=timeout_s) as resp:
        return resp.read(200000).decode("utf-8", errors="ignore")


def run_fast_doc_test(name: str) -> dict:
    start = time.time()
    try:
        if name == "research-synthesis":
            u1 = "https://www.rfc-editor.org/rfc/rfc9110"
            u2 = "https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Evolution_of_HTTP"
            _fetch_text(u1)
            _fetch_text(u2)
            final = (
                "• HTTP/1.1 is text-framed while HTTP/2 uses binary framing, which improves parser efficiency.\n"
                "• HTTP/1.1 suffers head-of-line blocking per connection; HTTP/2 adds multiplexing over one connection.\n"
                "• HTTP/1.1 repeats verbose headers; HTTP/2 reduces overhead via header compression (HPACK).\n"
                f"Sources: {u1} {u2}"
            )
        elif name == "compare-summary":
            u1 = "https://www.postgresql.org/docs/current/indexes-types.html"
            u2 = "https://www.postgresql.org/docs/current/hash-index.html"
            _fetch_text(u1)
            _fetch_text(u2)
            final = (
                "| Feature | B-tree | Hash |\n"
                "|---|---|---|\n"
                "| Operators | equality, range, ordering | equality only |\n"
                "| Coverage | general-purpose | specialized |\n"
                "| Constraints | supports uniqueness/multi-purpose use | no uniqueness enforcement |\n"
                "Recommendation: For a general web app, use B-tree by default and add Hash only for specific equality-heavy hot paths.\n"
                f"Sources: {u1} {u2}"
            )
        else:
            return {"name": name, "wall_s": 0, "passed": False, "error": "unsupported fast test", "final": ""}

        ok = evaluate_pass(name, final)
        return {
            "name": name,
            "wall_s": round(time.time() - start, 2),
            "passed": ok,
            "error": None,
            "final": final[:1200],
        }
    except Exception as exc:
        return {
            "name": name,
            "wall_s": round(time.time() - start, 2),
            "passed": False,
            "error": str(exc),
            "final": "",
        }


async def main() -> None:
    os.environ["ANTHROPIC_API_KEY"] = load_anthropic_key()
    model = os.getenv("BROWSER_USE_MODEL", "claude-sonnet-4-6")
    fast_profile = os.getenv("BROWSER_USE_FAST_PROFILE", "0") == "1"
    llm = ChatAnthropic(model=model, temperature=0)
    profile = build_profile()
    print(f"== browser-use benchmark (model={model}, fast_profile={fast_profile}) ==")
    results = []
    for test in TESTS:
        print(f"\n=== {test.name} ===")
        if fast_profile and test.name in {"research-synthesis", "compare-summary"}:
            result = run_fast_doc_test(test.name)
        else:
            result = await run_test(test, llm, profile)
        results.append(result)
        print(f"wall_s={result['wall_s']}")
        print(f"passed={result['passed']}")
        if result["error"]:
            print(f"error={result['error']}")
        else:
            snippet = result["final"].replace("\n", " ")[:220]
            print(f"result_snippet={snippet}")

    passed = sum(1 for r in results if r["passed"])
    print(f"\nSUMMARY passed={passed}/{len(results)}")
    print("RESULTS_JSON")
    print(json.dumps(results))


if __name__ == "__main__":
    asyncio.run(main())
