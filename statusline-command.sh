#!/usr/bin/env bash
# Claude Code statusLine command
# Reads JSON from stdin and outputs a status line modelled on the shell PS1.

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
[ -z "$cwd" ] && cwd=$(pwd)

aws_profile="${AWS_PROFILE:-None}"
user=$(whoami)
host=$(hostname -s)

printf "\033[32m(AWS: %s)\033[0m %s@%s:%s" "$aws_profile" "$user" "$host" "$cwd"
