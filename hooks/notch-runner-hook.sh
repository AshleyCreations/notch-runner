#!/bin/bash
# Usage: notch-runner-hook.sh <event>   (prompt | stop | end)
#
# Called by Claude Code hooks. Must ALWAYS exit quickly and must never print to
# stdout: UserPromptSubmit stdout is appended to Claude's context.
EVENT="$1"
DIR="$HOME/.notch-runner"
PORT="$(cat "$DIR/port" 2>/dev/null || echo 47811)"
TOKEN="$(cat "$DIR/token" 2>/dev/null)"
INPUT="$(cat)"                                  # hook JSON from Claude Code
TTY="$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# "/playbot" opens the island by hand, with no work for Claude to do. The
# prompt is matched HERE and never forwarded: only the fact that it matched
# leaves this script. A plain grep, so the common case costs nothing.
PLAY=0
if [ "$EVENT" = "prompt" ] &&
   printf '%s' "$INPUT" | grep -Eq '"prompt"[[:space:]]*:[[:space:]]*"/playbot[[:space:]]*"'; then
  EVENT="play"
  PLAY=1
fi

PAYLOAD=$(printf '{"event":"%s","tty":"%s","term":"%s","termSession":"%s","itermSession":"%s","entrypoint":"%s","hook":%s}' \
  "$EVENT" "$TTY" "${TERM_PROGRAM:-}" "${TERM_SESSION_ID:-}" "${ITERM_SESSION_ID:-}" "${CLAUDE_CODE_ENTRYPOINT:-}" "${INPUT:-{\}}")

if [ "$PLAY" = "1" ]; then
  # Deliver before exiting, so the island is already on its way up. Exit 2
  # blocks the prompt, so Claude never sees "/playbot" at all, and stderr is
  # shown to the user.
  curl -s -m 1 -o /dev/null -X POST "http://127.0.0.1:$PORT/event" \
    -H "Content-Type: application/json" -H "X-NR-Token: $TOKEN" --data-binary "$PAYLOAD" >/dev/null 2>&1
  echo "Notch Runner: island open. Esc Esc, Cmd+W or the x closes it." >&2
  exit 2
fi

curl -s -m 1 -o /dev/null -X POST "http://127.0.0.1:$PORT/event" \
  -H "Content-Type: application/json" -H "X-NR-Token: $TOKEN" --data-binary "$PAYLOAD" >/dev/null 2>&1 &
exit 0
