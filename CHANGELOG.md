# Changelog

## 1.0.0 — 2026-10-02

First public release.

- Safe defaults: diagnostics, orphaned helper processes, Spotlight markers,
  old logs. Claude Code, caches, Trash, settings and startup fixes are opt-in.
- `--claude`: close idle Claude Code tabs and delete chats older than
  `--days`, including their scattered folders, file history and prompts.
- `--claude-stop [N]`: only close Claude tabs launched N+ hours ago.
- `--only`: run selected steps.
- `--settings` backs files up, keeps your own `files.watcherExclude` entries
  and never rewrites a `settings.json` that has comments.
