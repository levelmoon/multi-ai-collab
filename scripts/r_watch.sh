#!/bin/bash
# R 端事件监听器。跑在 E 主机上,每次有意义的事发生就 emit 一行 stdout,
# R 的 harness 接事件唤醒,而不是定时轮询。
#
# 会 emit 的事件:
#   R_WATCH_START <时间> baseline_head=<sha>
#   COMMIT_NEW <oneline>          —— git HEAD 移动
#   QUESTION_FILE <path>          —— step-*-question.md 首次出现
#   HALT_FLAG                     —— handoff/.halt 首次出现
#   E_IDLE no new activity <N>s   —— IDLE_TIMEOUT_SEC 内没新东西
#
# 改顶上两行路径成你项目的,丢到 /tmp/,R 端这么接:
#   while true; do
#     ssh -o ServerAliveInterval=30 user@E_HOST "bash /tmp/r_watch.sh" 2>&1
#     echo "SSH_DROPPED reconnecting"; sleep 5
#   done
#
# 每行非噪声 stdout 都变成 R harness 的一次唤醒。
# 心跳写到 /tmp/r_heartbeat 每轮更新,人可以随时 cat 一眼确认监听还活着。

set -u

# === 改这两行 ===
WORKSPACE=${WORKSPACE:-/path/to/your/workspace}
LOG_DIR=${LOG_DIR:-$WORKSPACE/logs}   # 你项目里 E 持续产出新东西的目录
# ================

IDLE_TIMEOUT_SEC=${IDLE_TIMEOUT_SEC:-1200}   # 20 分钟
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

  # 新 commit?
  HEAD=$(git log --oneline -1 2>/dev/null)
  if [ -n "$HEAD" ] && [ "$HEAD" != "$LAST_HEAD" ]; then
    LAST_HEAD="$HEAD"
    echo "COMMIT_NEW $HEAD"
  fi

  # question 文件出现?(去重,只在首次出现时报一次)
  Q=$(ls "$HANDOFF"/step-*-question.md 2>/dev/null | head -1)
  if [ -n "$Q" ]; then
    [ "$Q_SEEN" -eq 0 ] && { Q_SEEN=1; echo "QUESTION_FILE $Q"; }
  else
    Q_SEEN=0
  fi

  # halt 标志出现?(去重)
  if [ -f "$HANDOFF/.halt" ]; then
    [ "$HALT_SEEN" -eq 0 ] && { HALT_SEEN=1; echo "HALT_FLAG"; }
  else
    HALT_SEEN=0
  fi

  # LOG_DIR 有新活动? 或长时间无活动?
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
