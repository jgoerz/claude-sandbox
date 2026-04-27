#!/bin/bash
set -e

# Verify required commands are available
MISSING=()
for cmd in sudo cp touch; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING+=("$cmd")
  fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Error: required commands not found:"
  for cmd in "${MISSING[@]}"; do
    echo "  - $cmd"
  done
  exit 1
fi

# Bootstrap claude config from template if not already present
if [ ! -f /home/claude/.claude/settings.json ]; then
  echo "First run — bootstrapping ~/.claude from template..."
  cp -a /opt/claude-template/. /home/claude/.claude/
fi

# Bootstrap command history file if not already present
if [ ! -f /commandhistory/.bash_history ]; then
  echo "Initializing bash history..."
  touch /commandhistory/.bash_history
fi

SANDBOX_MODE="${SANDBOX_MODE:-code}"

if [ "$SANDBOX_MODE" = "research" ]; then
  # Safety check: refuse research mode if workspace contains a git repo
  if [ -d /workspace/.git ] || git -C /workspace rev-parse --git-dir >/dev/null 2>&1; then
    echo ""
    echo "ERROR: Research mode blocked — git repository detected in /workspace."
    echo ""
    echo "Research mode opens outbound network access. Running it on a"
    echo "directory containing a git repo risks exposing source code."
    echo ""
    echo "Either:"
    echo "  1. Use a directory without a git repo for research"
    echo "  2. Remove the --research flag to run in code mode (firewall enabled)"
    echo ""
    exit 1
  fi

  echo "=== RESEARCH MODE ==="
  echo "Outbound network: OPEN (no firewall)"
  echo "Workspace verified: no git repository detected"
  echo ""
else
  # Default: locked-down code mode
  echo "Initializing firewall..."
  sudo /usr/local/bin/init-firewall.sh
fi

# Execute the provided command (default: bash)
exec "$@"
