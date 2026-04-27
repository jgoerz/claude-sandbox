#!/usr/bin/env bash
# Claude Code statusLine command — mirrors ~/.bashrc PS1
# Input: JSON via stdin

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# ANSI colors (dimmed by the terminal, as noted in statusLine docs)
cyan='\033[0;36m'
green='\033[0;32m'
yellow='\033[0;33m'
reset='\033[0m'

# Git branch from the cwd (skip optional locks to avoid contention)
# Collapse $HOME to ~
cwd="${cwd/#$HOME/\~}"

git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

if [ -n "$git_branch" ]; then
  printf "[${cyan}%s@%s${reset} %s${green} (%s)${reset}]" \
    "$(whoami)" "$(hostname -s)" "$cwd" "$git_branch"
  # printf "[%s ${green}(%s)${reset}]" "$cwd" "$git_branch"
else
  printf "[${cyan}%s@%s${reset} %s]" \
    "$(whoami)" "$(hostname -s)" "$cwd"
  # printf "[%s]" "$cwd"
fi

# Claude CLI version
claude_ver=$(claude --version 2>/dev/null | head -1)

# Append model, context usage, and version on the right
if [ -n "$model" ]; then
  if [ -n "$used_pct" ]; then
    printf " ${yellow}[%s ctx:%s%%]${reset}" "$model" "$(printf '%.0f' "$used_pct")"
  else
    printf " ${yellow}[%s]${reset}" "$model"
  fi
fi

if [ -n "$claude_ver" ]; then
  printf " ${cyan}v%s${reset}" "$claude_ver"
fi
