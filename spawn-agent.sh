#!/bin/bash
# spawn-agent.sh — Spawn a Claude Code agent in its own worktree + tmux session
# Usage: spawn-agent.sh <task-id> <repo-path> <branch-name> <prompt-file> [model]
#
# Example:
#   spawn-agent.sh feat-templates ~/project-geo feat/custom-templates /tmp/prompt.md claude-sonnet-4-20250514
#   spawn-agent.sh fix-bug ~/other-repo fix/login-bug /tmp/prompt.md claude-opus-4-6

set -euo pipefail

SWARM_DIR="$HOME/.openclaw/workspace/.swarm"
WORKTREE_ROOT="$HOME/.openclaw/workspace/worktrees"
TASK_ID="${1:?Usage: spawn-agent.sh <task-id> <repo-path> <branch-name> <prompt-file> [model]}"
REPO_PATH="${2:?Missing repo path}"
BRANCH="${3:?Missing branch name}"
PROMPT_FILE="${4:?Missing prompt file}"
MODEL="${5:-claude-sonnet-4-20250514}"
TMUX_SESSION="agent-${TASK_ID}"

# Resolve repo path
REPO_PATH=$(cd "$REPO_PATH" && pwd)
REPO_NAME=$(basename "$REPO_PATH")

mkdir -p "$WORKTREE_ROOT" "$SWARM_DIR/logs"

# Create worktree from main
cd "$REPO_PATH"
git fetch origin main 2>/dev/null || true
git worktree add "$WORKTREE_ROOT/$TASK_ID" -b "$BRANCH" origin/main 2>/dev/null || {
  echo "Worktree or branch already exists, reusing..."
  cd "$WORKTREE_ROOT/$TASK_ID" 2>/dev/null || {
    echo "ERROR: Cannot access worktree dir"
    exit 1
  }
  git checkout "$BRANCH" 2>/dev/null || true
}

WORKDIR="$WORKTREE_ROOT/$TASK_ID"

# Install deps if package.json exists
cd "$WORKDIR"
if [ -f "package.json" ]; then
  if [ -f "pnpm-lock.yaml" ]; then
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install 2>/dev/null || true
  elif [ -f "yarn.lock" ]; then
    yarn install --frozen-lockfile 2>/dev/null || true
  else
    npm ci 2>/dev/null || npm install 2>/dev/null || true
  fi
fi

# Launch claude in tmux (source shell profile for PATH)
CLAUDE_BIN=$(which claude)
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" -c "$WORKDIR" \
  "export PATH=\"/opt/homebrew/bin:/usr/local/bin:\$PATH\"; $CLAUDE_BIN --model $MODEL --dangerously-skip-permissions -p \"\$(cat '$PROMPT_FILE')\" 2>&1 | tee $SWARM_DIR/logs/${TASK_ID}.log; echo 'AGENT_DONE' >> $SWARM_DIR/logs/${TASK_ID}.log"

# Register task
TASK_JSON=$(cat <<EOF
{
  "id": "$TASK_ID",
  "tmuxSession": "$TMUX_SESSION",
  "repo": "$REPO_PATH",
  "repoName": "$REPO_NAME",
  "branch": "$BRANCH",
  "model": "$MODEL",
  "worktree": "$WORKDIR",
  "promptFile": "$PROMPT_FILE",
  "startedAt": $(date +%s)000,
  "status": "running"
}
EOF
)

# Append to active-tasks.json
TASKS_FILE="$SWARM_DIR/active-tasks.json"
if [ ! -f "$TASKS_FILE" ] || [ "$(cat "$TASKS_FILE")" = "" ]; then
  echo "[]" > "$TASKS_FILE"
fi
TMP=$(mktemp)
jq --argjson task "$TASK_JSON" '. + [$task]' "$TASKS_FILE" > "$TMP" && mv "$TMP" "$TASKS_FILE"

echo "✅ Agent spawned: $TMUX_SESSION"
echo "   Repo: $REPO_NAME ($REPO_PATH)"
echo "   Worktree: $WORKDIR"
echo "   Branch: $BRANCH"
echo "   Model: $MODEL"
echo "   Monitor: tmux attach -t $TMUX_SESSION"
