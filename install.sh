#!/bin/bash
# Notch Runner installer.
#   curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/install.sh | bash
# Optional: --version vX.Y.Z   pin a specific release.
set -euo pipefail

OWNER="AshleyCreations"
REPO="notch-runner"
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say(){ printf '  %s\n' "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

# 1. macOS 14+
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || die "Notch Runner needs macOS 14 (Sonoma) or newer. Found $(sw_vers -productVersion)."
say "macOS $(sw_vers -productVersion) on $(uname -m) — the build is universal."

# 2. Find the release asset.
API="https://api.github.com/repos/$OWNER/$REPO/releases/latest"
[ -n "$VERSION" ] && API="https://api.github.com/repos/$OWNER/$REPO/releases/tags/$VERSION"
URL="$(curl -fsSL "$API" | grep -o '"browser_download_url": *"[^"]*NotchRunner\.zip"' | head -1 | cut -d'"' -f4)"
[ -n "$URL" ] || die "no NotchRunner.zip asset found at $API"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say "Downloading $URL"
curl -fsSL -o "$TMP/NotchRunner.zip" "$URL"

# 3. Unzip into /Applications, or ~/Applications when that is not writable.
DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
APP="$DEST/NotchRunner.app"
osascript -e 'quit app "NotchRunner"' >/dev/null 2>&1 || true
rm -rf "$APP"
ditto -x -k "$TMP/NotchRunner.zip" "$DEST"
[ -d "$APP" ] || die "unzip did not produce $APP"
say "Installed $APP"

# 4. The build is unsigned; clear the quarantine flag so Gatekeeper lets it run.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 5. Hook script.
mkdir -p "$HOME/.notch-runner"
cp "$APP/Contents/Resources/notch-runner-hook.sh" "$HOME/.notch-runner/notch-runner-hook.sh"
chmod +x "$HOME/.notch-runner/notch-runner-hook.sh"

# 6. The /playbot slash command. Claude Code swallows anything starting with
#    "/" before it becomes a prompt, so this has to be a real command.
CMD="$HOME/.claude/commands/playbot.md"
mkdir -p "$HOME/.claude/commands"
if [ -f "$CMD" ] && ! grep -q 'NOTCH-RUNNER-PLAYBOT' "$CMD"; then
  say "$CMD already exists and is not ours - leaving it alone, so /playbot will not work."
else
  cp "$APP/Contents/Resources/playbot.md" "$CMD"
fi

# 7. Merge our entries into ~/.claude/settings.json (backs up first, idempotent).
"$APP/Contents/MacOS/NotchRunner" --install-hooks

# 8. Launch, with login item enabled by default.
open -a "$APP" --args --enable-login-item

cat <<'MSG'

  Notch Runner is installed.

  Restart Claude Code, then send a prompt. If Claude Code asks you to review
  hooks, approve the Notch Runner ones in /hooks.

  Uninstall:
    curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/uninstall.sh | bash
MSG
