# Notch Runner — Build Spec

A macOS menu-bar app. When you send a prompt to Claude Code in the terminal, a small pixel character called **Bit** drops out of the MacBook notch. The notch then stretches into a minimal runner game that you play while Claude works. When Claude finishes, the game pauses, the strip folds back into the notch, and you're returned to your terminal.

This file is the full brief for building it. The game UI is already done: `game/index.html`. Open it in a browser to try it with the dev harness. Build everything around that file.

---

## 0. Scope

**In scope (v1)**
- Trigger only on **prompt sent → Claude processing → Claude finished**, in Claude Code CLI sessions.
- macOS 14+ (Sonoma and later). On Macs without a notch, the island sits at the top centre of the screen.
- Install with one line: `curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash`
- An original character (Bit). **Do not** use Anthropic's Claude mascot, logo or "Claude" in the app name or icon. Plain text like "Claude is working" inside the UI is fine.

**Out of scope (v1)**: network-failure triggers, Windows/Linux, App Store, Apple signing and notarisation, multiplayer or leaderboards, sounds.

---

## 1. Repo layout

```
notch-runner/
├── README.md                     # what it is, GIF, install, uninstall, privacy
├── LICENSE                       # MIT
├── NOTCH_RUNNER_SPEC.md          # this file
├── install.sh                    # one-line installer
├── uninstall.sh
├── game/
│   └── index.html                # island UI + game (provided, single file, no deps)
├── app/
│   ├── project.yml               # XcodeGen spec
│   ├── NotchRunner/
│   │   ├── NotchRunnerApp.swift      # @main, menu-bar only (LSUIElement)
│   │   ├── AppDelegate.swift
│   │   ├── IslandPanel.swift         # borderless NSPanel at the notch
│   │   ├── IslandWebView.swift       # WKWebView + JS bridge
│   │   ├── EventServer.swift         # localhost HTTP listener for hook events
│   │   ├── SessionRouter.swift       # multi-session state, debouncing
│   │   ├── FocusReturner.swift       # bring the right terminal back
│   │   ├── HookInstaller.swift       # merge/unmerge ~/.claude/settings.json
│   │   ├── Settings.swift            # UserDefaults-backed settings
│   │   ├── StateStore.swift          # persists game state (saved tokens, level…)
│   │   ├── MenuBar.swift             # status item + menu
│   │   └── Resources/
│   │       ├── game/index.html       # copied from /game at build time
│   │       └── Assets.xcassets       # app icon + menu-bar template icon (Bit silhouette)
│   └── Info.plist
├── hooks/
│   └── notch-runner-hook.sh      # the only thing Claude Code calls
└── .github/workflows/release.yml # already exists in the owner's repo, adapt as needed
```

---

## 2. Architecture

```
Claude Code (terminal)
   │  hook events: UserPromptSubmit, Stop, SessionEnd
   ▼
~/.notch-runner/notch-runner-hook.sh   ← reads hook JSON on stdin, adds tty/terminal info
   │  POST http://127.0.0.1:47811/event   (header X-NR-Token, 1 s timeout, never blocks Claude)
   ▼
NotchRunner.app  (menu-bar app, always running)
   ├─ EventServer → SessionRouter
   ├─ IslandPanel (NSPanel at the notch) → WKWebView(game/index.html)
   │      native → JS:  window.NotchRunner.event({...})
   │      JS → native:  webkit.messageHandlers.runner.postMessage({...})
   └─ FocusReturner → activates the terminal window/tab the prompt came from
```

Why localhost HTTP rather than a Unix socket? The hook only needs `curl`, which ships with macOS, so there's no extra binary to install, sign or quarantine. Bind to `127.0.0.1` only, and require the token.

---

## 3. Hooks

### 3.1 Hook script — `~/.notch-runner/notch-runner-hook.sh`

Installed by `install.sh` (copied from `hooks/`), `chmod +x`.

```bash
#!/bin/bash
# Usage: notch-runner-hook.sh <event>   (prompt | stop | end)
# Must ALWAYS exit 0 quickly. Never print to stdout (UserPromptSubmit stdout is added to Claude's context).
EVENT="$1"
DIR="$HOME/.notch-runner"
PORT="$(cat "$DIR/port" 2>/dev/null || echo 47811)"
TOKEN="$(cat "$DIR/token" 2>/dev/null)"
INPUT="$(cat)"                                  # hook JSON from Claude Code
TTY="$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
PAYLOAD=$(printf '{"event":"%s","tty":"%s","term":"%s","termSession":"%s","itermSession":"%s","hook":%s}' \
  "$EVENT" "$TTY" "${TERM_PROGRAM:-}" "${TERM_SESSION_ID:-}" "${ITERM_SESSION_ID:-}" "${INPUT:-{}}")
curl -s -m 1 -o /dev/null -X POST "http://127.0.0.1:$PORT/event" \
  -H "Content-Type: application/json" -H "X-NR-Token: $TOKEN" --data-binary "$PAYLOAD" >/dev/null 2>&1 &
exit 0
```

