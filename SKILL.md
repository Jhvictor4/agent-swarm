# Agent Swarm — Coding Agent Orchestration

## Overview
Spawn, monitor, and manage multiple Claude Code agents running in parallel.
Each agent gets its own git worktree + tmux session.

## Directory
- `spawn-agent.sh` — Spawn an agent (worktree + tmux + Claude Code)
- `check-agents.sh` — Poll status of all agents (JSON output)
- `cleanup.sh` — Remove completed agent worktrees + sessions
- `active-tasks.json` — Task registry (auto-managed)
- `logs/<task-id>.log` — Agent output logs

## Workflow

### 1. Spawn
1. Write a prompt file to `/tmp/prompt-<task-id>.md` with:
   - Specific requirements
   - Relevant file paths
   - How to test
   - "Create a PR when done" instruction
2. Run: `spawn-agent.sh <task-id> <repo-path> <branch-name> <prompt-file> [model]`

### 2. Monitor
- `check-agents.sh` → JSON with status, PR URLs, CI results
- `tmux attach -t agent-<task-id>` for live view
- `tmux send-keys -t agent-<task-id> "..." Enter` to give instructions

### 3. Complete
- Agent finishes → status becomes `pr_ready` or `completed_no_pr`
- Review PR, merge
- `cleanup.sh` removes worktrees for done/failed/merged tasks

## Constraints
- Max 2-3 concurrent agents (16GB RAM limit)
- Default model: `claude-sonnet-4-20250514` (fast, cheap)
- Complex tasks: `claude-opus-4-6`
