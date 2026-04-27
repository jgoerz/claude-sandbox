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
# Install the script somewhere on your PATH
cp ~/devops/claude-sandbox/claude-sandbox-init ~/bin/

# Initialize the current directory
cd ~/my-project
claude-sandbox-init

# Or specify a target directory
claude-sandbox-init ~/my-project
```

This creates `claude/`, `commandhistory/`, a `docker-compose.yml`, and a `Makefile` with `run`, `connect`, `stop`, and `destroy` targets.

The script requires the `claude-sandbox` image to be built first. Set `CLAUDE_SANDBOX_HOME` if the repo lives somewhere other than `~/devops/claude-sandbox`.

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
cd ~/my-project-agent-1 && make run && make connect
cd ~/my-project-agent-2 && make run && make connect
```

Each agent has its own worktree, branch, `claude/` config, and bash history. No lock contention, no state collisions.

## Directory Structure

```
claude-sandbox/                  # This repo — build the image here
├── Dockerfile
├── docker-compose.yml           # For local dev/testing of the image
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
├── docker-compose.yml           # Generated — references pre-built image
├── Makefile                     # Generated — run/connect/stop/destroy
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

If you need web search capability:

1. **MCP proxy on the host** — Run an MCP search server outside the container. The host network is already allowed, so Claude inside the container can reach it with no firewall changes. This keeps the sandbox locked down while providing controlled search access.
2. **Allowlist a search API** — Add a specific search provider (e.g. `api.search.brave.com`) to `init-firewall.sh`. Claude gets search results but still cannot follow arbitrary result URLs.
3. **Open outbound HTTP/HTTPS** — Allow all outbound traffic on ports 80/443. This works but largely defeats the purpose of the firewall.

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

| Target    | Description                          |
|-----------|--------------------------------------|
| `run`     | Start the sandbox in background      |
| `connect` | Attach a bash shell                  |
| `stop`    | Stop the sandbox (keeps state)       |
| `destroy` | Remove the sandbox container         |
| `status`  | Show container status                |

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
