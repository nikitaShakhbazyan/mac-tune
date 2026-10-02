# mac-tune

A single-file cleanup script for Macs that run Docker, a browser and an IDE all
day, and maybe a few dozen Claude Code tabs. It finds what quietly eats memory,
CPU and disk, fixes what is safe to fix, and tells you about the rest.

- **Safe by default.** A plain run only kills orphaned helper processes, marks
  dev folders for Spotlight and prunes old logs. Everything else is opt-in.
- **Dry run first.** `mac-tune -n` prints every change without making it.
- **Repeatable.** Apps and `npm install` undo some fixes, so run it again
  whenever the Mac feels slow.

```text
$ mac-tune --claude -n
*** DRY RUN — nothing will be changed ***

== 3. Idle Claude Code tabs
   [dry] closing tabs (idle for 12+ h): 48, ~4366 MB of memory
      the conversation is kept: reopen it from the chat history

== 5. Claude Code chats older than 7 days — deleted whole, no archive
   [dry] deleting chats: 22
   [dry] empty project folders: 13
      ~65 MB
```

## Install

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/nikitaShakhbazyan/mac-tune/main/mac-tune -o ~/.local/bin/mac-tune
chmod +x ~/.local/bin/mac-tune
```

Make sure `~/.local/bin` is on your `PATH`.

Requirements: macOS, the bash 3.2 that ships with it, and `python3`, which
comes with the Xcode Command Line Tools (`xcode-select --install`).

## Usage

| Command | What it does |
|---|---|
| `mac-tune` | safe defaults: diagnostics, orphaned helpers, Spotlight markers, old logs |
| `mac-tune -n` | dry run, combinable with any other flag |
| `mac-tune --diag` | diagnostics only |
| `mac-tune --claude` | also close idle Claude Code tabs and delete old chats |
| `mac-tune --caches` | also clear package-manager caches and Docker junk |
| `mac-tune --trash` | also empty Trash items older than `--days` |
| `mac-tune --settings` | also apply the opinionated settings listed below |
| `mac-tune --startup` | also disable known updater and adware LaunchAgents |
| `mac-tune --all` | everything above, closing every idle Claude tab |
| `mac-tune --only claude-tabs,logs` | run only the listed steps |
| `mac-tune --claude-stop [N]` | only close Claude tabs launched N+ hours ago (default 6) |
| `--days N` | age threshold for logs, Trash and chats (default 7) |
| `--idle-hours N` | close Claude tabs idle for N+ hours (default 12) |

## Steps

| Step | Default | What it does |
|---|---|---|
| diagnostics | yes | warns when iCloud syncs a dev tree, when a process runs hot, when uptime is over 14 days; changes nothing |
| `orphans` | yes | kills helper processes whose parent died (PPID 1): `docker stats`, IDE ripgrep, crashpad, MCP servers, esbuild/tsserver, file watchers |
| `claude-tabs` | `--claude` | closes Claude Code tabs that have been idle for `--idle-hours` |
| `spotlight` | yes | drops a `.metadata_never_index` marker into `node_modules`, `vendor`, `.git`, `build` and similar folders over 20 MB; best effort, macOS may ignore it |
| `claude-chats` | `--claude` | deletes Claude Code chats older than `--days`, see below |
| `logs` | yes | prunes `~/Library/Logs`, crash reports and Xcode logs older than `--days` |
| `trash` | `--trash` | removes Trash items older than `--days` |
| `caches` | `--caches` | clears npm, Yarn, pnpm, Composer, pip, Go, Cargo, Gradle, CocoaPods and Homebrew caches and Xcode DerivedData; prunes dangling Docker images, build cache and stopped containers |
| `startup` | yes | lists login items and LaunchAgents; with `--startup` it disables the known junk ones |
| `settings` | `--settings` | applies the settings below |

## Never touched

- `~/.claude/projects/*/memory/`, Claude's memory between sessions
- running Claude chats: their files stay, and a tab that is working or waiting
  for your answer is never closed
- Docker volumes, where your local databases live
- project sources and git repositories
- running apps: browsers, IDEs, messengers

## Claude Code

Every Claude Code chat tab runs its own `claude` process of about 200 MB, and
it keeps running until you close the tab. Forty forgotten tabs are 8 GB.

`claude-tabs` sends SIGTERM to tabs that have been idle long enough. The
conversation stays on disk, so you can reopen it from the chat history.

`claude-chats` deletes everything that belongs to a chat older than `--days`,
with no archive:

- the transcript `<id>.jsonl` and its `<id>/` folder
- `<id>/` folders in every other project folder the chat moved into
- `file-history/<id>` and `session-env/<id>`
- its prompts in `history.jsonl`
- project folders left empty, and archives written by earlier versions

> [!WARNING]
> Both steps rely on Claude Code internals that are not documented:
> `~/.claude/sessions/*.json`, `history.jsonl` and the project folder layout.
> A Claude Code update can change them. The steps then skip quietly rather
> than guess, but please open an issue.

## Settings

`--settings` writes these values. Each file is backed up as
`*.mac-tune.bak` first. A VS Code `settings.json` with comments is never
rewritten; you get the list of keys to set by hand instead.

- **Docker Desktop:** Kubernetes off, analytics off, announcements off, UI does
  not open on startup, Resource Saver on.
- **VS Code and Cursor:** dependency and build folders added to
  `files.watcherExclude` (your own entries are kept), `search.followSymlinks`
  off, npm and task auto-detection off, telemetry and experiments off,
  extension update checks off, `git.autofetch` off.
- **Chrome and Brave:** no background mode once the windows are closed.

`--startup` disables Google Keystone and GoogleUpdater among others. Chrome
then stops updating itself, so update it by hand.

## Development

```sh
tests/run.sh        # runs against a throwaway $HOME, safe on your own Mac
CI=1 tests/run.sh   # also runs the settings test (flips Chrome/Brave prefs)
shellcheck mac-tune tests/run.sh
```

Not affiliated with Apple or Anthropic.

## License

[MIT](LICENSE)
