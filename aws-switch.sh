#!/usr/bin/env zsh

# aws-switch.sh - AWS CLI profile switcher (shell function)
#
# Usage:
#   source /Users/marvelph/Developer/Projects/scripts/aws-switch.sh
#   aws-switch

_aws_switch_choose_one() {
  emulate -L zsh
  setopt NO_UNSET PIPE_FAIL

  typeset prompt="$1"
  shift
  typeset -a items=("$@")
  typeset choice
  integer rc

  (( $#items > 0 )) || return 1

  if ! choice="$(printf '%s\n' "${items[@]}" | fzf --prompt="$prompt" --height=40% --reverse)"; then
    rc=$?
    case "$rc" in
      1|130) return 2 ;;
      *)
        print -u2 -- "Error: failed to select an item with fzf."
        return 1
        ;;
    esac
  fi

  [[ -n "$choice" ]] || return 2
  print -r -- "$choice"
}

aws-switch() {
  emulate -L zsh
  setopt NO_UNSET PIPE_FAIL

  typeset output profile
  integer rc
  typeset -a profiles

  if ! command -v -- aws >/dev/null 2>&1; then
    print -u2 -- "Error: 'aws' command is required."
    return 1
  fi
  if ! command -v -- fzf >/dev/null 2>&1; then
    print -u2 -- "Error: 'fzf' command is required."
    return 1
  fi

  if ! output="$(aws configure list-profiles)"; then
    print -u2 -- "Error: failed to list AWS profiles."
    return 1
  fi

  profiles=("${(@f)output}")
  profiles=("${(@)profiles:#}")

  if (( $#profiles == 0 )); then
    print -u2 -- "No AWS profiles found."
    return 1
  fi

  if profile="$(_aws_switch_choose_one "Select AWS Profile> " "${profiles[@]}")"; then
    :
  else
    rc=$?
    case "$rc" in
      2)
        print -u2 -- "No profile selected. AWS_PROFILE unchanged."
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  export AWS_PROFILE="$profile"
  print -- "Switched AWS_PROFILE to: $AWS_PROFILE"
}
