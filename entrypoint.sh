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

# Run firewall setup (equivalent to devcontainer postCreateCommand)
echo "Initializing firewall..."
sudo /usr/local/bin/init-firewall.sh

# Execute the provided command (default: bash)
exec "$@"