Claude Code's hook JSON includes `session_id`, `cwd`, `hook_event_name` and `transcript_path`. Use `session_id` as the session key.

### 3.2 Entries merged into `~/.claude/settings.json`

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.notch-runner/notch-runner-hook.sh prompt", "timeout": 3 }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.notch-runner/notch-runner-hook.sh stop",   "timeout": 3 }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.notch-runner/notch-runner-hook.sh end",    "timeout": 3 }] }]
  }
}
```

`HookInstaller` rules:
- Back up first: `~/.claude/settings.json.notch-runner-backup-<timestamp>`.
- Parse the JSON. If the file doesn't exist, create `{}`.
- **Append** our entries to each event array. Never replace other hooks. Our entries are recognised by the command containing `notch-runner-hook.sh`.
- Idempotent: running it twice doesn't duplicate entries.
- Uninstall removes only our entries, drops event keys left empty, and keeps everything else byte-for-byte where possible.
- If the JSON is invalid, abort and tell the user. Don't overwrite.
- Expose it as a CLI: `NotchRunner.app/Contents/MacOS/NotchRunner --install-hooks` / `--uninstall-hooks` (used by the scripts), and also as menu items.
- After installing, tell the user to restart Claude Code. Claude Code may ask them to review the new hooks in `/hooks`.

---

## 4. Event server (`EventServer.swift`)

- Use `Network.framework` `NWListener` on `127.0.0.1:47811`. If the port is busy, try 47812–47820 and write the chosen port to `~/.notch-runner/port`.
- On first launch, generate a random 32-byte hex token and write it to `~/.notch-runner/token` with mode 600. Reject requests without a matching `X-NR-Token` (respond 401).
- Accept only `POST /event`, with a body under 64 KB. Respond `204` immediately, then process on the main actor.
- Parse into:

```swift
struct HookEvent: Decodable {
  let event: String            // "prompt" | "stop" | "end"
  let tty: String?
  let term: String?            // TERM_PROGRAM: Apple_Terminal, iTerm.app, WarpTerminal, vscode, ghostty…
  let termSession: String?
  let itermSession: String?
  let hook: HookPayload
}
struct HookPayload: Decodable { let session_id: String?; let cwd: String?; let hook_event_name: String? }
```

---

## 5. Session routing (`SessionRouter.swift`)

There is one island but possibly several Claude sessions.

- Keep `[sessionId: Session]`, where `Session` holds `startedAt`, `tty`, `term`, `termSession`, `itermSession`, `cwd` and `state` (`working` / `idle`).
- `prompt`: mark the session working and remember its terminal info. If no other session is working, send `{type:'prompt', sessionId}` to the web view. If one is already working, keep the island open; the label can say "2 sessions working".
- `stop`: mark the session idle. When **no** sessions are working, send `{type:'stop', sessionId}`. That's the last session to finish; return focus to it.
- `end`: remove the session. Treat it as `stop` if it was working.
- Debounce: ignore a `stop` that arrives under 300 ms after the same session's `prompt`.
- Safety timeout: the web view folds away after `stuckTimeoutMs` (30 min) with no stop. That covers Esc or Ctrl+C interrupts, where `Stop` may not fire.
- If the app is disabled in the menu, drop events.

---

## 6. Island panel (`IslandPanel.swift`)

- `NSPanel`, borderless, `.nonactivatingPanel`, `isFloatingPanel = true`, `level = .statusBar` (or `.mainMenu + 1` so it sits over the menu bar), `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- **Frame:** fixed at the maximum island size plus a margin (600 × 240 pt), top-centred on the target screen, with its top edge flush with the screen's top (`screen.frame.maxY`).
- **Target screen:** the screen with the notch (`screen.safeAreaInsets.top > 0`) if there is one, otherwise `NSScreen.main`.
- **Notch width:** read it from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, then send `{type:'config'}` so the idle width matches the real notch. Add a `--w-idle` override message if needed. The default is 186 × 32 pt.
- **Click-through:** the web view posts `{type:'island', state, width, height, interactive}`. Set `panel.ignoresMouseEvents = !interactive`, so only the expanded game strip takes clicks and the rest of the panel never blocks the menu bar or apps below.
- **Keyboard:**
  - The panel must become key to receive Space, ↓ and Esc. Override `canBecomeKey = true`.
  - On `{type:'wantsKeyboard'}` (sent when the strip opens and on click), call `panel.makeKey()` and `NSApp.activate(ignoringOtherApps: true)`.
  - The setting "Take keyboard when the game opens" (default **on**) controls whether this happens automatically when the strip opens. The user has just sent a prompt, so they're not typing.
