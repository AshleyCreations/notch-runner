# Notch Runner

A macOS menu-bar app. Send a prompt to Claude Code in the terminal and a small
pixel character called **Bit** drops out of the MacBook notch. The notch
stretches into a minimal runner game you play while Claude works. When Claude
finishes, the game pauses, the strip folds back into the notch, and you land
back in your terminal.

> Not affiliated with Anthropic. Bit is an original character; no Anthropic
> mascot, logo or branding is used.

## Status

Early. The island UI and game are done; the native app is being built around
them. See [NOTCH_RUNNER_SPEC.md](NOTCH_RUNNER_SPEC.md) for the full brief and
the build order.

| Piece | State |
|---|---|
| `game/index.html` — island UI + game | done |
| Menu-bar app, notch panel, transparent web view | done |
| `HookInstaller` — merge/unmerge `~/.claude/settings.json` | done |
| `EventServer` — localhost listener for hook events | done |
| `SessionRouter` — multi-session state, debouncing | done |
| `FocusReturner` — exact Terminal/iTerm tab | done, untested on a real screen |
| `install.sh` / release workflow | written, untested end to end |

## Tests

```bash
app/Tests/run.sh
```

No Xcode needed — the suites compile against the Swift toolchain alone.

## Try the game now

```bash
open game/index.html
```

Opened in a browser it brings up a dev harness: **Send prompt** / **Claude
finished** / **Reset** drive the island through its states. Space jumps (hold
for higher), ↓ ducks and fast-falls, Esc pauses.

## Install

Not yet released. Once `v0.1.0` is tagged:

```bash
curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/install.sh | bash
```

Then restart Claude Code. If it asks you to review hooks, approve the Notch
Runner ones in `/hooks`.

### Why does macOS say it's from an unidentified developer?

The release build is ad-hoc signed, not signed with a paid Developer ID and not
notarised. `install.sh` clears the quarantine flag on the app it just
downloaded so Gatekeeper lets it run. If you would rather not have a script do
that, build it yourself:

```bash
brew install xcodegen
cd app && xcodegen generate && open NotchRunner.xcodeproj
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/uninstall.sh | bash
```

That quits the app, removes only our entries from `~/.claude/settings.json`
(everything else is left byte-for-byte), and deletes the app and
`~/.notch-runner`.

## How it works

```
Claude Code (terminal)
   │  hook events: UserPromptSubmit, Stop, SessionEnd
   ▼
~/.notch-runner/notch-runner-hook.sh
   │  POST http://127.0.0.1:47811/event  (X-NR-Token, 1s timeout, never blocks Claude)
   ▼
NotchRunner.app
   ├─ EventServer → SessionRouter
   ├─ IslandPanel (NSPanel at the notch) → WKWebView(game/index.html)
   └─ FocusReturner → activates the terminal the prompt came from
```

`game/index.html` is the single source of truth for the UI; a build phase
copies it into the app bundle.

## Privacy

Everything stays on your machine. No telemetry, and nothing leaves localhost.

- **Your prompt text is never read or stored.** The hook forwards only
  `session_id`, `cwd` and terminal identifiers.
- The event server binds to `127.0.0.1` only and requires a token from a
  mode-600 file in `~/.notch-runner`.
- The web view makes no network requests — no external fonts, no CDNs.
- Permissions: Apple Events only, and only so the app can bring your exact
  terminal tab back. Deny it and the app falls back to plain app activation.
  No Accessibility, Input Monitoring or Screen Recording.

## Licence

MIT — see [LICENSE](LICENSE).
