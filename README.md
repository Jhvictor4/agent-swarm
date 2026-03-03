# Agent Swarm 🐝

Lightweight orchestration for spawning multiple [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents in parallel — each in its own git worktree and tmux session.

Built for AI assistants (like [OpenClaw](https://openclaw.ai)) that need to delegate coding tasks to autonomous agents and monitor their progress.

## How It Works

```
Your AI Assistant (orchestrator)
  │
  ├── spawn-agent.sh  →  tmux session + git worktree + Claude Code
  ├── spawn-agent.sh  →  tmux session + git worktree + Claude Code
  │
  ├── check-agents.sh →  poll status, detect PRs, check CI
  └── cleanup.sh      →  remove finished worktrees + sessions
```

Each agent:
1. Gets its own **git worktree** (isolated branch, no conflicts)
2. Runs in a **tmux session** (detached, persistent)
3. Executes **Claude Code** with a prompt file (`-p`)
4. Optionally creates a **PR** when done

## Setup

```bash
git clone https://github.com/Jhvictor4/agent-swarm.git
cd agent-swarm

# Scripts are standalone — copy them wherever you want
chmod +x *.sh
```

**Requirements:** `tmux`, `jq`, `gh` (GitHub CLI), `claude` (Claude Code CLI)

## Usage

### Spawn an Agent

```bash
# Write a prompt
cat > /tmp/prompt.md << 'EOF'
Fix the login bug in src/auth.ts.
Write tests. Create a PR when done.
EOF

# Spawn
./spawn-agent.sh <task-id> <repo-path> <branch-name> <prompt-file> [model]
./spawn-agent.sh fix-login ~/my-app fix/login-bug /tmp/prompt.md claude-sonnet-4-20250514
```

### Check Status

```bash
./check-agents.sh
# Returns JSON: agent status, PR URLs, CI results
```

### Clean Up

```bash
./cleanup.sh
# Removes worktrees and tmux sessions for completed/failed tasks
```

### Monitor Directly

```bash
tmux attach -t agent-fix-login
```

## Configuration

| Env / Default | Description |
|---|---|
| `SWARM_DIR` | Task registry & logs (default: `~/.openclaw/workspace/.swarm`) |
| `WORKTREE_ROOT` | Where worktrees are created (default: `~/.openclaw/workspace/worktrees`) |
| Model param | `claude-sonnet-4-20250514` (default), `claude-opus-4-6` for complex tasks |

## Task Registry

`active-tasks.json` tracks all agents:

```json
[
  {
    "id": "fix-login",
    "tmuxSession": "agent-fix-login",
    "repo": "/Users/you/my-app",
    "branch": "fix/login-bug",
    "model": "claude-sonnet-4-20250514",
    "worktree": "/Users/you/.openclaw/workspace/worktrees/fix-login",
    "status": "running",
    "startedAt": 1709000000000
  }
]
```

Statuses: `running` → `pr_ready` / `completed_no_pr` / `crashed` → `done` / `failed` / `merged`

## OpenClaw Skill

Drop the included `SKILL.md` into your OpenClaw skills directory to use this as an agent skill.

## Constraints

- **Max 2-3 concurrent agents** recommended (RAM-bound on 16GB machines)
- Each worktree is a full copy — watch disk space on large repos
- Agents run with `--dangerously-skip-permissions` — use on trusted repos only

## License

MIT
