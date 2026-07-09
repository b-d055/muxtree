#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# muxtree test suite
# Tests non-interactive functions: sanitization, config parsing, arg parsing
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0
TESTS=0

# ── Test harness ─────────────────────────────────────────────────────────────

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $label"
    else
        echo "  FAIL: $label"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $label"
    else
        echo "  FAIL: $label"
        echo "    expected to contain: '$needle'"
        echo "    actual: '$haystack'"
        FAILURES=$((FAILURES + 1))
    fi
}

# ── Source muxtree ────────────────────────────────────────────────────────────

# muxtree's dispatch is guarded by a BASH_SOURCE check, so sourcing defines the
# functions without running anything. The redirect keeps the source's [[ -t 1 ]]
# color check deterministic (colors always off), so assertions on captured
# output never depend on whether the test run itself has a terminal.
{
    source "$SCRIPT_DIR/muxtree"
} >/dev/null 2>&1

# ── 1. session_prefix sanitization ───────────────────────────────────────────

echo ""
echo "== session_prefix sanitization =="

assert_eq "clean branch" \
    "repo_feature" \
    "$(session_prefix "repo" "feature")"

assert_eq "slashes replaced" \
    "repo_feature-auth" \
    "$(session_prefix "repo" "feature/auth")"

assert_eq "dots replaced" \
    "repo_v1-2-3" \
    "$(session_prefix "repo" "v1.2.3")"

assert_eq "hash replaced" \
    "repo_issue-123" \
    "$(session_prefix "repo" "issue#123")"

assert_eq "colon replaced" \
    "repo_foo-bar" \
    "$(session_prefix "repo" "foo:bar")"

assert_eq "at sign replaced" \
    "repo_user-branch" \
    "$(session_prefix "repo" "user@branch")"

assert_eq "spaces replaced" \
    "repo_my-branch" \
    "$(session_prefix "repo" "my branch")"

assert_eq "nested slashes" \
    "repo_a-b-c" \
    "$(session_prefix "repo" "a/b/c")"

assert_eq "leading special char stripped" \
    "repo_branch" \
    "$(session_prefix "repo" ".branch")"

# ── 2. worktree_path sanitization ────────────────────────────────────────────

echo ""
echo "== worktree_path sanitization =="

# Need WORKTREE_DIR set
WORKTREE_DIR="/tmp/wt"

assert_eq "clean branch" \
    "/tmp/wt/repo/feature" \
    "$(worktree_path "repo" "feature")"

assert_eq "slashes replaced" \
    "/tmp/wt/repo/feature-auth" \
    "$(worktree_path "repo" "feature/auth")"

assert_eq "special chars replaced" \
    "/tmp/wt/repo/fix-bug-123" \
    "$(worktree_path "repo" "fix#bug@123")"

assert_eq "dots preserved" \
    "/tmp/wt/repo/v1.2.3" \
    "$(worktree_path "repo" "v1.2.3")"

assert_eq "leading dash stripped" \
    "/tmp/wt/repo/branch" \
    "$(worktree_path "repo" "-branch")"

# ── 3. _parse_config ─────────────────────────────────────────────────────────

echo ""
echo "== _parse_config =="

# Create temp config files for testing
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Basic parsing
cat > "$TMPDIR_TEST/basic.conf" <<'EOF'
worktree_dir=~/my-worktrees
terminal=iterm2
copy_files=.env,.env.local
EOF

WORKTREE_DIR="" TERMINAL="" COPY_FILES=""
_parse_config "$TMPDIR_TEST/basic.conf"

assert_eq "basic worktree_dir" "~/my-worktrees" "$WORKTREE_DIR"
assert_eq "basic terminal" "iterm2" "$TERMINAL"
assert_eq "basic copy_files" ".env,.env.local" "$COPY_FILES"

# Metacharacter rejection
cat > "$TMPDIR_TEST/meta.conf" <<'EOF'
worktree_dir=$(rm -rf /)
terminal=safe
EOF

WORKTREE_DIR="default" TERMINAL=""
_parse_config "$TMPDIR_TEST/meta.conf" 2>/dev/null

assert_eq "metachar rejection keeps default" "default" "$WORKTREE_DIR"
assert_eq "metachar safe value passes" "safe" "$TERMINAL"

# Quoted values preserved (not mangled by xargs)
cat > "$TMPDIR_TEST/quoted.conf" <<'EOF'
copy_files=file with spaces.txt
EOF

COPY_FILES=""
_parse_config "$TMPDIR_TEST/quoted.conf"

assert_eq "spaces in value preserved" "file with spaces.txt" "$COPY_FILES"

# Flag-like values preserved
cat > "$TMPDIR_TEST/flags.conf" <<'EOF'
copy_files=-e .env
EOF