- Hide the panel completely (`orderOut`) while idle for more than a few seconds, and when a full-screen app is in front and the setting "Show over full-screen apps" is off.

### WKWebView (`IslandWebView.swift`)
- Load `Resources/game/index.html` with `loadFileURL(_:allowingReadAccessTo:)`.
- Use a transparent background: `setValue(false, forKey: "drawsBackground")`, and set the underlying layer's background to clear.
- Add the `WKScriptMessageHandler` named `runner`.
- Native → JS: `webView.evaluateJavaScript("window.NotchRunner.event(\(json))")`.
- Queue events until JS posts `{type:'ready'}`, then send `restore` with the saved state and `config` with the settings.

---

## 7. Bridge contract

### Native → JS: `window.NotchRunner.event(obj)`

| type | payload | effect |
|---|---|---|
| `prompt` | `{sessionId}` | Starts the flow. After `showAfterMs`: peek, then the game strip opens with the countdown. |
| `stop` | `{sessionId}` | Pause the game, save it, show the "Claude is done" pill, fold to idle, then post `returnFocus`. If the island never opened, does nothing. |
| `reset` | – | Clear all progress. |
| `restore` | `{state}` | Load the saved game state (shape below). |
| `config` | `{config:{showAfterMs, countdownSecs, …}}` | Override `CONFIG`. |
| `pause` | – | Pause, for example when the screen locks. |

### JS → native: `webkit.messageHandlers.runner.postMessage(obj)`

| type | payload | native should |
|---|---|---|
| `ready` | – | Flush queued events, send `restore` and `config`. |
| `island` | `{state, width, height, interactive}` | Set click-through. Optionally use the size for accessibility frames. |
| `wantsKeyboard` | – | Make the panel key (per settings). |
| `save` | `{state}` | Persist to `StateStore` (UserDefaults JSON). |
| `returnFocus` | `{sessionId}` | `FocusReturner.focus(session)`, and resign the panel's key status. |

Saved state shape: `{ saved, level, cleared, speed, ctx, best, everPlayed }`.

---

## 8. Returning focus (`FocusReturner.swift`)

The goal is to land the user back on the exact window or tab the prompt came from, with the cursor ready.

1. Resign the panel's key status first.
2. Use `session.term` (TERM_PROGRAM):
   - **Apple_Terminal:** use AppleScript to find the tab whose `tty` is `/dev/<session.tty>`, then select that tab, set its window as the front window and activate it.
   - **iTerm.app:** use AppleScript to find the session whose `tty` matches (or whose `unique ID` equals the part of `itermSession` after `:`), then select it and activate.
   - **Anything else** (WarpTerminal, ghostty, vscode, Cursor and others): look up the app by bundle ID and call `NSRunningApplication.activate()`. You don't get exact-tab precision here.
3. The Apple Events permission prompt appears once. Add `NSAppleEventsUsageDescription` to Info.plist: "Notch Runner brings your terminal back when Claude finishes." If the user denies it, fall back to plain app activation and never ask again.
4. Remember the app that was frontmost when the prompt arrived (`NSWorkspace.shared.frontmostApplication`) as a fallback.

---

## 9. Game logic (all in `game/index.html`)

### Island states and timings
`idle` (notch size) → **peek** (300×36: Bit drops out with a spring, "Thinking…", seconds counter) → **game** (560×222: game canvas, processing glow at the bottom) → **done** (380×40: "Claude is done · 1.5K tokens saved (^‿^)") → `idle`.

| Constant | Default |
|---|---|
| `showAfterMs` | 2000. Quick replies never show the island. |
| `peekToGameMs` | 1450 |
| `doneHoldMs` | 2200 |
| `countdownSecs` | 5 |
| `resumeAfterEscSecs` | 3 |
| `stuckTimeoutMs` | 30 min |

