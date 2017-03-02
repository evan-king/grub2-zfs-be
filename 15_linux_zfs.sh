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

# get_distributor: void -> str
get_distributor() {
    if [ x$GRUB_DISTRIBUTOR = x ] ; then
        echo "GNU/Linux"
    else
        case $GRUB_DISTRIBUTOR in
            Ubuntu|Kubuntu) echo $GRUB_DISTRIBUTOR ;;
            *) echo "$GRUB_DISTRIBUTOR GNU/Linux" ;;
        esac
    fi
}

# get_recovery_flags: void -> str
get_recovery_flags() {
    if [ -x /lib/recovery-mode/recovery-menu ]; then
        flags=recovery
    else
        flags=single
    fi
    if [ x$ubuntu_recovery = x1 ]; then
        flags="$flags nomodeset"
    fi
    echo $flags
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
    dataset=$1 # syspool/ROOT/ubuntu
    tmppath=$(mktemp -d)
    # requires working temporary mount properties:
    # zfs mount -o mountpoint=$2 -o readonly=on $1
    mount -t zfs -o ro -o zfsutil $dataset $tmppath
    echo $tmppath
    
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
    dataset=$1
    
    # ensure root mounted
    premounted=$(zfs_property mounted $dataset)
    if [ x$premounted = xyes ]; then
        mountpath=$(zfs_property mountpoint $dataset)
    else
        mountpath=$(mount_root $dataset)
    fi
    
    # enumerate kernels
    kernels=$(list_kernels $mountpath)
    
    # choose most recent
    latestkernel=$(version_find_latest $kernels)
    
    # output_entry for most recent
    output_entry zfs simple $dataset $latestkernel 0
    
    # start submenu
    output_entry zfs menustart $dataset
    
    # for each kernel
    for i in $kernels; do
    
        # output advanced option
        output_entry zfs advanced $dataset "$i" 4
        
        # output recovery option
        if [ x${GRUB_DISABLE_RECOVERY} != xtrue ]; then
            output_entry zfs recovery $dataset "$i" 4
        fi
        
    done
    
    # end submenu
    output_entry zfs menuend $dataset
    
    # ensure tmp-mount unmounted
    if [ x$premounted != xyes ]; then
        umount_root $mountpath
    fi
}

output_entry() {
    fstype=$1 # zfs|btrfs|lvm|legacy (currently only supporting zfs)
    type=$2 # simple|advanced|recovery
    root=$3 # syspool/ROOT/ubuntu
    kernel=$4 # 4.4.0-64-generic
    indent=${5:-0} # 4
    
    deviceid=$GRUB_DEVICE_UUID
    rootname=$(echo $root | sed 's/.*\///g') # ubuntu
    rootdash=$(idstring $root) # syspool_root_ubuntu
    #rootdash=$(echo $root |  sed 's/\//-/g') # syspool-ROOT-ubuntu
    rootnopool=$(echo $root | sed 's/^[^/]*//g') # /ROOT/ubuntu
    distributor=$(get_distributor)
    
    label="$distributor ($rootname)"
    
    case $type in
        menustart)
            label="Advanced options for $label"
            entryid="gnulinux-$rootdash-$type-$deviceid"
            indent_multiline $indent "submenu '$label' \$menuentry_id_option $entryid {"
            return 0
            ;;
        menuend)
            indent_multiline $indent "}"
            return 0
            ;;
        recovery)
            label="$label, with Linux $kernel (recovery mode)"
            entryid="gnulinux-$rootdash-$kernel-$type-$deviceid"
            recovery=$(get_recovery_flags)
            ;;
        advanced)
            label="$label, with Linux $kernel"
            entryid="gnulinux-$rootdash-$kernel-$type-$deviceid"
            recovery=
            ;;
        simple|*)
            label=$label
            entryid="gnulinux-$rootdash-$type-$deviceid"
            recovery=
            ;;
    esac
    
    msgkernel=
    msginit=
    if [ x"$quiet_boot" = x0 ] || [ x"$type" != xsimple ]; then
        msgkernel="echo '$(gettext_printf "Loading Linux %s ..." ${kernel})'"
        msginit="echo '$(gettext_printf "Loading initial ramdisk ...")'"
    fi
    
    text=$(cat << EOF
menuentry '$label' $CLASS \$menuentry_id_option '$entryid' {
    recordfail
    load_video
    gfxmode \$linux_gfx_mode
    insmod gzio
    if [ x\$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
    insmod part_gpt
    insmod zfs
    set root='hd0,gpt1'
    if [ x\$feature_platform_search_hint = xy ]; then
      search --no-floppy --fs-uuid --set=root --hint-bios=hd0,gpt1 --hint-efi=hd0,gpt1 --hint-baremetal=ahci0,gpt1 $deviceid
    else
      search --no-floppy --fs-uuid --set=root $deviceid
    fi
    $msgkernel
    linux $rootnopool@/boot/vmlinuz-$kernel root=ZFS=$root ro $recovery net.ifnames=0 quiet splash \$vt_handoff
    $msginit
    initrd $rootnopool@/boot/initrd.img-$kernel
}
EOF
)

    indent_multiline "$indent" "${text}"
}

# generate entries for all roots
for i in $(list_zfs_roots); do
    output_zfs_root $i
done
