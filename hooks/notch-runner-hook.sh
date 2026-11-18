#!/bin/bash
# Usage: notch-runner-hook.sh <event>   (prompt | stop | end)
#
# Called by Claude Code hooks. Must ALWAYS exit 0 quickly and must never print
# to stdout: UserPromptSubmit stdout is appended to Claude's context.
EVENT="$1"
DIR="$HOME/.notch-runner"
PORT="$(cat "$DIR/port" 2>/dev/null || echo 47811)"
TOKEN="$(cat "$DIR/token" 2>/dev/null)"
INPUT="$(cat)"                                  # hook JSON from Claude Code
TTY="$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
PAYLOAD=$(printf '{"event":"%s","tty":"%s","term":"%s","termSession":"%s","itermSession":"%s","entrypoint":"%s","hook":%s}' \
  "$EVENT" "$TTY" "${TERM_PROGRAM:-}" "${TERM_SESSION_ID:-}" "${ITERM_SESSION_ID:-}" "${CLAUDE_CODE_ENTRYPOINT:-}" "${INPUT:-{\}}")
curl -s -m 1 -o /dev/null -X POST "http://127.0.0.1:$PORT/event" \
  -H "Content-Type: application/json" -H "X-NR-Token: $TOKEN" --data-binary "$PAYLOAD" >/dev/null 2>&1 &
exit 0