### Start, pause, resume
- **Every** start, including the first, every new prompt and every resume, shows a 5-4-3-2-1 countdown. Clicking or pressing Space skips it. It auto-starts at 0.
- Before any resume, the track ahead is cleared (a breather). **Score, level, speed and context bar are kept**, but obstacle positions are not.
- Esc toggles pause at any time. The face shows `(-_-) zZ` and the glow dims.
- When Claude stops, the game always pauses automatically and the state is saved.
- On a crash, the screen shows "(x_x) Hit by <label>" and a new run starts after 5 s. Clicking starts it immediately. Tokens saved carry over; level and speed reset.

### Controls
| Input | Action |
|---|---|
| Space / ↑ / click (tap) | Short hop (clears bugs) |
| Hold Space / ↑ / mouse | Higher, longer jump (lower gravity for up to 14 frames while rising). Needed for tall walls and wide blocks. |
| Hold ↓ on the ground | Duck (clouds, low birds) |
| ↓ in the air | Fast fall (3× gravity) |
| Esc | Pause / resume |

Physics constants: gravity 0.45, jump velocity 5.4, held-jump gravity 0.18, hold window 14 frames, fast-fall multiplier 3. Speed starts at 3.2 and rises by 0.0016 per frame, up to a cap of 7.5. The hitbox is inset 4 px on the sides and 2 px on top.

### Obstacles (each gets a random label)
| Type | How to clear | From level | Labels |
|---|---|---|---|
| bug | tap jump | 1 | bug, NaN, undefined, TODO, typo, console.log, any |
| wall (tall) | held jump | 2 | 404, 500, EADDRINUSE, CORS, 429, 403, ENOENT |
| cloud | duck | 2 | 529 overloaded, localhost refused, Vercel build failed, npm ERR!, port 3000 in use, DNS_PROBE |
| bird | low: duck; high: stay on the ground | 3 | merge conflict, flaky test, Slack ping, scope creep, "quick call?", PM feedback |
| wide block | long held jump | 3 | node_modules, legacy code, tech debt, monorepo, .env missing, lockfile diff |
| bomb | falls with a ground shadow showing where it will land, then jump it | 4 | prod deploy, rm -rf, force push, Friday 5pm, DROP TABLE, hotfix |

Spacing: `gap = speed × 40 + obstacleWidth + random(tightness[level])`, where tightness is [140, 120, 105, 95, 80]. That always leaves room to land a full held jump. Level 5 occasionally sends a quick double.

### Levels
Levels go up by obstacles cleared: 0 / 6 / 14 / 24 / 36 → Level 1–5. The level name flashes on level-up.

### Score: "tokens saved"
- Clearing an obstacle adds `random(60…240) × (1 + (level−1) × 0.5)`, multiplied by 1.4 for walls and wide blocks. A green `+N` floats up.
- The top-right shows `1.5K tokens saved (^‿^)`. Faces: `(^‿^)` running, `\(^o^)/` on every 5th clear, `(⌐■_■)` on compact, `(°ロ°;)` on level-up, `(x_x)` on a crash, `(-_-) zZ` when paused.
- The context bar (top-left) fills while you run. When it's full, "/compact · context cleared, speed reset" appears and speed drops back 70 % of the way toward its starting value.

### Visual rules
- The island is pure black so it blends into the notch. The game uses greys plus Bit's amber.
- The processing glow is a blurred moving gradient (amber, coral, lavender, blue, teal) **only in the bottom band** of the strip, below the ground line. It never goes inside the game canvas.
- Respect `prefers-reduced-motion` (no glow animation, no spring).
- No external fonts or network requests. It must work offline.

---

## 10. Menu bar (`MenuBar.swift`)

Template icon: Bit's silhouette. Menu items:
- **Enabled** ✓ (toggle)
- **Play now**: opens the strip with a countdown, even when Claude isn't working. Fold it with Esc ×2 or the "Close" item.
- Tokens saved: 12.4K · Best: 3.1K (read-only line)
- **Settings…**
  - Show after: 0 / 2 / 5 / 10 s
  - Take keyboard when the game opens
  - Show over full-screen apps
  - Launch at login (`SMAppService.mainApp`)
- **Install hooks / Remove hooks** (shows ✓ when installed)
- **Reset progress**
- **About**, **Quit**

---

## 11. install.sh / uninstall.sh

