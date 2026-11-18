# Notch Runner

A macOS menu-bar app. Send a prompt to Claude Code in the terminal and a small
pixel character called **Bit** drops out of the MacBook notch. The notch
stretches into a minimal runner game you play while Claude works. When Claude
finishes, the game pauses, the strip folds back into the notch, and you land
back in your terminal.

> Not affiliated with Anthropic. Bit is an original character; no Anthropic
> mascot, logo or branding is used.

<!-- DEMO GOES HERE.
     Record with Cmd+Shift+5, then edit this file on github.com and drag the
     .mov straight into the editor at this spot: GitHub hosts it and renders a
     player, so no ffmpeg and no gif conversion needed. -->

## Status

Everything in [NOTCH_RUNNER_SPEC.md](NOTCH_RUNNER_SPEC.md) is built and has run
on a real machine: install, play, Claude finishes, focus comes back.






| `HookInstaller` — merge/unmerge `~/.claude/settings.json` | working, idempotent |
| `EventServer` — localhost listener for hook events | working |
| `SessionRouter` — multi-session state, debouncing | working |
| `FocusReturner` — exact Terminal/iTerm tab | working |
| `install.sh` / `uninstall.sh` / release workflow | working, run end to end |

Not yet verified: Macs **without** a notch, external displays, and two Claude
sessions running at once. The code paths exist and are unit-tested, but none of
them has run on real hardware.

It is also **unsigned** — see [below](#why-does-macos-say-its-from-an-unidentified-developer).

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

```bash
curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/install.sh | bash
```

Then **restart Claude Code** and send a prompt. Anything that takes more than
two seconds brings Bit out of the notch.

### What the installer changes

Three things, and nothing else:

| Path | What happens |
|---|---|
| `/Applications/NotchRunner.app` | the app (`~/Applications` if `/Applications` is not writable) |
| `~/.notch-runner/` | the hook script, plus a port file and a mode-600 token |
| `~/.claude/settings.json` | three hook entries appended |

It never uses `sudo`, and it touches nothing else in `~/.claude`.

### About the hooks

Notch Runner needs to know when you send a prompt and when Claude finishes.
Claude Code exposes exactly that through hooks, so the installer appends three
entries to `~/.claude/settings.json`:

```json
"UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.notch-runner/notch-runner-hook.sh prompt", "timeout": 3 }] }],
"Stop":             [{ "hooks": [{ "type": "command", "command": "~/.notch-runner/notch-runner-hook.sh stop",   "timeout": 3 }] }],
"SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.notch-runner/notch-runner-hook.sh end",    "timeout": 3 }] }]
```

Your existing file is copied to `settings.json.notch-runner-backup-<timestamp>`
first, and your own hooks are left alone -- ours are only ever appended.
Running the installer twice does not duplicate them.

**Claude Code will ask you to approve the new hooks.** That prompt is expected,
and it is Claude Code being careful on your behalf: a hook is a shell command
it runs for you, so it wants you to look before it runs anything. Open
`/hooks`, find the three `notch-runner-hook.sh` entries, and approve them. If
you would rather read the script first, it is
[`hooks/notch-runner-hook.sh`](hooks/notch-runner-hook.sh) -- 16 lines, and
all it does is POST to `127.0.0.1`.

The hook never reads your prompt. It forwards only the session id, the working
directory and which terminal you are in, it never writes to stdout (which would
otherwise land in Claude's context), and it backgrounds its own request with a
one-second timeout so it cannot slow Claude down or block on a stopped app.

### Why does macOS say it's from an unidentified developer?

Because it is. Notch Runner is **not signed with an Apple Developer ID and not
notarised** -- that needs a paid Apple developer account, and this is a free
toy. The release is ad-hoc signed instead, which satisfies macOS's "is this
binary intact" check but tells it nothing about who built it.

So macOS quarantines it, and `install.sh` clears that flag:

```bash
xattr -dr com.apple.quarantine /Applications/NotchRunner.app
```

**That line is the part you should think about.** Clearing quarantine is how
you tell macOS you vouch for an app it cannot vouch for. You are being asked to
trust a stranger on the internet, and piping a script into `bash` means you are
trusting it before you have read it. That is a reasonable thing to be wary of.

What you can check, if you care to:

- **Read the installer first.** It is [`install.sh`](install.sh), about 70 lines:
  `curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/install.sh | less`
- **The binary is built in public.** Every release is produced by
  [the release workflow](.github/workflows/release.yml) running on GitHub's
  machines from a tagged commit -- not uploaded from anyone's laptop. The
  release page names the commit it was built from, and you can read every line
  that went into it.
- **Watch what it does.** The app makes no network requests at all; the web
  view is a local file and the server binds to `127.0.0.1`. Little Snitch or
  `lsof -i -P | grep NotchRunner` will show you.

**Or skip all of that and build it yourself** -- then nothing is quarantined,
because you compiled it:

```bash
git clone https://github.com/AshleyCreations/notch-runner.git
cd notch-runner
brew install xcodegen
app/stage-resources.sh
cd app && xcodegen generate && open NotchRunner.xcodeproj
```

If Notch Runner ever earns a Developer ID, this section goes away and the
installer stops touching quarantine. Until then, the honest answer is: read the
script, or build it yourself.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/AshleyCreations/notch-runner/main/uninstall.sh | bash
```

That quits the app, removes only our entries from `~/.claude/settings.json`,
and deletes the app and `~/.notch-runner`.

Your `settings.json` backups are deliberately **not** deleted, in case you want
them. Clean them up yourself when you are happy:

```bash
rm ~/.claude/settings.json.notch-runner-backup-*
```

One known wrinkle: the hook entries are removed and every other setting is
preserved, but the file is rewritten through a JSON serialiser, so key order
and spacing may change even though the values do not. If you keep your dotfiles
in git, expect a cosmetic diff.

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
