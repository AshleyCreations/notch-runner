#!/bin/bash
# Removes Notch Runner. Touches nothing in ~/.claude except our own hook entries.
set -euo pipefail

say(){ printf '  %s\n' "$*"; }

APP=""
for d in /Applications "$HOME/Applications"; do
  [ -d "$d/NotchRunner.app" ] && APP="$d/NotchRunner.app"
done

if [ -n "$APP" ]; then
  "$APP/Contents/MacOS/NotchRunner" --uninstall-hooks || say "could not remove hook entries; edit ~/.claude/settings.json by hand"
  osascript -e 'quit app "NotchRunner"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$APP"
  say "Removed $APP"
else
  say "NotchRunner.app not found; removing the rest anyway."
fi

rm -rf "$HOME/.notch-runner"
say "Removed ~/.notch-runner"

# Only ours: never touch a playbot.md someone else wrote.
CMD="$HOME/.claude/commands/playbot.md"
if [ -f "$CMD" ] && grep -q 'NOTCH-RUNNER-PLAYBOT' "$CMD"; then
  rm -f "$CMD"
  say "Removed $CMD"
fi
say "Done. Restart Claude Code to drop the hooks."