`install.sh` must:
1. Check macOS 14 or newer and `uname -m`. The build is universal, so it works on both Intel and Apple Silicon.
2. Download the latest release zip from the GitHub Releases API: `https://api.github.com/repos/<owner>/<repo>/releases/latest` → asset `NotchRunner.zip`.
3. Unzip to `/Applications/NotchRunner.app`. If that isn't writable, use `~/Applications`.
4. Run `xattr -dr com.apple.quarantine` on the app. It's unsigned, so this avoids the Gatekeeper block for people who chose to run the installer. Explain this in the README.
5. `mkdir -p ~/.notch-runner`, then copy the hook script there and `chmod +x` it.
6. Run `NotchRunner --install-hooks` (backup + merge).
7. `open` the app, and enable Launch at login by default.
8. Print: "Restart Claude Code, then send a prompt. If Claude Code asks you to review hooks, approve the Notch Runner ones in /hooks."

Use `set -euo pipefail`, keep it idempotent, and add `--version vX.Y.Z` support. Never use `sudo`.

`uninstall.sh`: quit the app, run `--uninstall-hooks`, then remove the app, `~/.notch-runner` and the login item. Don't touch anything else in `~/.claude`.

---

## 12. Build and release

- XcodeGen `project.yml`: macOS 14 target, `LSUIElement = YES`, universal binary, bundle ID `io.github.<owner>.notchrunner`, version from the git tag.
- A build phase copies `/game/index.html` into the app's Resources, so there's one source of truth.
- The owner already has GitHub Actions. The release workflow runs on `macos-15` (`macos-14` was retired on 2 Nov 2026): `brew install xcodegen` → `xcodegen` → `xcodebuild -scheme NotchRunner -configuration Release ARCHS="arm64 x86_64" CODE_SIGN_IDENTITY="-"` (ad-hoc sign) → `ditto -c -k --keepParent NotchRunner.app NotchRunner.zip` → upload it to the GitHub Release for tag `v*`.
- Later, add Developer ID signing and notarisation through repo secrets when available.

---

## 13. Privacy and security

- Everything stays on the machine. There's no telemetry and nothing is sent anywhere except localhost.
- Prompt text is **never** read or stored. Only `session_id`, `cwd` and terminal identifiers are used.
- The event server binds to 127.0.0.1 only and requires the token from a mode-600 file.
- Permissions: Apple Events (optional, for exact-tab focus). No Accessibility, Input Monitoring or Screen Recording.

---

## 14. Build order for Claude Code

Do these in order, and make each one testable before moving on.

1. **Scaffold the repo:** layout, LICENSE, README stub, `game/index.html` in place. Opening it in a browser shows the dev harness and it works.
2. **App shell:** menu-bar app, notch panel, transparent WKWebView loading the game. The menu item "Simulate prompt" / "Simulate stop" drives the island.
3. **Click-through and keyboard:** the panel only takes clicks in game state; Space, ↓ and Esc work after the strip opens.
4. **Event server and hook script:** `curl` against the server opens the island. Then install the hooks by hand and test with real Claude Code.
5. **HookInstaller:** `--install-hooks` / `--uninstall-hooks`, idempotent and with backups. Add unit tests with sample settings files: missing, empty, with other hooks, invalid JSON.
6. **SessionRouter:** two Claude sessions at once; the safety timeout; interrupting with Esc in Claude Code.
7. **FocusReturner:** Terminal and iTerm exact tab, plus fallbacks.
8. **Settings, StateStore, launch at login.**
9. **install.sh / uninstall.sh and the release workflow;** tag `v0.1.0`.
10. **README:** GIF, install line, what permissions it asks for and why, uninstall, FAQ ("Why does macOS say it's from an unidentified developer?").

### Acceptance checklist
- [ ] A fresh Mac: the one-line install leads to a restart of Claude Code, and the next prompt that takes more than 2 s shows Bit dropping from the notch.
- [ ] A countdown appears on every start and resume; click or Space skips it.
- [ ] Esc pauses and resumes. Claude finishing auto-pauses, folds the strip, and focuses the original Terminal or iTerm tab.
- [ ] The next prompt resumes with the same level, speed and score, a clear track and a countdown.
- [ ] Quick replies under 2 s never show the island.
- [ ] Two parallel sessions: the island stays until both finish.
- [ ] Interrupting Claude with Esc: the island folds by the timeout and the next prompt still works.
- [ ] The menu bar and apps under the panel stay clickable whenever the strip isn't open.
- [ ] Uninstall leaves `~/.claude/settings.json` exactly as it was, minus our entries.
- [ ] No network requests from the web view (check in Web Inspector).
