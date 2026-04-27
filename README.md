# Claude Sandbox

A sandboxed Docker environment for running Claude Code agents. Network-firewalled to only allow access to GitHub, Anthropic, and essential services.

## Prerequisites

- Docker (with Compose v2)
- `make`

## Quick Start

```bash
# Build the image (one time)
make build

# Start a container
make run

# Connect to it
make connect

# Inside the container, on first run:
claude login
```

On first run, the entrypoint bootstraps `~/.claude` from the baked-in template (settings, statusline, commands). Subsequent runs reuse the existing config — no re-login needed.

## Using in a Project

Use the `claude-sandbox-init` script to set up any directory:

```bash
# Symlink the script onto your PATH (preferred — stays in sync with `git pull`)
ln -sf "${PWD}/claude-sandbox-init" ~/bin

# Initialize the current directory
cd ~/my-project
claude-sandbox-init

# Or specify a target directory
claude-sandbox-init ~/my-project
```

This creates `claude/`, `commandhistory/`, `claude-sandbox-compose.yml`, and `claude-sandbox.mk`. If a `Makefile` already exists, an `include claude-sandbox.mk` block is appended; otherwise a one-line `Makefile` is created. Generated targets are prefixed with `sandbox-` (e.g. `sandbox-run`, `sandbox-connect`) so they never collide with project targets.

The script requires the `claude-sandbox` image to be built first. It auto-detects the repo location in this order: `$CLAUDE_SANDBOX_HOME`, the directory of the script (resolved through symlinks), then `$HOME/claude-sandbox`. Set `CLAUDE_SANDBOX_HOME` only if you cloned the repo somewhere unusual and didn't symlink the script.

## Running Multiple Agents with Worktrees

To run independent agents that can each commit without lock conflicts, give each its own git worktree:

```bash
# Create worktrees from your main repo
cd ~/my-project
git worktree add ../my-project-agent-1 -b agent-1
git worktree add ../my-project-agent-2 -b agent-2

# Initialize each worktree as a sandbox
claude-sandbox-init ~/my-project-agent-1
claude-sandbox-init ~/my-project-agent-2

# Start them (e.g. in separate tmux panes)
cd ~/my-project-agent-1 && make sandbox-run && make sandbox-connect
cd ~/my-project-agent-2 && make sandbox-run && make sandbox-connect
```

Each agent has its own worktree, branch, `claude/` config, and bash history. No lock contention, no state collisions.

## Directory Structure

```
claude-sandbox/                  # This repo — build the image here
├── Dockerfile
├── claude-sandbox-compose.yml   # Compose definition — used here for dev/testing
│                                #   AND copied into target projects by init
├── Makefile                     # build/run/connect/clean
├── claude-sandbox-init          # Setup script for project directories
├── entrypoint.sh                # First-run bootstrap + firewall init
├── init-firewall.sh             # Network allowlist
└── claude-template/             # Tracked — baked into image
    ├── settings.json            # Claude Code settings (statusline, etc.)
    ├── statusline-command.sh    # Custom statusline display
    ├── commands/                # Custom slash commands
    └── skills/                  # Custom skills (SKILL.md files)

~/my-project/                    # A project initialized with claude-sandbox-init
├── claude-sandbox-compose.yml   # Generated — references pre-built image
├── claude-sandbox.mk            # Generated — sandbox-run/sandbox-connect/...
├── Makefile                     # Created if missing, or has an
│                                #   `include claude-sandbox.mk` block appended
├── claude/                      # Gitignored — per-instance runtime state
│   ├── commands/                # Custom slash commands (from template)
│   ├── skills/                  # Custom skills (from template)
│   ├── settings.json            # Claude Code settings (from template)
│   └── ...                      # Credentials, sessions, etc. (created at runtime)
└── commandhistory/              # Gitignored — persistent bash history
```

## Firewall

The container starts with a restrictive iptables firewall. Allowed destinations:

