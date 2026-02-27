aws-profile() {
  local profile
  profile=$(aws configure list-profiles | fzf --preview 'awk '\''( "{}" == "default" && $1 == "[default]" ) || ( $1 == "[profile" && $2 == "{}]" ) { found = 1 ; print $0 ; next } found && $1 ~ /^\[.+$/ { exit } found { print $0 }'\'' ~/.aws/config') || return 1
  export AWS_PROFILE="$profile"
}
