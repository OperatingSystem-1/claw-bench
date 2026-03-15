#!/bin/bash
# Pre-compact hook: comprehensive work context capture before compaction
# Captures: tasks, TODOs, shell history, env state, test results, diffs, decisions
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

# Extract decision log from memory files (Why: sections)
decision_log() {
  (
    cd "$1" || return
    if [ ! -d ".claude/projects/-Users-almorris-OS-1/memory" ]; then
      return
    fi

    local mem_dir=".claude/projects/-Users-almorris-OS-1/memory"
    local decisions
    decisions=$(find "$mem_dir" -name '*.md' -type f -exec grep -l "Why:" {} \; 2>/dev/null | head -3)

    if [ -n "$decisions" ]; then
      echo "**Recent decisions (Why sections):**"
      echo ""
      while IFS= read -r file; do
        local name=$(basename "$file")
        echo "- **$name:**"
        grep -A 2 "^\*\*Why:" "$file" 2>/dev/null | head -3 | sed 's/^/  /'
      done <<< "$decisions"
      echo ""
    fi
  )
}

# Extract TODOs, FIXMEs, XXXs from recently modified files
extract_todos() {
  (
    cd "$1" || return
    local recent_files
    recent_files=$(git diff --name-only HEAD~5..HEAD 2>/dev/null)

    if [ -z "$recent_files" ]; then
      return
    fi

    local todos
    todos=$(echo "$recent_files" | while read -r file; do
      [ -f "$file" ] && grep -Hn 'TODO\|FIXME\|XXX' "$file" 2>/dev/null || true
    done | head -10)

    if [ -n "$todos" ]; then
      echo "**TODOs/FIXMEs in recent files:**"
      echo "\`\`\`"
      echo "$todos"
      echo "\`\`\`"
      echo ""
    fi
  )
}

# Show environment state: running services, ports, processes
env_state() {
  (
    cd "$1" || return

    echo "**Environment State:**"
    echo ""

    # Check if we're in the monorepo and show dev status
    if [ -f "Makefile" ] && grep -q "dev:" Makefile 2>/dev/null; then
      echo "- **Development status:**"
      if pgrep -f "npm run dev" >/dev/null 2>&1; then
        echo "  - npm dev: ✓ running"
      else
        echo "  - npm dev: ✗ not running"
      fi

      if pgrep -f "kind" >/dev/null 2>&1; then
        echo "  - KIND cluster: ✓ running"
      else
        echo "  - KIND cluster: ✗ not running"
      fi

      echo ""
    fi

    # Show open ports that might matter
    echo "- **Open ports (dev-related):**"
    for port in 3000 18789 5432 4300 8080 9090; do
      if lsof -i :"$port" >/dev/null 2>&1; then
        local proc=$(lsof -i :"$port" -n -P 2>/dev/null | awk 'NR==2 {print $1}')
        echo "  - $port: $proc"
      fi
    done
    echo ""
  )
}

# Show branch status and unpushed commits
branch_status() {
  (
    cd "$1" || return
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")

    echo "**Branch Status:**"
    echo "- **Current:** \`$branch\`"

    # Check for unpushed commits
    local unpushed
    unpushed=$(git log @{u}..HEAD --oneline 2>/dev/null | wc -l)
    if [ "$unpushed" -gt 0 ]; then
      echo "- **Unpushed commits:** $unpushed"
    fi

    # Check for commits ahead/behind main
    local main_distance
    main_distance=$(git rev-list --left-right --count main...HEAD 2>/dev/null || echo "0 0")
    local behind=$(echo "$main_distance" | awk '{print $1}')
    local ahead=$(echo "$main_distance" | awk '{print $2}')

    if [ "$behind" != "0" ] || [ "$ahead" != "0" ]; then
      echo "- **vs main:** behind $behind, ahead $ahead"
    fi
    echo ""
  )
}

# Show recent shell commands (history of what was run)
shell_history() {
  local history_file
  if [ -f "$HOME/.zsh_history" ]; then
    history_file="$HOME/.zsh_history"
  elif [ -f "$HOME/.bash_history" ]; then
    history_file="$HOME/.bash_history"
  else
    return
  fi

  echo "**Recent commands (last 15):**"
  echo "\`\`\`"
  # Extract command from zsh history format: : timestamp:0;command
  # Fallback to just showing last 15 lines
  if [ -f "$history_file" ]; then
    tail -30 "$history_file" 2>/dev/null | \
      sed -n 's/^: [0-9]*:[0-9]*;//p' | \
      head -15
  fi
  echo "\`\`\`"
  echo ""
}

