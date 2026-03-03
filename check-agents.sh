#!/bin/bash
# check-agents.sh — Check status of all running agents (multi-repo)
# Outputs JSON summary for Kith to parse

set -euo pipefail

SWARM_DIR="$HOME/.openclaw/workspace/.swarm"
TASKS_FILE="$SWARM_DIR/active-tasks.json"

if [ ! -f "$TASKS_FILE" ] || [ "$(cat "$TASKS_FILE")" = "[]" ]; then
  echo '{"agents":[],"summary":"No active agents"}'
  exit 0
fi

RESULTS="[]"

while IFS= read -r task; do
  TASK_ID=$(echo "$task" | jq -r '.id')
  TMUX_SESSION=$(echo "$task" | jq -r '.tmuxSession')
  BRANCH=$(echo "$task" | jq -r '.branch')
  REPO=$(echo "$task" | jq -r '.repo // empty')
  STATUS=$(echo "$task" | jq -r '.status')

  # Skip already completed
  if [ "$STATUS" = "done" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "merged" ]; then
    RESULTS=$(echo "$RESULTS" | jq --argjson t "$task" '. + [$t]')
    continue
  fi

  # Check tmux session alive
  TMUX_ALIVE="false"
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null && TMUX_ALIVE="true"

  # Check if agent log says DONE
  AGENT_DONE="false"
  LOG_FILE="$SWARM_DIR/logs/${TASK_ID}.log"
  if [ -f "$LOG_FILE" ] && grep -q "AGENT_DONE" "$LOG_FILE"; then
    AGENT_DONE="true"
  fi

  # Check for PR (use repo dir for gh context)
  PR_URL=""
  PR_NUM=""
  if [ -n "$REPO" ] && [ -d "$REPO" ]; then
    cd "$REPO" 2>/dev/null
  fi
  PR_INFO=$(gh pr list --head "$BRANCH" --json number,url,state 2>/dev/null || echo "[]")
  if [ "$PR_INFO" != "[]" ]; then
    PR_NUM=$(echo "$PR_INFO" | jq -r '.[0].number // empty')
    PR_URL=$(echo "$PR_INFO" | jq -r '.[0].url // empty')
  fi

  # Check CI status
  CI_STATUS="unknown"
  if [ -n "$PR_NUM" ]; then
    CI_STATUS=$(gh pr checks "$PR_NUM" --json state --jq '.[].state' 2>/dev/null | sort -u | tr '\n' ',' || echo "unknown")
  fi

  # Determine new status
  NEW_STATUS="$STATUS"
  if [ "$AGENT_DONE" = "true" ] && [ -n "$PR_NUM" ]; then
    NEW_STATUS="pr_ready"
  elif [ "$AGENT_DONE" = "true" ]; then
    NEW_STATUS="completed_no_pr"
  elif [ "$TMUX_ALIVE" = "false" ]; then
    NEW_STATUS="crashed"
  fi

  RESULT=$(echo "$task" | jq \
    --arg status "$NEW_STATUS" \
    --arg tmux_alive "$TMUX_ALIVE" \
    --arg pr_url "$PR_URL" \
    --arg pr_num "$PR_NUM" \
    --arg ci "$CI_STATUS" \
    '. + {status: $status, tmuxAlive: ($tmux_alive == "true"), prUrl: $pr_url, prNum: $pr_num, ciStatus: $ci}')

  RESULTS=$(echo "$RESULTS" | jq --argjson r "$RESULT" '. + [$r]')
done < <(jq -c '.[]' "$TASKS_FILE")

# Count by status
RUNNING=$(echo "$RESULTS" | jq '[.[] | select(.status == "running")] | length')
PR_READY=$(echo "$RESULTS" | jq '[.[] | select(.status == "pr_ready")] | length')
CRASHED=$(echo "$RESULTS" | jq '[.[] | select(.status == "crashed")] | length')

echo "$RESULTS" | jq --arg r "$RUNNING" --arg p "$PR_READY" --arg c "$CRASHED" \
  '{agents: ., summary: "Running: \($r), PR Ready: \($p), Crashed: \($c)"}'

# Update tasks file with new statuses
echo "$RESULTS" | jq '.' > "$TASKS_FILE"
