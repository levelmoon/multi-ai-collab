#!/bin/bash
# R event detector. Runs on E's host. Emits one stdout line per meaningful
# event so R's harness can wake on it instead of polling on a timer.
#
# Events emitted:
#   R_WATCH_START <time> baseline_head=<sha>
#   COMMIT_NEW <oneline>          when git HEAD moves
#   QUESTION_FILE <path>          when step-*-question.md first appears
#   HALT_FLAG                     when handoff/.halt first appears
#   E_IDLE no new probe <N>s      when nothing new for IDLE_TIMEOUT_SEC
#
# Configure the two paths at the top to your project, drop to /tmp/, then
# wire R-side as:
#   while true; do
#     ssh -o ServerAliveInterval=30 user@E_HOST "bash /tmp/r_watch.sh" 2>&1
#     echo "SSH_DROPPED reconnecting"; sleep 5
#   done
#
# Each non-noise stdout line becomes a wake-up event in R's harness.
# Heartbeat is written to /tmp/r_heartbeat every loop so the human can
# verify the watcher is alive: cat /tmp/r_heartbeat

set -u

# === EDIT THESE TWO ===
WORKSPACE=${WORKSPACE:-/path/to/your/workspace}
LOG_DIR=${LOG_DIR:-$WORKSPACE/logs}   # whichever dir E drops fresh artifacts in
# ======================

IDLE_TIMEOUT_SEC=${IDLE_TIMEOUT_SEC:-1200}   # 20 min
LOOP_SLEEP_SEC=${LOOP_SLEEP_SEC:-30}

HANDOFF="$WORKSPACE/handoff"

cd "$WORKSPACE" 2>/dev/null || { echo "WORKSPACE_NOT_FOUND $WORKSPACE"; exit 1; }

LAST_HEAD=$(git log --oneline -1 2>/dev/null)
LAST_PROBE=$(ls -t "$LOG_DIR" 2>/dev/null | head -1)
LAST_PROBE_TS=$(date +%s)
IDLE_NOTIFIED=0
Q_SEEN=0
HALT_SEEN=0

echo "R_WATCH_START $(date +%H:%M:%S) baseline_head=$LAST_HEAD"

while true; do
  echo "R-monitor alive $(date +%H:%M:%S) pid=$$" > /tmp/r_heartbeat 2>/dev/null

  # New commit?
  HEAD=$(git log --oneline -1 2>/dev/null)
  if [ -n "$HEAD" ] && [ "$HEAD" != "$LAST_HEAD" ]; then
    LAST_HEAD="$HEAD"
    echo "COMMIT_NEW $HEAD"
  fi

  # Question file appeared? (dedupe — emit once per appearance)
  Q=$(ls "$HANDOFF"/step-*-question.md 2>/dev/null | head -1)
  if [ -n "$Q" ]; then
    [ "$Q_SEEN" -eq 0 ] && { Q_SEEN=1; echo "QUESTION_FILE $Q"; }
  else
    Q_SEEN=0
  fi

  # Halt flag appeared? (dedupe)
  if [ -f "$HANDOFF/.halt" ]; then
    [ "$HALT_SEEN" -eq 0 ] && { HALT_SEEN=1; echo "HALT_FLAG"; }
  else
    HALT_SEEN=0
  fi

  # New activity in LOG_DIR, or extended idle?
  NEWP=$(ls -t "$LOG_DIR" 2>/dev/null | head -1)
  NOW=$(date +%s)
  if [ "$NEWP" != "$LAST_PROBE" ]; then
    LAST_PROBE="$NEWP"
    LAST_PROBE_TS=$NOW
    IDLE_NOTIFIED=0
  else
    GAP=$((NOW - LAST_PROBE_TS))
    if [ "$GAP" -gt "$IDLE_TIMEOUT_SEC" ] && [ "$IDLE_NOTIFIED" -eq 0 ]; then
      IDLE_NOTIFIED=1
      echo "E_IDLE no new activity ${GAP}s"
    fi
  fi

  sleep "$LOOP_SLEEP_SEC"
done
