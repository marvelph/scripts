# aws-switch.sh - AWS CLI プロファイル切替用関数

aws-switch() {
    PROFILES=$(aws configure list-profiles)
    if [ -z "$PROFILES" ]; then
        echo "No AWS profiles found."
        return 1
    fi

    PROFILE=$(echo "$PROFILES" | fzf --prompt="Select AWS Profile> ")
    if [ -z "$PROFILE" ]; then
        echo "No profile selected. AWS_PROFILE unchanged."
        return 1
    fi

    export AWS_PROFILE="$PROFILE"
    echo "Switched to AWS profile: $AWS_PROFILE"
}
