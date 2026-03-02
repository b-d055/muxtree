```
                       _
  _ __ ___  _   ___  _| |_ _ __ ___  ___
 | '_ ` _ \| | | \ \/ / __| '__/ _ \/ _ \
 | | | | | | |_| |>  <| |_| | |  __/  __/
 |_| |_| |_|\__,_/_/\_\\__|_|  \___|\___|
```

**Tmux Worktree Session Manager**

A lightweight CLI for spinning up isolated git worktrees paired with tmux sessions, purpose-built for running parallel [Claude Code](https://code.claude.com/docs), [Codex](https://openai.com/codex/), or [OpenCode](https://opencode.ai/) sessions on macOS.

Each `muxtree new` call gives you a fresh branch in its own directory with your config files copied in, setup commands run, and a tmux session with two windows ready to go — one for viewing code and running your app, one for your AI coding agent. Switch between them with `Ctrl-b n` / `Ctrl-b p`.

---

## Install

```bash
# Copy the script somewhere on your PATH
cp muxtree /usr/local/bin/muxtree
chmod +x /usr/local/bin/muxtree

# Or with Homebrew's default bin path
cp muxtree ~/.local/bin/muxtree
```

### Prerequisites

- **git** (with worktree support — any modern version)
- **tmux** (`brew install tmux`)
- **macOS** with Terminal.app or iTerm2

### Shell Completion

Tab completion is available for bash and zsh, providing completion for commands, flags, session actions, and managed branch names.

**Bash** — requires [`bash-completion`](https://github.com/scop/bash-completion) (`brew install bash-completion@2`). Add to `~/.bashrc` or `~/.bash_profile`:

```bash
source /path/to/muxtree/completions/muxtree.bash
```

**Zsh** — add to `~/.zshrc`:

```zsh
source /path/to/muxtree/completions/muxtree.zsh
```

Replace `/path/to/muxtree` with the actual path to your muxtree checkout or install location.

---

## Quick Start

```bash
# 1. Run interactive setup (creates ~/.muxtree/config)
muxtree init

# 2. Navigate to your repo
cd ~/projects/my-app

# 3. Create a new worktree + tmux session
muxtree new feature-auth

# 4. A terminal window opens with a tmux session containing two windows:
#    • dev    ← run your app, browse code
#    • agent  ← run claude/codex/opencode here
#    Switch windows with Ctrl-b n / Ctrl-b p
```

That's it. You're working in an isolated branch with your `.env` and config files already copied over and setup commands already running.

---

## How It Works

```
  Your repo (~/projects/my-app)
  ├── main branch (your normal working copy)
  │
  │  muxtree new feature-auth --run claude
  │  ┌──────────────────────────────────────────────────────────┐
  │  │  1. git worktree add                                     │
  │  │     ~/worktrees/my-app/feature-auth/  (branch: feature-auth)
  │  │                                                          │
  │  │  2. Copy config files (.env, CLAUDE.md, etc.)            │
  │  │                                                          │
  │  │  3. Run setup commands (npm install, etc.)               │
  │  │                                                          │
  │  │  4. Create tmux session: my-app_feature-auth             │
  │  │     ┌─────────────┐  ┌─────────────┐                    │
  │  │     │  dev window  │  │ agent window│                    │
  │  │     │  (run app,   │  │ (claude is  │                    │
  │  │     │   view code) │  │  running)   │                    │
  │  │     └─────────────┘  └─────────────┘                    │
  │  │     Ctrl-b n / Ctrl-b p to switch                        │
  │  │                                                          │
  │  │  5. Open terminal window attached to session             │
  │  └──────────────────────────────────────────────────────────┘
  │
  │  muxtree new fix-bug
  │  └─► ~/worktrees/my-app/fix-bug/  →  tmux: my-app_fix-bug
  │
  │  muxtree list         ← see all worktrees + diff stats + session status
  │  muxtree delete fix-bug  ← kills session, removes worktree + branch
