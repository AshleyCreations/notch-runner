# Notch Runner

A macOS menu-bar app. Send a prompt to Claude Code in the terminal and a small
pixel character called **Bit** drops out of the MacBook notch. The notch
stretches into a minimal runner game you play while Claude works. When Claude
finishes, the game pauses, the strip folds back into the notch, and you land
back in your terminal.

https://github.com/user-attachments/assets/507854a1-22c5-4a43-a23c-3b4f9669f7a5

> Not affiliated with Anthropic. Bit is an original character; no Anthropic
> mascot, logo or branding is used.

## Status

**Shipped.** Everything in [NOTCH_RUNNER_SPEC.md](NOTCH_RUNNER_SPEC.md) is
built and has run on a real machine, end to end: install from the one-liner,
prompt, play, Claude finishes, the strip folds away, focus lands back on the
tab you started from, uninstall leaves nothing behind.

Install it with the [one-liner below](#install). The latest build is on the
[releases page](https://github.com/AshleyCreations/notch-runner/releases/latest).

It has only ever run on **one machine**, though. Please read
[Known issues](#known-issues) first — not because anything is known to be
broken, but because a fair amount is simply untested.

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

Then **restart Claude Code** and send a prompt.

### When the island actually shows up

Two rules, and both are about not getting in your way.

**Only after 30 seconds.** The island appears when Claude is *still* working
half a minute in. Quick answers never show it, so you are never watching a
strip unfold just as the reply lands. This is measured, not predicted: nothing
guesses how long a prompt will take from its text, and the hook never sees your
prompt. Change it under Settings -> Show after (immediately / 10s / 30s / 60s)
if you want it sooner.

**Only where you are waiting on Claude Code.** Terminal sessions and the Claude
Code desktop app both get the island. Chat and Cowork do not: those are not
sessions you sit and watch, so a strip unfolding over them is noise. Anything
else is allowed through, on the grounds that a new Claude Code surface should
get the island and the cost of being wrong is a strip you can close.

`/playbot` ignores both rules. If you asked for it, you get it.

### Playing without waiting for Claude

Type `/playbot` and the island opens straight away, with nothing to wait for:

```
> /playbot
```

Claude never answers it, and no turn is spent. `/playbot` is a real Claude Code
command, installed at `~/.claude/commands/playbot.md`; it expands to a marker
the hook recognises, which opens the island and then blocks the prompt before
it reaches Claude. (It has to work this way: Claude Code handles anything
starting with `/` itself, so a prompt hook never sees a bare `/playbot`.)

Close it with the **x**, **Cmd+W**, or **Esc** twice.

Your score, level and speed carry across, so this is the same run you have been
building up while Claude works -- not a separate practice mode. There is also
**Play now** in the menu, which does the same thing.

### What the installer changes

Four things, and nothing else:

| Path | What happens |
|---|---|
| `/Applications/NotchRunner.app` | the app (`~/Applications` if `/Applications` is not writable) |
| `~/.notch-runner/` | the hook script, plus a port file and a mode-600 token |
| `~/.claude/settings.json` | three hook entries appended |
| `~/.claude/commands/playbot.md` | the `/playbot` command |

It never uses `sudo`. In `~/.claude` it appends the three hook entries and adds
that one command file -- and it will not overwrite a `playbot.md` you wrote
yourself; it says so and leaves it alone. Uninstalling removes both.

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

The hook forwards only the session id, the working directory and which terminal
you are in. It never writes to stdout (which would otherwise land in Claude's
context), and it backgrounds its own request with a one-second timeout so it
cannot slow Claude down or block on a stopped app.

It looks at your prompt for exactly **one** thing: whether it contains the
`/playbot` marker. That check happens inside the script, and only the yes-or-no
leaves it -- the text of your prompt is never sent anywhere, written down, or included
in what the app receives. If you would rather it did not look at all, delete
the three lines around `grep -Eq` in
[`hooks/notch-runner-hook.sh`](hooks/notch-runner-hook.sh); everything except
`/playbot` keeps working.

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

## Known issues

Nothing here is known to be broken. It is the list of things that have not been
proven, so you can judge the risk yourself rather than find out.

### It has run on exactly one Mac

Everything below works on an Apple Silicon MacBook with a notch, a single
display, running macOS 26. None of these has ever been tried:

| Untested | Why it might matter |
|---|---|
| **macOS 14 and 15** | The app targets 14.0, but has only run on 26. Window levels and `SMAppService` have both shifted across that range. |
| **Intel Macs** | The binary is universal and built on an Intel runner, but has never been *run* on Intel. |
| **Macs without a notch** | There is a fallback that puts the island at the top centre of the screen. That code has never executed. |
| **External or multiple displays** | The island picks the screen with a notch, else the main one. Never tried with more than one screen. |
| **Two Claude sessions at once** | The island should stay until the last one finishes. Unit-tested, never run for real. |

If you hit any of these, an issue with your macOS version and hardware is
genuinely useful -- that is the gap.

### It is unsigned

No Developer ID, no notarisation, so the installer clears the quarantine flag.
See [the explanation above](#why-does-macos-say-its-from-an-unidentified-developer)
for what that means and how to check the build.

### The Cowork and Chat block is unverified

The island is meant to stay out of Cowork and Chat sessions. That works by
matching `CLAUDE_CODE_ENTRYPOINT`, and the values it matches are **guesses** --
nobody has confirmed what those surfaces actually report. If one of them uses a
different name, it will get an island anyway. The app records each surface it
sees in `~/.notch-runner/entrypoints`; if yours is wrong, that file has the
right answer and an issue with its contents would fix it for everyone.

### Uninstalling reformats `settings.json`

Removing the hooks rewrites `~/.claude/settings.json` through a JSON
serialiser. Every setting survives intact, but key order and spacing may change.
If you keep your dotfiles in git, expect a cosmetic diff.

### `/playbot` depends on how Claude Code delivers slash commands

Claude Code handles anything starting with `/` itself, so `/playbot` works by
installing a real command and matching what the prompt hook receives. **Which
form arrives has already changed once** between Claude Code builds -- the raw
`/playbot` in some, the expanded command body in others. Both are matched now,
but a future change could break it again. If `/playbot` stops working, that is
the first place to look.

### The island covers part of the menu bar

By design -- it unfolds from the notch, which is in the menu bar. It only
takes clicks where it is actually drawn, so the rest of the menu bar stays
usable, but the middle of it is behind the island while the game is open.

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
