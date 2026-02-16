# aws-switch.sh - AWS CLI profile switcher (shell function)
#
# Usage (zsh/bash):
#   source /Users/marvelph/Developer/Projects/scripts/aws-switch.sh
#   aws-switch

aws-switch() {
    local -a profiles
    local p profile

    if ! command -v aws >/dev/null 2>&1; then
        echo "Error: 'aws' command is required." >&2
        return 1
    fi

    while IFS= read -r p; do
        [[ -n "$p" ]] && profiles+=("$p")
    done < <(aws configure list-profiles)

    if (( ${#profiles[@]} == 0 )); then
        echo "No AWS profiles found." >&2
        return 1
    fi

    if command -v fzf >/dev/null 2>&1; then
        profile="$(printf '%s\n' "${profiles[@]}" | fzf --prompt="Select AWS Profile> " --height=40% --reverse)"
    else
        echo "fzf not found; falling back to numbered selection." >&2
        select profile in "${profiles[@]}"; do
            [[ -n "${profile:-}" ]] && break
            echo "Invalid selection." >&2
        done
    fi

    if [[ -z "${profile:-}" ]]; then
        echo "No profile selected. AWS_PROFILE unchanged." >&2
        return 1
    fi

    export AWS_PROFILE="$profile"
    echo "Switched AWS_PROFILE to: $AWS_PROFILE"
}