COPY_FILES=""
_parse_config "$TMPDIR_TEST/flags.conf"

assert_eq "flag-like value preserved" "-e .env" "$COPY_FILES"

# setup_commands allows & and ; (shell commands)
cat > "$TMPDIR_TEST/setup.conf" <<'EOF'
setup_commands=npm install,npm run build
EOF

SETUP_COMMANDS=""
_parse_config "$TMPDIR_TEST/setup.conf"

assert_eq "setup_commands basic" "npm install,npm run build" "$SETUP_COMMANDS"

# setup_commands with && (allowed, since it's intentionally a shell command)
cat > "$TMPDIR_TEST/setup_chain.conf" <<'EOF'
setup_commands=npm install && npm run build
EOF

SETUP_COMMANDS=""
_parse_config "$TMPDIR_TEST/setup_chain.conf"

assert_eq "setup_commands allows &&" "npm install && npm run build" "$SETUP_COMMANDS"

# setup_commands still rejects backticks
cat > "$TMPDIR_TEST/setup_bad.conf" <<'EOF'
setup_commands=`rm -rf /`
EOF

SETUP_COMMANDS="default"
_parse_config "$TMPDIR_TEST/setup_bad.conf" 2>/dev/null

assert_eq "setup_commands rejects backticks" "default" "$SETUP_COMMANDS"

# ── 4. cmd_delete arg parsing ────────────────────────────────────────────────

echo ""
echo "== cmd_delete arg parsing =="

# Run cmd_delete in subshells with overridden die/ensure_git_repo/load_config
# to isolate argument parsing logic.

_run_delete() {
    (
        die() { echo "DIE: $*"; exit 1; }
        ensure_git_repo() { :; }
        load_config() { WORKTREE_DIR="/nonexistent"; }
        cmd_delete "$@" 2>&1
    ) || true
}

# No args should produce usage error
result=$(_run_delete)
assert_contains "no args produces usage" "Usage:" "$result"

# --force before branch name should parse correctly
result=$(_run_delete --force mybranch)
assert_contains "--force before branch parses" "not found" "$result"

# Unknown flag rejected
result=$(_run_delete --bogus)
assert_contains "unknown flag rejected" "Unknown option" "$result"

# ── 5. Color TTY check ──────────────────────────────────────────────────────

echo ""
echo "== Color TTY check =="