```

Each worktree is a fully independent working directory — separate branch, separate files, separate tmux session. You can run multiple AI agents in parallel without them stepping on each other.

---

## Commands

### `muxtree init`

Interactive setup. Creates `~/.muxtree/config` where you specify:

- **Worktree base directory** — where all worktrees live (e.g. `~/worktrees`)
- **Terminal app** — `terminal` (Terminal.app) or `iterm2`
- **Files to copy** — comma-separated list of files to copy from your repo root into each new worktree (e.g. `.env,.env.local,CLAUDE.md`)
- **Setup commands** — comma-separated list of commands to run in the dev window when a new worktree is created (e.g. `npm install,npm run build`)

```bash
$ muxtree init
Worktree base directory [~/worktrees]: ~/worktrees
Terminal app (terminal/iterm2) [terminal]: iterm2
Files to copy: .env,.env.local,.claude/settings.json
Setup commands: npm install,npm run build
✓ Config written to ~/.muxtree/config
```

### `muxtree new <branch> [options]`

Creates a worktree, copies config files, runs setup commands, and launches a tmux session with two windows (dev + agent) in a new terminal.

```bash
# Branch from main (auto-detected)
muxtree new feature-auth

# Branch from a specific base
muxtree new fix-bug --from develop

# Auto-launch Claude Code in the claude session
muxtree new feature-ai --run claude

# Auto-launch Codex instead
muxtree new feature-ai --run codex

# Auto-launch OpenCode instead
muxtree new feature-ai --run opencode

# Create worktree + session without opening a terminal window
muxtree new fix-bug --bg
```

**What happens:**

1. `git worktree add -b <branch>` at `<worktree_dir>/<repo>/<branch>/`
2. Copies each file from `copy_files` config into the new worktree
3. Creates a detached tmux session with two windows (dev + agent)
4. Runs `setup_commands` in the dev window (chained with `&&`)
5. Opens the session in a new terminal window

### `muxtree list`

Shows all managed worktrees with diff stats and session status.

```
Worktrees for my-app
════════════════════════════════════════════════════════════════

  feature-auth  +42 -7
  ~/worktrees/my-app/feature-auth
  Session: ● my-app_feature-auth

  fix-bug  +3 -1
  ~/worktrees/my-app/fix-bug
  Session: ○ my-app_fix-bug
```

- `●` = tmux session is running
- `○` = tmux session is not running
- Diff stats show combined staged + unstaged changes vs HEAD

### `muxtree delete <branch> [--force]`

Removes a worktree, kills its tmux sessions, and deletes the local branch.

```bash
$ muxtree delete feature-auth

  Branch:    feature-auth
  Path:      ~/worktrees/my-app/feature-auth
  Changes:   +42 -7

⚠ This will remove the worktree and delete the local branch.
Are you sure? (y/N) y
✓ Killed session my-app_feature-auth
✓ Worktree removed
✓ Branch deleted
```

Use `--force` or `-f` to skip confirmation.

### `muxtree sessions <action> <branch> [options]`

Manage the tmux session independently of the worktree.

```bash
# Close session for a branch
muxtree sessions close feature-auth

# Reopen it (creates new terminal window)
muxtree sessions open feature-auth

# Reopen with claude auto-running in the agent window
muxtree sessions open feature-auth --run claude

# Close + reopen in one step
muxtree sessions relaunch feature-auth --run codex

# Attach to session in your current terminal
muxtree sessions attach feature-auth

# Attach with a specific window selected
muxtree sessions attach feature-auth agent
```

### `muxtree config`

Shows both global (`~/.muxtree/config`) and project-local (`.muxtree`) config files, labeling which one is active. Useful for debugging which settings are in effect.

### `muxtree version`

Print the version number. Also available as `muxtree -v` or `muxtree --version`.

### `muxtree help`

Show all commands and usage. Also available as `muxtree -h` or `muxtree --help`.

---

## Configuration

Config lives at `~/.muxtree/config` (override with `MUXTREE_CONFIG_DIR`). It's a plain key=value file:

```ini
# muxtree configuration

# Base directory for worktrees
worktree_dir=~/worktrees

# Terminal app: terminal | iterm2
terminal=iterm2

# Files to copy from repo root into new worktrees (comma-separated)
# Supports glob patterns
copy_files=.env,.env.local,CLAUDE.md,.claude/settings.json

