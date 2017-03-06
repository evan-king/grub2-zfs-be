#! /bin/sh
set -e

# REMOVE WHEN TESTING DONE
. "/etc/default/grub"

prefix="/usr"
exec_prefix="/usr"
datarootdir="/usr/share"
ubuntu_recovery="1"
quiet_boot="1"
quick_boot="1"
gfxpayload_dynamic="1"
vt_handoff="1"

. "${datarootdir}/grub/grub-mkconfig_lib"

CLASS="--class gnu-linux --class gnu --class os"
SUPPORTED_INITS="sysvinit:/lib/sysvinit/init systemd:/lib/systemd/systemd upstart:/sbin/upstart"
MOUNT_BASE=

# get_device dirname? -> str
# GLOBALS: $GRUB_DEVICE, $GRUB_DEVICE_BOOT
get_device() {
    if [ x$dirname = x/ ]; then
        printf $GRUB_DEVICE
    else
        printf $GRUB_DEVICE_BOOT
    fi
}

# get_distributor: void -> str
get_distributor() {
    if [ x$GRUB_DISTRIBUTOR = x ] ; then
        printf "GNU/Linux"
    else
        case $GRUB_DISTRIBUTOR in
            Ubuntu|Kubuntu) printf $GRUB_DISTRIBUTOR ;;
            *) printf "$GRUB_DISTRIBUTOR GNU/Linux" ;;
        esac
    fi
}

# get_recovery_flags: type -> str
# GLOBALS: $ubuntu_recovery
get_recovery_flags() {
    type=$1
    if [ x$type != xrecovery ]; then
        return 0
    fi
    if [ -x /lib/recovery-mode/recovery-menu ]; then
        flags=recovery
    else
        flags=single
    fi
    if [ x$ubuntu_recovery = x1 ]; then
        flags="$flags nomodeset"
    fi
    printf $flags
}

# get_recordfail: void -> str
# GLOBALS: $quick_boot
get_recordfail() {
    if [ x$quick_boot = x1 ]; then
        printf recordfail
    fi
}

# get_videoload: void -> str
# GLOBALS: $GRUB_PAYLOAD_LINUX
get_videoload() {
    if [ x$GRUB_GFXPAYLOAD_LINUX != xtext ]; then
        printf load_video
    fi
}

# get_gfxmode: type -> str
# GLOBALS: $GRUB_PAYLOAD_LINUX, $ubuntu_recovery, $gfxpayload_dynamic
get_gfxmode() {
    if ([ x$ubuntu_recovery = x0 ] || [ x$type != xrecovery ]) && \
        ([ x$GRUB_GFXPAYLOAD_LINUX != x ] || [ x$gfxpayload_dynamic = x1 ]); then
        printf "gfxmode \$linux_gfx_mode"
    fi
}

# get_label: name[, type[, kernel]] -> str 
get_label() {
    name=$1
    type=$2
    kernel=$3
    
    case $type in
        menu)
            gettext_printf "Advanced options for %s" $name
            ;;
        recovery)
            gettext_printf "%s, with Linux %s, recovery mode" $name $kernel
            ;;
        advanced)
            gettext_printf "%s, with Linux %s" $name $kernel
            ;;
        *)
            printf "$name"
            ;;
    esac
}

# get_grub_args: void -> str
# GLOBALS: $GRUB_CMDLINE_LINUX, $GRUB_CMDLINE_LINUX_DEFAULT
get_grub_args() {
    echo "$GRUB_CMDLINE_LINUX $GRUB_CMDLINE_LINUX_DEFAULT"
}

# get_entry_id: prefix, type[, kernel] -> str
# TODO: abstract out $GRUB_DEVICE_UUID
get_entry_id() {
    prefix=$1
    type=$2
    kernel="-$3"
    if [ x$type = xsimple ] || [ x$type = xmenu ]; then
        kernel=
    fi
    echo "$prefix-$type$kernel-$GRUB_DEVICE_UUID"
}

# list_zfs_roots: void -> [dataset]
list_zfs_roots() {
    # A dataset is considered a root if it has properties mountpoint=/ and canmount=noauto
    zfs list -H -o name,canmount,mountpoint | grep -oP ".*(?=\tnoauto\t/$)"
}

# list_kernels: root -> [kernel]
list_kernels() {
    tmproot=$1
    kernels=$(ls -tr $tmproot/boot/vmlinuz-* | grep -oP "(?<=vmlinuz-)\S+")
    
    # output in version order, latest to oldest
    echo "${kernels}" | sort -r --version-sort
}

# zfs_property: propname, dataset -> value
zfs_property() {
    zfs get -H -t filesystem -o value $1 $2
}

# idstring: str -> str
idstring() {
    echo $1 | tr 'A-Z' 'a-z' | cut -d' ' -f1|LC_ALL=C sed 's,[^[:alnum:]_],_,g'
}