- GitHub (all service IPs from their `/meta` endpoint)
- GitLab (`gitlab.com`, `registry.gitlab.com` — resolved via DNS)
- RubyGems (`rubygems.org`, `index.rubygems.org` + Fastly CDN ranges)
- `api.anthropic.com`
- `statsig.anthropic.com` / `statsig.com`
- `sentry.io`
- Localhost and host network (for port forwarding)

Everything else is blocked.

### Web Search

Claude Code's web search and `WebFetch` tools do not work inside the container — they require access to search providers and arbitrary URLs, which the firewall blocks by design.

The available options form a layered set, ordered from most-restrictive to least. **Pick the most restrictive layer that satisfies your need** — each step up trades sandbox isolation for capability.

1. **MCP proxy on the host** *(most restrictive — sandbox stays locked down)* — Run an MCP search server outside the container. The host network is already allowed, so Claude inside the container can reach it with no firewall changes. You control exactly which queries leave your machine and which results come back.
2. **Allowlist a specific search API** — Add a search provider (e.g. `api.search.brave.com`) to `init-firewall.sh` and rebuild the image. Claude gets search results but still cannot follow arbitrary result URLs.
3. **Open outbound HTTP/HTTPS** — Allow all outbound traffic on ports 80/443 in `init-firewall.sh` and rebuild. Claude can reach any HTTP(S) URL, but other protocols (SSH, raw TCP, etc.) remain blocked.
4. **Research mode (`make sandbox-run-research`)** *(least restrictive — convenience escape hatch)* — Skips firewall initialization entirely; outbound network is fully open. As a safety measure against code exfiltration, the container **refuses to start in research mode if `/workspace` is a git repository** (including worktrees, which share remotes, credentials, and hooks with their parent repo). Intended for ad-hoc research, scraping, or experiments in a scratch directory.

## Make Targets

### In this repo (build the image)

| Target    | Description                          |
|-----------|--------------------------------------|
| `build`   | Build the `claude-sandbox` image     |
| `run`     | Start the container in background    |
| `connect` | Attach a bash shell                  |
| `stop`    | Stop the container (keeps state)     |
| `destroy` | Remove the container (keeps image)   |
| `clean`   | Remove container and image           |
| `logs`    | Tail container logs                  |
| `status`  | Show container status                |

### In a project (generated by `claude-sandbox-init`)

| Target                 | Description                                          |
|------------------------|------------------------------------------------------|
| `sandbox-run`          | Start the sandbox in code mode (firewall enabled)    |
| `sandbox-run-research` | Start in research mode (open network)                |
| `sandbox-connect`      | Attach a bash shell                                  |
| `sandbox-stop`         | Stop the sandbox (keeps state)                       |
| `sandbox-destroy`      | Remove the sandbox container                         |
| `sandbox-status`       | Show container status                                |
| `sandbox-help`         | List sandbox targets                                 |

## Customizing the Template

Edit files in `claude-template/` and rebuild the image. Changes take effect for new `claude/` directories (existing ones are not overwritten).

### Adding Custom Slash Commands

Place markdown files in `claude-template/commands/` to make them available as `/command-name` inside Claude Code:

```bash
cat > claude-template/commands/review.md << 'EOF'
Review the current diff for bugs, security issues, and style problems.
Focus on logic errors and edge cases. Be concise.
EOF
```

### Adding Custom Skills

Skills live in `claude-template/skills/{skill-name}/SKILL.md`:

```bash
mkdir -p claude-template/skills/code-review
cat > claude-template/skills/code-review/SKILL.md << 'EOF'
---
name: code-review
description: Review code for bugs, security issues, and style
---

Review the current diff. Focus on:
- Logic errors and edge cases
- Security vulnerabilities
- Style consistency
EOF
```

After adding commands or skills, rebuild the image:

```bash
make build
```

For an existing sandbox, copy files directly without rebuilding:

```bash
# Slash command
cp claude-template/commands/review.md ~/my-project/claude/commands/

# Skill
cp -r claude-template/skills/code-review ~/my-project/claude/skills/
```