# Commands to run in the dev window when a new worktree is created (comma-separated)
# Chained with && so execution stops on first failure
setup_commands=npm install,npm run build
```

### Config options

| Key | Default | Description |
|-----|---------|-------------|
| `worktree_dir` | `~/worktrees` | Base directory where worktrees are created. Organized as `<worktree_dir>/<repo>/<branch>/` |
| `terminal` | `terminal` | Which terminal app to open: `terminal` (Terminal.app) or `iterm2` |
| `copy_files` | *(empty)* | Comma-separated list of files/globs to copy from repo root into new worktrees |
| `setup_commands` | *(empty)* | Comma-separated list of commands to run in the dev window on worktree creation. Chained with `&&` |

### Project-local config

You can create a `.muxtree` file in your repo root to override global settings on a per-project basis. This is useful for setting project-specific `copy_files` and `setup_commands`.

```bash
# Interactive setup for the current repo
muxtree init --local
```

The local config file uses the same key=value format. When present, local values override the global config.

### Glob patterns in copy_files

The `copy_files` value supports shell glob patterns:

```ini
# Copy specific files
copy_files=.env,.env.local

# Copy all dotenv files
copy_files=.env*

# Mix of specific files and patterns
copy_files=.env*,CLAUDE.md,config/*.local.json
```

### Command aliases

| Command | Aliases |
|---------|---------|
| `muxtree list` | `muxtree ls` |
| `muxtree delete` | `muxtree rm` |
| `muxtree sessions` | `muxtree s` |
| `muxtree help` | `muxtree -h`, `muxtree --help` |
| `sessions open` | `sessions launch`, `sessions start` |
| `sessions close` | `sessions kill`, `sessions stop` |
| `sessions relaunch` | `sessions restart` |

---

## Directory Layout

```
~/worktrees/                  ← worktree_dir from config
  my-app/                     ← repo name (auto-detected)
    feature-auth/             ← branch name (sanitized)
      .env                    ← copied from repo root
      .env.local              ← copied from repo root
      src/                    ← full working tree
      ...
    fix-bug/
      ...
```

---

## Tmux Session Naming

Each worktree gets a single tmux session named `<repo>_<branch>` with two windows:

```
my-app_feature-auth
  ├── dev     ← for running your app / viewing code
  └── agent   ← for Claude Code / Codex / OpenCode
```

Switch between windows with `Ctrl-b n` (next) and `Ctrl-b p` (previous).

Branch names are sanitized in two ways:

- **Session names**: any character that isn't alphanumeric, underscore, or dash is replaced with a dash (tmux compatibility).
- **Filesystem paths**: any character that isn't alphanumeric, dot, underscore, or dash is replaced with a dash (traversal prevention).

---

## Typical Workflow

```bash
# Start your day — create a fresh workspace
cd ~/projects/my-app
muxtree new feature-user-profiles --run claude

# A terminal window opens with a tmux session:
#   dev window:    cd'd into the worktree, setup commands already running
#   agent window:  Claude Code is already running
# Switch between them with Ctrl-b n / Ctrl-b p

# Check on all your active branches
muxtree list

# Done with a feature — clean up
muxtree delete feature-user-profiles

# Need to step away but keep the worktree? Just close the session
muxtree sessions close feature-user-profiles

# Come back later and relaunch
muxtree sessions open feature-user-profiles --run claude
```

---

## Security

muxtree is designed with security in mind:

- **No shell execution of config** — config is parsed as plain key=value pairs, not sourced. Values containing shell metacharacters (`$`, `` ` ``, `;`, `|`, `&`) are ignored with a warning. `setup_commands` allows `&`, `;`, and `|` since it holds intentional shell commands, but still rejects backticks and `$(...)`.
- **AppleScript injection prevention** — session names are escaped before embedding in osascript.
- **Branch name sanitization** — filesystem paths strip non-alphanumeric characters to prevent traversal.
- **Command validation** — `--run` only accepts `claude`, `codex`, or `opencode`.
- **Safe file operations** — `--` separators on `rm`, `cp`, `mkdir` to handle edge-case filenames.

---

## Uninstall

```bash
# Remove the binary
rm /usr/local/bin/muxtree

# Remove config
rm -rf ~/.muxtree

# Optionally clean up any remaining worktrees
rm -rf ~/worktrees  # or wherever you configured them
```

---

## License

MIT
