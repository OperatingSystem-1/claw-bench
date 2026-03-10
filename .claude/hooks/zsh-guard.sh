#!/bin/bash
# ZSH Guard - Blocks bash commands that will break zsh
# Hook: PreToolUse (matcher: Bash)

# Read the tool input from stdin
INPUT=$(cat)

# Extract the command from JSON input
COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"command"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

# Check for the forbidden pattern: export VAR=value followed by a command
# Pattern: export followed by VAR=value followed by something that looks like a command
if echo "$COMMAND" | grep -qE '^[[:space:]]*(export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+[a-zA-Z])'; then
    echo "BLOCKED: export VAR=value command"
    echo ""
    echo "ZSH GUARD: This command will break zsh!"
    echo ""
    echo "BAD:  export VAR=value command"
    echo "GOOD: VAR=value command"
    echo ""
    echo "Rewrite without 'export' keyword for inline env vars."
    exit 2
fi

# Allow the command
exit 0
