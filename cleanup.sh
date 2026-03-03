#!/bin/bash
# cleanup.sh — Clean up completed/failed agent worktrees
set -euo pipefail

SWARM_DIR="$HOME/.openclaw/workspace/.swarm"
TASKS_FILE="$SWARM_DIR/active-tasks.json"

if [ ! -f "$TASKS_FILE" ]; then exit 0; fi

CLEANED=0
while IFS= read -r task; do
  STATUS=$(echo "$task" | jq -r '.status')
  TASK_ID=$(echo "$task" | jq -r '.id')
  TMUX_SESSION=$(echo "$task" | jq -r '.tmuxSession')
  WORKTREE=$(echo "$task" | jq -r '.worktree')
  REPO=$(echo "$task" | jq -r '.repo // empty')

  if [ "$STATUS" = "done" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "merged" ]; then
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    if [ -n "$REPO" ] && [ -d "$REPO" ]; then
      cd "$REPO"
      git worktree remove "$WORKTREE" --force 2>/dev/null || true
    fi
    CLEANED=$((CLEANED + 1))
  fi
done < <(jq -c '.[]' "$TASKS_FILE")

# Remove cleaned tasks from registry
jq '[.[] | select(.status != "done" and .status != "failed" and .status != "merged")]' "$TASKS_FILE" > /tmp/tasks-clean.json
mv /tmp/tasks-clean.json "$TASKS_FILE"

echo "Cleaned $CLEANED agent(s)"
