#!/bin/sh

# ultra-rudimentary substitute for real beadm utility
# 
# https://www.freebsd.org/cgi/man.cgi?beadm
# https://docs.oracle.com/cd/E23824_01/html/821-1462/beadm-1m.html
# 
# Currently (planned) supported options:
#  - beadm create [-a] beName@snopshot
#  - beadm destroy beName
#  - beadm activate beName

# is_command: str -> errcode
get_command() {
    if [ "$(type "cmd_$1")" = "cmd_$1 is a shell function" ]; then
        printf "cmd_$1"
    else
        printf "usage"
        return 1
    fi
}

usage() {
    echo "usage:..."
}

cmd_create() {
    echo "args: $@";
}

cmd_destroy() {
    echo "args: $@";
}

cmd_activate() {
    echo "args: $@";
}

SUBCMD=$(get_command $1)
if [ $? ]; then shift; fi
CMDARGS="$@"

$SUBCMD $CMDARGS
