# aws-switch.sh - AWS CLI profile switcher (shell function)
#
# Usage:
#   source /Users/marvelph/Developer/Projects/scripts/aws-switch.sh
#   aws-switch

_aws_switch_choose_one() {
    local prompt="$1"
    shift
    local -a items=("$@")
    local choice rc=0

    if (( ${#items[@]} == 0 )); then
        return 1
    fi

    if command -v fzf >/dev/null 2>&1; then
        choice="$(printf '%s\n' "${items[@]}" | fzf --prompt="$prompt" --height=40% --reverse)" || rc=$?
        case "$rc" in
            0) ;;
            1|130) return 2 ;;
            *) echo "Error: failed to select an item with fzf." >&2; return 1 ;;
        esac
        [[ -n "${choice:-}" ]] || return 2
        printf '%s\n' "$choice"
        return 0
    fi

    return 1
}

aws-switch() {
    local -a profiles
    local p profile rc

    if ! command -v aws >/dev/null 2>&1; then
        echo "Error: 'aws' command is required." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: 'fzf' command is required." >&2
        return 1
    fi

    while IFS= read -r p; do
        [[ -n "$p" ]] && profiles+=("$p")
    done < <(aws configure list-profiles)

    if (( ${#profiles[@]} == 0 )); then
        echo "No AWS profiles found." >&2
        return 1
    fi

    if profile="$(_aws_switch_choose_one "Select AWS Profile> " "${profiles[@]}")"; then
        :
    else
        rc=$?
        case "$rc" in
            2)
                echo "No profile selected. AWS_PROFILE unchanged." >&2
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    export AWS_PROFILE="$profile"
    echo "Switched AWS_PROFILE to: $AWS_PROFILE"
}