# Source muxtree in a pipe (stdout not a TTY) and check color vars
color_result=$(bash -c '
    source "'"$SCRIPT_DIR/muxtree"'" 2>/dev/null
    echo "COLORCHECK:RED=${RED}:GREEN=${GREEN}:RESET=${RESET}"
' 2>/dev/null | grep "^COLORCHECK:" | head -1)

assert_eq "piped output has no colors" "COLORCHECK:RED=:GREEN=:RESET=" "$color_result"

# ── 6. Status pane: _pad_v / _rule_v ─────────────────────────────────────────

echo ""
echo "== _pad_v / _rule_v =="

_pad_v p "abc" 6;              assert_eq "pads short string"      "abc   " "$p"
_pad_v p "abcdef" 6;           assert_eq "exact width untouched"  "abcdef" "$p"
_pad_v p "abcdefgh" 6;         assert_eq "truncates with ellipsis" "abcde…" "$p"
_pad_v p "" 3;                 assert_eq "empty pads to width"    "   "    "$p"
_rule_v r 5;                   assert_eq "rule width"             "─────"  "$r"

# Multi-byte must pad by character, not byte, or every row misaligns.
_pad_v p "●" 3;                assert_eq "multibyte pads by char" "●  "    "$p"

# ── 7. Status pane: _clean_line ──────────────────────────────────────────────

echo ""
echo "== _clean_line =="

_clean_line "   hello   world  ";  assert_eq "trims and squeezes"   "hello world" "$CLEANED"
_clean_line "⏺ Reading file";      assert_eq "strips assistant mark" "Reading file" "$CLEANED"
_clean_line "❯ typed text";        assert_eq "strips prompt mark"    "typed text"  "$CLEANED"

# ── 8. Status pane: _is_chrome ───────────────────────────────────────────────

echo ""
echo "== _is_chrome =="

is_chrome() { _is_chrome "$1" && echo yes || echo no; }

assert_eq "blank is chrome"        "yes" "$(is_chrome "     ")"
assert_eq "box rule is chrome"     "yes" "$(is_chrome "──────────────")"
assert_eq "input line is chrome"   "yes" "$(is_chrome "❯ do the thing")"
assert_eq "hint bar is chrome"     "yes" "$(is_chrome "  ⏵⏵ accept edits on (shift+tab to cycle) · ← for agents")"
assert_eq "spinner summary chrome" "yes" "$(is_chrome "✻ Cogitated for 4m 5s")"
assert_eq "survey is chrome"       "yes" "$(is_chrome "● How is Claude doing this session? (optional)")"
assert_eq "prose is not chrome"    "no"  "$(is_chrome "  the RSVP check is now backed by the real service")"
# Regression: prose must not be eaten by the "<glyph> <word> for <N>" rule.
assert_eq "prose w/ 'for N' kept"  "no"  "$(is_chrome "I ran for 3 hours")"

# ── 9. Status pane: _classify_pane ───────────────────────────────────────────

echo ""
echo "== _classify_pane =="

# Fixtures captured from a live Claude Code 2.1.x pane.
pane_idle='  per Copilot'"'"'s review.

✻ Worked for 30s

────────────────────────────────────────
❯ did copilot resolve the comment?
────────────────────────────────────────
  ⏵⏵ accept edits on (shift+tab to cycle) · ← for agents'

pane_working='⏺ Bash(echo hello)
  ⎿  hello
✢ Meandering… (4s · ↓ 65 tokens)
────────────────────────────────────────
❯
────────────────────────────────────────
  ⏸ manual mode on · esc to interrupt · ← for agents'

pane_input=' Do you want to create foo.txt?
 ❯ 1. Yes
   2. Yes, allow all edits during this session (shift+tab)
   3. No
 Esc to cancel · Tab to amend'

pane_trust=' Quick safety check: Is this a project you created or one you trust?
 ❯ 1. Yes, I trust this folder
   2. No, exit
 Enter to confirm · Esc to cancel'

pane_shell='bryandoss@host worktree % '

_classify_pane "$pane_idle"
assert_eq "idle state"    "idle" "$A_STATE"
assert_eq "idle last output" "per Copilot's review." "$A_LINE"

_classify_pane "$pane_working"
assert_eq "working state" "working" "$A_STATE"
assert_contains "working shows spinner" "Meandering" "$A_LINE"

_classify_pane "$pane_input"
assert_eq "permission prompt is input" "input" "$A_STATE"
assert_eq "input shows question" "Do you want to create foo.txt?" "$A_LINE"

_classify_pane "$pane_trust"
assert_eq "trust prompt is input" "input" "$A_STATE"
assert_contains "trust shows question" "trust this folder" "$A_LINE"

_classify_pane "$pane_shell"
assert_eq "bare shell is not an agent" "shell" "$A_STATE"

_classify_pane ""
assert_eq "empty pane is shell" "shell" "$A_STATE"

# Fixtures captured from a live codex-cli 0.144.0 pane. Codex uses "› " (U+203A)
# where Claude Code uses "❯" (U+276F), and different dialog trailers.
pane_codex_approval='  Would you like to run the following command?

  Environment: local

  Reason: Allow running the TypeScript checker outside the sandbox after Bun
  failed to write to its temp directory?

  $ bunx tsc -p apps/web/tsconfig.json --noEmit

› 1. Yes, proceed (y)
  2. Yes, and don'"'"'t ask again for commands that start with `bunx tsc` (p)
  3. No, and tell Codex what to do differently (esc)

  Press enter to confirm or esc to cancel'

pane_codex_trust='> You are in /tmp/demo
  Do you trust the contents of this directory? Working with untrusted contents
  comes with higher risk of prompt injection. Trusting the directory allows
  project-local config, hooks, and exec policies to load.
› 1. Yes, continue
  2. No, quit
  Press enter to continue'

pane_codex_working='• Working (2s • esc to interrupt)

› Summarize recent commits

  gpt-5.5 medium · /tmp/demo'

# Footer path may be ~-abbreviated (as captured live) or absolute.
pane_codex_idle='› write a story

• Here is a short story about a lighthouse.

› Summarize recent commits

  gpt-5.5 medium · ~/muxtree/worktrees/geogenesis/onboarding-checklist'

_classify_pane "$pane_codex_approval"
assert_eq "codex approval is input" "input" "$A_STATE"
assert_contains "codex approval shows reason" "Allow running" "$A_LINE"

_classify_pane "$pane_codex_trust"
assert_eq "codex trust prompt is input" "input" "$A_STATE"
assert_contains "codex trust shows question" "Do you trust" "$A_LINE"

_classify_pane "$pane_codex_working"
assert_eq "codex working state" "working" "$A_STATE"
assert_contains "codex working shows status" "Working (" "$A_LINE"

_classify_pane "$pane_codex_idle"
assert_eq "codex idle state" "idle" "$A_STATE"
assert_eq "codex idle last output" "Here is a short story about a lighthouse." "$A_LINE"

# ── 10. Status pane: _legend_lines ───────────────────────────────────────────

echo ""
echo "== _legend_lines =="

count_lines() { local n=0 l; while IFS= read -r l; do n=$((n+1)); done <<< "${1%$'\n'}"; echo "$n"; }

FRAME=""; _legend_lines 140
assert_eq "wide terminal: legend on one line" "1" "$(count_lines "$FRAME")"

FRAME=""; _legend_lines 90
assert_eq "narrow terminal: legend stacks" "2" "$(count_lines "$FRAME")"

FRAME=""; _legend_lines 90
assert_contains "legend explains state glyphs" "needs input" "$FRAME"
assert_contains "legend explains TERM column" "attached" "$FRAME"

# ── 11. cmd_status arg parsing ───────────────────────────────────────────────

echo ""
echo "== cmd_status arg parsing =="

# `|| true` must sit outside the subshell: die() calls exit, so it terminates
# the subshell before any `||` inside it could run.
_run_status() {
    (
        die() { echo "DIE: $*"; exit 1; }
        ensure_git_repo() { :; }
        load_config() { WORKTREE_DIR="/nonexistent"; }
        cmd_status "$@" 2>&1
    ) || true
}

result=$(_run_status --interval abc)
assert_contains "non-numeric interval rejected" "positive integer" "$result"

# Regression: `-n` as the last arg used to hit a bare `shift 2`, which fails
# under set -e and killed the script silently before any error message.
result=$(_run_status -n)
assert_contains "missing interval value rejected" "requires a value" "$result"

result=$(_run_status --interval 0)
assert_contains "zero interval rejected" "positive integer" "$result"

result=$(_run_status --bogus)
assert_contains "unknown status flag rejected" "Unknown option" "$result"

result=$(_run_status extra-arg)
assert_contains "positional arg rejected" "Unexpected argument" "$result"

# ── 12. Sourcing guard ───────────────────────────────────────────────────────

echo ""
echo "== sourcing guard =="

# Regression: sourcing used to forward the sourcing script's own arguments
# into muxtree's `main "$@"` -- `source muxtree` from a script invoked as
# `./test.sh delete foo --force` would have run the real cmd_delete.
guard_result=$(bash -c '
    source "'"$SCRIPT_DIR/muxtree"'" delete some-branch --force >/dev/null 2>&1
    echo "guard-ok"
')
assert_eq "sourcing never dispatches commands" "guard-ok" "$guard_result"

# ── 13. _git_stats (scratch repo) ────────────────────────────────────────────

echo ""
echo "== _git_stats =="

STATS_REPO="$TMPDIR_TEST/stats-repo"
mkdir -p "$STATS_REPO"
git -C "$STATS_REPO" init -q 2>/dev/null
_stats_commit() {
    git -C "$STATS_REPO" -c user.email=test@test -c user.name=test \
        -c commit.gpgsign=false commit -q "$@"
}
printf 'one\ntwo\n' > "$STATS_REPO/tracked.txt"
git -C "$STATS_REPO" add tracked.txt
_stats_commit -m init

printf 'one\nCHANGED\n' > "$STATS_REPO/tracked.txt"   # unstaged edit: +1 -1
mkdir -p "$STATS_REPO/newdir"
printf 'a\n' > "$STATS_REPO/newdir/a.txt"
printf 'b\n' > "$STATS_REPO/newdir/b.txt"

_git_stats "$STATS_REPO"
# Regression: without -uall an untracked directory shows as one "?? newdir/"
# entry, undercounting the 2 files inside it.
assert_eq "untracked dir counts its files" "3" "$G_FILES"
assert_eq "insertions vs HEAD"             "1" "$G_INS"
assert_eq "deletions vs HEAD"              "1" "$G_DEL"

# Regression: staged + unstaged edits used to be summed (diff + diff --cached),
# double-counting the staged hunk. One file, staged and edited again on top.
git -C "$STATS_REPO" add tracked.txt
printf 'one\nCHANGED\nthree\n' > "$STATS_REPO/tracked.txt"

_git_stats "$STATS_REPO"
assert_eq "staged+unstaged file counts once"     "3" "$G_FILES"
assert_eq "staged changes not double-counted +"  "2" "$G_INS"
assert_eq "staged changes not double-counted -"  "1" "$G_DEL"

# A clean worktree is all zeros.
git -C "$STATS_REPO" add -A
_stats_commit -m wip
_git_stats "$STATS_REPO"
assert_eq "clean worktree files" "0" "$G_FILES"
assert_eq "clean worktree +"     "0" "$G_INS"
assert_eq "clean worktree -"     "0" "$G_DEL"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Tests: $TESTS  Passed: $((TESTS - FAILURES))  Failed: $FAILURES"
echo "════════════════════════════════════════"

if [[ $FAILURES -gt 0 ]]; then
    exit 1
else
    echo "All tests passed."
fi
