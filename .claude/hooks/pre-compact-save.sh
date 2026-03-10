#!/bin/bash
# Pre-compact hook: saves git state across the monorepo before context compaction
# Detects if we're in a submodule and captures both subrepo AND monorepo root state
set -euo pipefail

input=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Detect monorepo root by looking for the Makefile with our cross-repo targets
find_monorepo_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.gitmodules" ] && [ -f "$dir/Makefile" ] && grep -q 'submodule foreach' "$dir/Makefile" 2>/dev/null; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

MONO_ROOT=$(find_monorepo_root "$PROJECT_DIR" 2>/dev/null || echo "")

SESSION_DIR="$PROJECT_DIR/.claude/session-summaries"
mkdir -p "$SESSION_DIR"

# Prune summaries older than 7 days
find "$SESSION_DIR" -name '*.md' -mtime +7 -delete 2>/dev/null || true

TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TRIGGER=$(echo "$input" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")

SUMMARY_FILE="$SESSION_DIR/${TIMESTAMP}.md"

# Capture git state for a repo (runs in subshell to isolate cwd)
repo_state() {
  (
    cd "$1" || return
    local label="$2"
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")

    echo "### ${label}"
    echo ""
    echo "**Branch:** \`${branch}\`"
    echo ""

    local status_output
    status_output=$(git status --short 2>/dev/null)
    if [ -n "$status_output" ]; then
      echo "**Changed files:**"
      echo "\`\`\`"
      echo "$status_output"
      echo "\`\`\`"
    else
      echo "_Working tree clean_"
    fi
    echo ""

    local staged
    staged=$(git diff --cached --stat 2>/dev/null)
    if [ -n "$staged" ]; then
      echo "**Staged for commit:**"
      echo "\`\`\`"
      echo "$staged"
      echo "\`\`\`"
      echo ""
    fi

    echo "**Recent commits:**"
    echo "\`\`\`"
    git log --oneline -5 2>/dev/null || echo "no commits"
    echo "\`\`\`"
    echo ""
  )
}

# Files modified in the last 30 minutes — single find call, no per-file re-find
recently_touched() {
  (
    cd "$1" || return
    local files
    files=$(find . -maxdepth 4 \
      \( -name node_modules -o -name .next -o -name .git \) -prune -o \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.sh' -o -name '*.md' -o -name '*.json' \) \
      -mmin -30 -type f -print 2>/dev/null | head -15)
    if [ -n "$files" ]; then
      echo "**Recently modified files (last 30 min):**"
      echo "\`\`\`"
      echo "$files"
      echo "\`\`\`"
      echo ""
    fi
  )
}

{
  cat << HEADER
# Session Summary — ${TIMESTAMP}

- **Session ID:** ${SESSION_ID}
- **Compact trigger:** ${TRIGGER}
- **Project:** ${PROJECT_DIR}
- **Monorepo root:** ${MONO_ROOT:-"(not in monorepo)"}
- **Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Instructions for Claude

After compaction, read this file to restore working context:
1. Run \`git status\` and \`git log --oneline -5\` to verify current state
2. Check the "Recently modified files" section for what was actively being worked on
3. If in a submodule, check "Monorepo Cross-Repo State" for sibling repo context

## Current Repo (${PROJECT_DIR##*/})

HEADER

  repo_state "$PROJECT_DIR" "$(basename "$PROJECT_DIR")"
  recently_touched "$PROJECT_DIR"

  if [ -n "$MONO_ROOT" ]; then
    echo "---"
    echo ""

    if [ "$MONO_ROOT" != "$PROJECT_DIR" ]; then
      echo "## Monorepo Cross-Repo State"
      echo ""
      repo_state "$MONO_ROOT" "monorepo root"
    fi

    echo "### All Submodules"
    echo ""
    echo "| Repo | Branch | Status |"
    echo "|------|--------|--------|"
    (
      cd "$MONO_ROOT"
      git submodule foreach --quiet 'branch=$(git branch --show-current 2>/dev/null || echo "detached"); changes=$(git status --short 2>/dev/null | wc -l | tr -d " "); if [ "$changes" = "0" ]; then st="clean"; else st="${changes} changed"; fi; echo "| $(basename $sm_path) | \`${branch}\` | ${st} |"' 2>/dev/null || echo "| (error) | - | - |"
    )
    echo ""
  fi

} > "$SUMMARY_FILE"

echo "Saved session summary to $SUMMARY_FILE" >&2

cat << HOOKJSON
{
  "ok": true,
  "additionalContext": "Session summary saved to ${SUMMARY_FILE}. After compaction, read this file to restore working context. Monorepo root: ${MONO_ROOT:-none}"
}
HOOKJSON

exit 0
