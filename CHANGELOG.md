# Changelog

## 1.1.0 — 2026-07-09

### Added
- **Codex agent detection** in `muxtree status`: input prompts (approval and
  trust dialogs), working state, and idle state are now recognized alongside
  Claude Code, using fixtures captured from codex-cli 0.144.0. A Codex agent
  waiting for approval shows `! needs input` instead of `no agent`.
- Agent TUI markers consolidated into single tables (`INPUT_MARKERS`,
  `WORKING_MARKERS`, `IDLE_MARKERS`, `CHROME_PATTERNS`) shared by all
  detection code — a UI drift in either agent is a one-place fix, pinned by
  `test.sh` fixtures.
- Detached-HEAD worktrees now appear in `list` and `status` as `(detached)`
  instead of being silently hidden.
- `list` and `delete` show the changed-file count alongside `+/-` diff stats.
- `sessions attach` switches clients when run from inside tmux instead of
  failing on nested attach.
- Session lookups resolve by worktree directory first (branch name as
  fallback), so a branch renamed inside its worktree no longer orphans its
  session in `list`, `sessions`, or `delete`.

### Fixed
- `status`: Ctrl-C now exits the live pane cleanly instead of leaving the loop
  repainting over the normal screen.
- `status`: rows no longer wrap and garble the display on narrow terminals
  (including standard 80-column); the BRANCH column shrinks to fit, the header
  truncates, and autowrap is disabled while the pane runs.
- `status`: keys are read from `/dev/tty`, so a redirected stdin no longer
  causes a 100% CPU busy-loop with dead keybindings.
- `status`: pressing a digit on a row with no session is ignored instead of
  exiting with a tmux error.
- `status`: rows are clamped to the terminal height (an `… N more` line
  replaces the overflow) instead of scrolling and garbling the in-place
  repaint; `--once` output is never clamped.
- `status`: ports are now found when `worktree_dir` sits behind a symlink
  (e.g. `/tmp` → `/private/tmp` on macOS) — `lsof` reports physical paths.
- `status`: a foreign tmux session with spaces in its name can no longer
  garble the per-frame session snapshot (tab-delimited now).
- `status`: a `/dev/tty` that disappears mid-run exits the pane instead of
  busy-looping at 100% CPU.
- Changed-file counts use `git status -uall`, so an untracked directory
  counts each file inside it instead of appearing as one entry.
- `status -n` / `--interval` with a missing value dies with a usage message
  instead of exiting silently.
- tmux session matching is exact (`=name`): a session named as a prefix of
  another (e.g. `fix` vs `fix-bug`) can no longer display the wrong
  worktree's agent state.
- `list` no longer double-counts staged changes in diff stats, and handles
  worktree paths containing spaces; `list`, `status`, and `delete` now share
  one stats implementation and agree with each other.
- Sourcing `muxtree` (as `test.sh` does) no longer dispatches the sourcing
  script's arguments as real commands.
- Shell completions include `--prompt`/`-p` for `new` and
  `sessions open/relaunch` (bash and zsh).

### Performance
- `status`: the `lsof` port scan is cached for a few seconds per frame
  (`r` forces a rescan); per-row `tmux has-session` forks replaced by one
  `list-sessions` snapshot per frame.

## 1.0.2

- `--prompt` flag to pass an initial prompt to claude/codex agents.
- `sessions open` reattaches to existing sessions in a new terminal.
- `setup_commands` config to run one-time setup in the dev window.
- Shell autocompletion (bash, zsh) and documentation improvements.