# Show diffs for critical files (not just stats)
critical_diffs() {
  (
    cd "$1" || return
    local critical=("Makefile" "scripts/dev-startup-check.sh" "website/CLAUDE.md" ".claude/hooks/pre-compact-save.sh")

    local has_changes=false
    for file in "${critical[@]}"; do
      if git diff --quiet HEAD -- "$file" 2>/dev/null; then
        continue
      fi
      has_changes=true
      break
    done

    if [ "$has_changes" = false ]; then
      return
    fi

    echo "**Changes in critical files:**"
    echo ""

    for file in "${critical[@]}"; do
      if [ ! -f "$file" ]; then
        continue
      fi

      if ! git diff --quiet HEAD -- "$file" 2>/dev/null; then
        echo "**\`$file\`:**"
        echo "\`\`\`diff"
        git diff HEAD -- "$file" 2>/dev/null | head -30
        if [ $(git diff HEAD -- "$file" 2>/dev/null | wc -l) -gt 30 ]; then
          echo "... (truncated)"
        fi
        echo "\`\`\`"
        echo ""
      fi
    done
  )
}

# Show active/pending tasks if using task system
active_tasks() {
  local tasks_dir="${PROJECT_DIR}/.claude/tasks"
  if [ ! -d "$tasks_dir" ]; then
    return
  fi

  local pending_tasks
  pending_tasks=$(find "$tasks_dir" -name '*.json' -type f 2>/dev/null | xargs grep -l '"status":"pending"' 2>/dev/null | wc -l)
  local in_progress
  in_progress=$(find "$tasks_dir" -name '*.json' -type f 2>/dev/null | xargs grep -l '"status":"in_progress"' 2>/dev/null | wc -l)

  if [ "$pending_tasks" -gt 0 ] || [ "$in_progress" -gt 0 ]; then
    echo "**Active Tasks:**"
    echo "- Pending: $pending_tasks"
    echo "- In progress: $in_progress"
    echo ""
  fi
}

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

# Extract context from recent commit messages, changed files, and memory
work_context() {
  (
    cd "$1" || return

    # Look for recent TODOs/notes in memory
    if [ -d ".claude/projects" ] && [ -d ".claude/projects/-Users-almorris-OS-1/memory" ]; then
      local mem_dir=".claude/projects/-Users-almorris-OS-1/memory"
      local latest_mem
      latest_mem=$(find "$mem_dir" -name '*.md' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
      if [ -n "$latest_mem" ]; then
        echo "**Latest memory file:** \`$(basename "$latest_mem")\`"
        echo ""
        head -8 "$latest_mem" | grep -E '^(name|description)' | sed 's/^/  /'
        echo ""
      fi
    fi

    # Infer work from recent commits (last 3)
    echo "**Recent changes:**"
    echo "\`\`\`"
    git log --oneline -3 --format="%h %s" 2>/dev/null | while read -r line; do
      echo "$line"
    done
    echo "\`\`\`"
    echo ""
  )
}

# Show files modified + git diff summary to understand what changed
changed_with_context() {
  (
    cd "$1" || return

    local changed
    changed=$(git status --short 2>/dev/null | head -10)
    if [ -z "$changed" ]; then
      return
    fi

    echo "**Modified files with context:**"
    echo ""

    # Show each changed file with its git diff --stat
    echo "$changed" | while read -r status file; do
      case "$status" in
        M*)  echo "**Modified:** \`$file\`" ;;
        A*)  echo "**Added:** \`$file\`" ;;
        D*)  echo "**Deleted:** \`$file\`" ;;
        *) echo "**Changed ($status):** \`$file\`" ;;
      esac

      # For modified files, show a brief diff stat
      if [ "$status" != "D" ]; then
        if git diff --stat HEAD -- "$file" 2>/dev/null | tail -1 | grep -qE '^\s'; then
          git diff --stat HEAD -- "$file" 2>/dev/null | tail -1 | sed 's/^/  /'
        fi
      fi
    done
    echo ""
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

## Quick Navigation (Priority Order)

**Fastest way to restore context:**
1. **Active Tasks** — What's currently assigned?
2. **Recent Decisions** — Why were things done this way?
3. **TODOs/FIXMEs** — What's still pending?
4. **Environment** — What's currently running?
5. **Branch Status** — What's uncommitted/unpushed?
6. **Shell History** — What was I testing?
7. **Recent Changes** — Actual diffs of critical files
8. **Memory Files** — Full context: \`cat .claude/projects/-Users-almorris-OS-1/memory/MEMORY.md\`

**For full recovery:** Read sections in order. Each builds on the previous.

---

## Task Status

HEADER

  active_tasks

  cat << DECISIONS
## Recent Decisions

DECISIONS

  decision_log "$PROJECT_DIR"

  cat << TODOS
## Pending Work

TODOS

  extract_todos "$PROJECT_DIR"

  cat << ENV
## Environment

ENV

  env_state "$PROJECT_DIR"

  cat << BRANCH
## Branch Status

BRANCH

  branch_status "$PROJECT_DIR"

  cat << HISTORY
## What Was Being Tested

HISTORY

  shell_history

  cat << CRITICAL
## Recent Code Changes

CRITICAL

  critical_diffs "$PROJECT_DIR"

  cat << GIT
## Full Git State

GIT

  work_context "$PROJECT_DIR"
  changed_with_context "$PROJECT_DIR"
  repo_state "$PROJECT_DIR" "$(basename "$PROJECT_DIR")"

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
