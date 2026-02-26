aws-profile() {
  local profile
  profile=$(aws configure list-profiles | fzf) || return 1
  export AWS_PROFILE="$profile"
}

