#!/bin/bash
set -e

# ultra-rudimentary substitute for real beadm utility
# 
# https://www.freebsd.org/cgi/man.cgi?beadm
# https://docs.oracle.com/cd/E23824_01/html/821-1462/beadm-1m.html
# 
# Currently (planned) supported options:
#  - beadm list
#  - beadm create [-a] [-e bename@snapname] bename
#  - beadm destroy bename
#  - beadm activate bename

# is_command: str -> errcode
get_command() {
    if [ "$(type -t "cmd_$1")" = "function" ]; then
        printf "cmd_$1"
    else
        printf "usage"
        return 1
    fi
}

# idstring: str -> str
idstring() {
    echo $1 \
        | tr 'A-Z' 'a-z' \
        | cut -d' ' -f1 \
        | LC_ALL=C sed 's,[^[:alnum:]_],_,g' \
        | sed "s/^_//g" \
        | sed "s/_$//g"
}

# list_zfs_roots: void -> [dataset]
list_zfs_roots() {
    # A dataset is considered a root if it has properties mountpoint=/ and canmount=noauto
    zfs list -H -o name,canmount,mountpoint -s creation | grep -oP ".*(?=\tnoauto\t/$)"
}

# list_primary_grub_ids: void -> [gunulinux-rpool_root_ubuntu-simple-4.4.0-62-generic-u1d5tr1ng]
list_primary_grub_ids() {
    cat /boot/grub/grub.cfg \
        | grep "\$menuentry_id_option" \
        | grep "gnulinux-.*-simple" \
        | sed -r 's/^.*\$menuentry_id_option\W'"'"'(.*)'"'"'.*$/\1/g'
}

# get_current_be: void -> bename
get_current_be() {
    mount | grep " on / " | sed -r "s;^.*/(.*) on / .*;\1;g"
}

# get_active_be: void -> bename
get_active_be() {
    saved_entry=""
    source /boot/grub/grubenv
    
    for gab_be in $(list_zfs_roots) ; do
        if echo "$saved_entry" | grep --silent $(idstring $gab_be) ; then
            echo $gab_be | sed "s;^.*/;;g"
            break
        fi
    done
}

# get_bebase: bename|void -> rpool/ROOT
# Show full path of specified or original boot environment
get_bebase() {
    gb_match=${1:-.*}
    gb_firstroot=$(list_zfs_roots | grep "/$gb_match\$" | head -1)
    if [ x$gb_firstroot = x ]; then
        echo "Unable to find named boot environment" >&2
        exit 1
    fi
    printf ${gb_firstroot%/*}
}

# snapshot_exists: fullsnapname -> 0|1
snapshot_exists() {
    zfs list -H -o name -t snapshot | grep "^$1$" > /dev/null
    return $?
}

# validate_active_be: void -> 0|1
# Return error if active boot environment is invalid or unspecified
validate_active_be() {
    saved_entry=""
    source /boot/grub/grubenv
    
    if [ x$saved_entry = x ] || [ x$(list_primary_grub_ids | grep "$saved_entry") = x ]; then
        return 1
    fi
    
    return 0
}

usage() {
    echo "TODO: explain"
}

# cmd_list: void -> str
# List all boot environment names
cmd_list() {
    list_zfs_roots | sed -e "s;^.*/;;g"
}

# cmd_create: [-a] [-e bename@snapname] bename -> str
cmd_create() {
    cc_clearsnap=0
    cc_activate=0
    cc_bename=${@:$#}
    
    while getopts "ae:" cc_pnam "$@"; do
        #echo "$cc_pnam: $OPTARG"
        case $cc_pnam in
            a) cc_activate=1 ;;
            e) cc_source=$OPTARG ;;
        esac
    done
    
    #echo "activate: $cc_activate, src: $cc_source, name: $cc_bename"
    
    cc_srcbe=$(echo $cc_source | sed "s/@.*$//g")
    if [ x$cc_srcbe = x ]; then
        cc_srcbe=$(list_zfs_roots | head -1 | sed "s;^.*/;;g")
        cc_srcsnap=$cc_bename
    fi
    
    cc_srcsnap=$(echo $cc_source | sed -r "s/.*@(.*)|.*/\1/g")
    if [ x$cc_srcsnap = x ]; then
        cc_srcsnap=$cc_bename;
        cc_clearsnap=1 # ensure automatic snapshot name will be fresh
    fi
    
    
    cc_base=$(get_bebase $cc_srcbe)
    cc_src="$cc_base/$cc_srcbe@$cc_srcsnap"
    cc_dest="$cc_base/$cc_bename"
    
    if [ x$cc_clearsnap = x1 ] && snapshot_exists $cc_src; then zfs destroy $cc_src; fi
    if ! snapshot_exists $cc_src; then zfs snapshot $cc_src; fi
    
    zfs clone -o mountpoint=/ -o canmount=noauto $cc_src $cc_dest
    echo "Boot environment created"
    
    update-grub
    
    if ! validate_active_be; then cc_activate=1; fi
    if [ x$cc_activate = x1 ]; then cmd_activate $cc_bename; fi
}

# cmd_destroy: bename -> str
cmd_destroy() {
    cd_be="$1"
    cd_be="$(get_bebase $cd_be)/$cd_be"
    
    if (( $(list_zfs_roots | wc -l) < 2 )); then
        echo "Cannot delete last boot environment" >&2
        exit 1
    fi
    
    zfs destroy $cd_be
    
    update-grub
    
    if ! validate_active_be; then cmd_activate; fi
}

# cmd_activate: bename|void -> str
# Activate the named or newest boot environment
cmd_activate() {
    ca_be=${1:-$(list_zfs_roots | tail -1 | sed "s;^.*/;;g")}
    ca_bepath="$(get_bebase $ca_be)/$ca_be"
    
    # get first entry with id matching root path
    ca_entry=$(list_primary_grub_ids | grep $(idstring $ca_bepath) | head -1)
    
    echo "Activated primary entry for $ca_be"
    
    grub-set-default $ca_entry
    
}

SUBCMD=$(get_command $1)
if [ $? ]; then shift; fi
CMDARGS="$@"

$SUBCMD $CMDARGS
