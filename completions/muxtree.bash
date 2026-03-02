# bash completion for muxtree

_muxtree_managed_branches() {
    local worktree_dir repo_name wt_base
    worktree_dir="$HOME/worktrees"
    local config_dir="${MUXTREE_CONFIG_DIR:-$HOME/.muxtree}"
    local config_file="$config_dir/config"

    # Load worktree_dir from global config
    if [[ -f "$config_file" ]]; then
        local val
        val=$(grep -E '^worktree_dir=' "$config_file" 2>/dev/null | head -1 | cut -d= -f2-)
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        [[ -n "$val" ]] && worktree_dir="$val"
    fi

    # Override with project-local config
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return
    if [[ -f "$repo_root/.muxtree" ]]; then
        local val
        val=$(grep -E '^worktree_dir=' "$repo_root/.muxtree" 2>/dev/null | head -1 | cut -d= -f2-)
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        [[ -n "$val" ]] && worktree_dir="$val"
    fi

    worktree_dir="${worktree_dir/#\~/$HOME}"
    repo_name=$(basename "$repo_root")
    wt_base="$worktree_dir/$repo_name"

    git worktree list 2>/dev/null | while IFS= read -r line; do
        local wt_dir branch
        wt_dir=$(echo "$line" | awk '{print $1}')
        branch=$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')
        [[ -n "$branch" ]] || continue
        [[ "$wt_dir" == "$wt_base"/* ]] || continue
        echo "$branch"
    done
}

_muxtree_git_branches() {
    git branch -a --format='%(refname:short)' 2>/dev/null
}

_muxtree() {
    local cur prev words cword
    _init_completion || return

    local commands="init config new list ls delete rm sessions s help version"
    local session_actions="open launch start close kill stop relaunch restart attach"

    # Top-level command completion
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi

    local cmd="${words[1]}"

    case "$cmd" in
        init)
            COMPREPLY=($(compgen -W "--local -l" -- "$cur"))
            ;;
        config|list|ls|help|version)
            # No further completions
            ;;
        new)
            case "$prev" in
                --from)
                    local branches
                    branches=$(_muxtree_git_branches)
                    COMPREPLY=($(compgen -W "$branches" -- "$cur"))
                    ;;
                --run)
                    COMPREPLY=($(compgen -W "claude codex opencode" -- "$cur"))
                    ;;
                *)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--from --run --bg" -- "$cur"))
                    fi
                    ;;
            esac
            ;;
        delete|rm)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--force -f" -- "$cur"))
            else
                local branches
                branches=$(_muxtree_managed_branches)
                COMPREPLY=($(compgen -W "$branches" -- "$cur"))
            fi
            ;;
        sessions|s)
            # Determine position within the sessions subcommand
            # words[0]=muxtree words[1]=sessions words[2]=action words[3]=branch ...
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$session_actions" -- "$cur"))
                return
            fi

            local action="${words[2]}"

            if [[ $cword -eq 3 ]]; then
                # Branch name position
                local branches
                branches=$(_muxtree_managed_branches)
                COMPREPLY=($(compgen -W "$branches" -- "$cur"))
                return
            fi

            # Position 4+ depends on the action
            case "$action" in
                open|launch|start|relaunch|restart)
                    case "$prev" in
                        --run)
                            COMPREPLY=($(compgen -W "claude codex opencode" -- "$cur"))
                            ;;
                        *)
                            if [[ "$cur" == -* ]]; then
                                COMPREPLY=($(compgen -W "--run --bg" -- "$cur"))
                            fi
                            ;;
                    esac
                    ;;
                attach)
                    if [[ $cword -eq 4 ]]; then
                        COMPREPLY=($(compgen -W "dev agent" -- "$cur"))
                    fi
                    ;;
            esac
            ;;
    esac
}

complete -F _muxtree muxtree