# mount_root: dataset -> mountpath
mount_root() {
    dataset=$1 # rpool/ROOT/rootds
    tmppath=$(mktemp -d)
    # requires working temporary mount properties:
    # zfs mount -o mountpoint=$2 -o readonly=on $1
    mount -t zfs -o ro -o zfsutil $dataset $tmppath
    printf $tmppath
    
}

# umount_root: mountpath -> void
umount_root() {
    tmppath=$1
    umount $tmppath
    rmdir $tmppath
}

# indent_multiline: int, "${str}" -> indented_text
indent_multiline() {
    numspaces=$1
    text=$2
    
    spaces=$(printf %0${1}s)
    
(cat <<END
$text
END
) | sed "s/^/$spaces/"

}

# output_zfs_root: dataset -> void
output_zfs_root() {
    dataset=$1 # rpool/ROOT/rootds
    
    # ensure root mounted
    premounted=$(zfs_property mounted $dataset)
    if [ x$premounted = xyes ]; then
        mountpath=$(zfs_property mountpoint $dataset)
    else
        mountpath=$(mount_root $dataset)
    fi
    MOUNT_BASE=$mountpath
    
    # enumerate kernels
    kernels=$(list_kernels $mountpath)
    
    # choose most recent
    latestkernel=$(version_find_latest $kernels)
    
    # output_entry for most recent
    output_entry zfs simple $dataset $latestkernel 0
    
    # start submenu
    echo "submenu '$(get_label $(get_zfs_name $dataset) menu)' \$menuentry_id_option $(get_entry_id gnulinux menu) {"
    
    # for each kernel
    for i in $kernels; do
    
        # output advanced option
        output_entry zfs advanced $dataset "$i" 4
        
        # output recovery option
        if [ x${GRUB_DISABLE_RECOVERY} != xtrue ]; then
            output_entry zfs recovery $dataset "$i" 4
        fi
        
    done
    
    MOUNT_BASE=
    
    # end submenu
    echo "}"
    
    # ensure tmp-mount unmounted
    if [ x$premounted != xyes ]; then
        umount_root $mountpath
    fi
}

# boot_msg: str[, arg...] -> str|void
# GLOBALS: $quiet_boot
boot_msg() {
    msg="$1"
    shift
    if [ x"$quiet_boot" = x0 ] || [ x"$type" != xsimple ]; then
        printf "echo '$(gettext "$msg")'" "$@"
    fi
}

# get_zfs_name: str
get_zfs_name() {
    root=$1
    echo "$(get_distributor) ($(echo $root | sed 's/.*\///g'))" # Ubuntu (rootds)
}

# output_entry: fstype, type, root, kernel[, indent] -> str
output_entry() {
    fstype=$1 # zfs|btrfs|lvm|legacy (currently only supporting zfs)
    type=$2 # simple|advanced|recovery
    root=$3 # zfs: rpool/ROOT/rootds, *: ?
    kernel=$4 # 4.4.0-64-generic[.efi.signed]
    indent=${5:-0} # 0|4
    
    case $fstype in
        zfs)
            pathboot=$(echo $root | sed 's/^[^/]*//g')@/boot # /ROOT/rootds@/boot
            entryid="$(get_entry_id gnulinux-$(idstring $root) $type $kernel)"
            name="$(get_distributor) ($(echo $root | sed 's/.*\///g'))" # Ubuntu (rootds)
            ;;
        *)
            pathboot="/boot"
            entryid="$(get_entry_id gnulinux $type $kernel)"
            name="$(get_distributor)" # Ubuntu
            ;;
    esac
    
    
    # kernel already contains efi suffix
    efisuffix=
    if test -d $MOUNT_BASE/sys/firmware/efi && test -e "$MOUNT_BASE/boot/vmlinuz-$kernel.efi.signed"; then
        efisuffix=".efi.signed"
    fi
    
    text=$(cat << EOF
$(get_recordfail)
$(get_videoload)
$(get_gfxmode $type)
insmod gzio
if [ x\$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
$(prepare_grub_to_access_device $(get_device))
$(boot_msg "Loading Linux %s ..." $kernel)
linux $pathboot/vmlinuz-$kernel root=ZFS=$root ro $(get_recovery_flags $type) $(get_grub_args) \$vt_handoff
$(boot_msg "Loading initial ramdisk ...")
initrd $pathboot/initrd.img-$kernel
EOF
)

    indent_multiline $indent "
menuentry '$(get_label $name $type $kernel)' $CLASS \$menuentry_id_option '$entryid' {
$(indent_multiline 4 "$text")
}"
}


#if [ "$(which zfs)" != "" ]; then

    # generate entries for all roots
    for i in $(list_zfs_roots); do
        output_zfs_root $i
    done
    
#fi


