#! /bin/sh
set -e

# grub-mkconfig helper script.
# Copyright (C) 2006,2007,2008,2009,2010  Free Software Foundation, Inc.
#
# GRUB is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GRUB is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GRUB.  If not, see <http://www.gnu.org/licenses/>.

# CODING CONVENTIONS
# functions documented as "fn_name: void|arg1, arg2[, optarg3...] -> result"
# where args and results are named by description or semantic type
# args identified as [something] define an 'array-string' of something delimited by newlines
# variables are pseudo-locally-scoped by prefixing them with acronym of fn_name

datarootdir="/usr/share"
ubuntu_recovery="1"
quiet_boot="1"
quick_boot="1"
gfxpayload_dynamic="1"
vt_handoff="1"

. "${datarootdir}/grub/grub-mkconfig_lib"

CLASS="--class gnu-linux --class gnu --class os"
SUPPORTED_INITS="sysvinit:/lib/sysvinit/init systemd:/lib/systemd/systemd upstart:/sbin/upstart"

# report: formatstring, arg1... -> void
report() {
    r_format="$1"
    shift
    printf "$(gettext "$r_format\n")" "$@" >&2
}

# get_device kernelpath -> str
# GLOBALS: $GRUB_DEVICE, $GRUB_DEVICE_BOOT
get_device() {
    gd_kernelpath="$1"
    if [ x$gd_kernelpath = x/ ]; then
        printf "$GRUB_DEVICE"
    else
        printf "$GRUB_DEVICE_BOOT"
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
    grf_type=$1
    if [ x$grf_type != xrecovery ]; then
        return 0
    fi
    if [ -x /lib/recovery-mode/recovery-menu ]; then
        printf "recovery"
    else
        printf "single"
    fi
    if [ x$ubuntu_recovery = x1 ]; then
        printf " nomodeset"
    fi
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

# get_entry_label: mountpath[, type[, kernel]] -> str 
get_entry_label() {
    gel_mntpath=$1
    gel_type=${2:-simple}
    gel_init=$3
    gel_kernel=$4
    
    gel_version="$(get_kernel_version "$gel_kernel")"
    
    # build entry name
    gel_name=$(get_distributor)
    gel_pathkern="$(get_volpath "$gel_mntpath")"
    if [ x$gel_pathkern != x ]; then
        gel_name="$gel_name ($(get_device_label "$gel_mntpath")$gel_pathkern)"
    fi
    
    case $gel_type in
        menu)
            gettext_printf "Advanced options for %s" "$gel_name"
            ;;
        recovery)
            gettext_printf "%s, with Linux %s, recovery mode" "$gel_name" "$gel_version"
            ;;
        advanced)
            if [ x"$gel_init" != x ]; then
                gettext_printf "%s, with Linux %s, init %s" "$gel_name" "$gel_version" "$gel_init"
            else
                gettext_printf "%s, with Linux %s" "$gel_name" "$gel_version" 
            fi
            ;;
        *)
            printf "$gel_name"
            ;;
    esac
}

# get_entry_id: rootpath, type[, kernel] -> str
# GLOBALS: $GRUB_DEVICE_UUID
get_entry_id() {
    gei_rootpath=$1
    gei_type=$2
    gei_init=$3
    gei_kernel=$4
    
    printf "gnulinux-"
    if [ x"$gei_rootpath" != x ]; then printf "$(idstring "$(get_volpath "$gei_rootpath")")-"; fi
    printf "$gei_type-"
    if [ x"$gei_type" != xsimple ] && [ x"$gei_type" != xmenu ]; then printf "$gei_kernel-"; fi
    if [ x"$gei_init" != x ]; then printf "$gei_init-"; fi
    printf "$GRUB_DEVICE_UUID"
}

# get_grub_args: mountpath[, initpath] -> str
# GLOBALS: $GRUB_CMDLINE_LINUX, $GRUB_CMDLINE_LINUX_DEFAULT, $vt_handoff
get_grub_args() {
    gga_mntpath=${1:-/}
    gga_init="$2"
    
    # add subvol flag for btrfs roots
    if [ x$(get_fs_type "$gga_mntpath") = xbtrfs ]; then
        printf "rootflags=subvol=$(get_subvol "$gga_mntpath") "
    fi
    
    # add standard configured flags
    printf "$GRUB_CMDLINE_LINUX $GRUB_CMDLINE_LINUX_DEFAULT"
    
    # add init specification
    if [ x"$gga_init" != x ]; then
        printf " init=$gga_init"
    fi
    
    # add vt_handoff
    if [ x$vt_handoff = x1 ]; then printf " \$vt_handoff"; fi
}

# get_root_device: mntpath -> str
# GLOBALS: $GRUB_DEVICE, $GRUB_DEVICE_UUID, $GRUB_DISABLE_LINUX_UUID
get_root_device() {
    grd_mntpath=$1
    
    # zfs roots
    if [ x$(get_fs_type "$grd_mntpath") = xzfs ]; then
        printf "ZFS=$(get_volpath "$grd_mntpath")"
        return 0
    fi

    if [ x$GRUB_DEVICE_UUID = x ] || [ x$GRUB_DISABLE_LINUX_UUID = xtrue ] \
        || ! test -e "/dev/disk/by-uuid/$GRUB_DEVICE_UUID" \
        || uses_abstraction "${GRUB_DEVICE}" lvm
    then
        printf "$GRUB_DEVICE"
        return 0
    fi
    
    # default
    printf "UUID=$GRUB_DEVICE_UUID"
}

# get_device_label: mountpoint -> str
# GLOBALS: $GRUB_DEVICE
get_device_label() {
    gd_device="$1"
    "$grub_probe" --target=fs_label "$gd_device"
}

# get_subvol: mountpath -> str|void
get_subvol() {
    gs_mountpath=${1:-/}
    "$grub_mkrelpath" "$gs_mountpath"
}

# get_volpath: mountpath -> str|void
get_volpath() {
    gv_mountpath=${1:-/}
    printf "$(get_device_label "$gv_mountpath")$(get_subvol "$gv_mountpath")" | sed "s/@//g"
}

# get_kernel_version: [path] -> [version]
get_kernel_version() {
    echo "$1" | sed "s/[^-]*-//;s/[._-]\(pre\|rc\|test\|git\|old\|trunk\)/~\1/g"
}

# list_zfs_roots: void -> [dataset]
list_zfs_roots() {
    # A dataset is considered a root if it has properties mountpoint=/ and canmount=noauto
    zfs list -H -o name,canmount,mountpoint | grep -oP ".*(?=\tnoauto\t/$)"
}

# list_kernels: mountpath -> [kernelpath]
list_kernels() {
    lk_mntpath="$1"
    lk_machine="$(uname -m)"
    
    case x$lk_machine in
        xi?86|xx86_64)
            lk_paths="$lk_mntpath/boot/vmlinuz-* $lk_mntpath/vmlinuz-* $lk_mntpath/boot/kernel-*"
            ;;
        *)
            lk_paths="$lk_mntpath/boot/vmlinuz-* $lk_mntpath/boot/vmlinux-* $lk_mntpath/vmlinuz-* $lk_mntpath/vmlinux-* $lk_mntpath/boot/kernel-*"
            ;;
    esac
    
    lk_kernels=""
    for i in $lk_paths ; do
        if grub_file_is_not_garbage "$i"; then
            lk_kernels="$i${lk_kernels:+
$lk_kernels}"
        fi
    done
    
    lk_len=${#lk_mntpath}
    
    # output kernels
        # strip out tmproot prefix
        # put kernels in version order, latest to oldest
    printf "$lk_kernels" \
        | sed -e "s/^.\{${lk_len}\}//g" \
        | sort -r --version-sort
}

# list_extra_inits: basepath -> [initpath]
# GLOBALS: $SUPPORTED_INITS
list_extra_inits() {
    lei_base="${1:-/}"
    
    for lei_init in $SUPPORTED_INITS; do
        lei_path="${lei_init#*:}"
        if [ ! -x "$lei_base$lei_path" ]; then continue; fi
        if [ "$(readlink -f $lei_base/sbin/init)" = "$lei_path" ]; then continue; fi
        echo "$lei_init"
    done
}
# zfs_property: propname, dataset -> value
zfs_property() {
    zfs get -H -t filesystem -o value $1 $2
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

# mount_zfs_root: dataset -> mountpath
mount_zfs_root() {
    mzr_dataset=$1 # rpool/ROOT/rootds
    mzr_tmppath=$(mktemp -d)
    # requires working temporary mount properties:
    # zfs mount -o mountpoint=$2 -o readonly=on $1
    mount -t zfs -o ro -o zfsutil $mzr_dataset $mzr_tmppath
    printf $mzr_tmppath
}

# umount_zfs_root: mountpath -> void
umount_zfs_root() {
    uzr_tmppath=$1
    umount $uzr_tmppath
    rmdir $uzr_tmppath
}

# find_initrd: basepath, kernelversion -> [initrdpath]
# GLOBALS: $GENKERNEL_ARCH
find_initrd() {
    fi_basepath="$1"
    fi_version="$2"
    fi_alt_version="$(echo $fi_version | sed -e "s,\.old$,,g")"
    
    for fi_img in "initrd.img-${fi_version}" \
        "initrd-${fi_version}.img" \
        "initrd-${fi_version}.gz" \
        "initrd-${fi_version}" \
        "initramfs-${fi_version}.img" \
        "initrd.img-${fi_alt_version}" \
        "initrd-${fi_alt_version}.img" \
        "initrd-${fi_alt_version}" \
        "initramfs-${fi_alt_version}.img" \
        "initramfs-genkernel-${fi_version}" \
        "initramfs-genkernel-${fi_alt_version}" \
        "initramfs-genkernel-${GENKERNEL_ARCH}-${fi_version}" \
        "initramfs-genkernel-${GENKERNEL_ARCH}-${fi_alt_version}"
    do
        if test -e "$fi_basepath/${fi_img}" ; then
            #report "  Found initrd image: %s" "$fi_img"
            printf "$fi_img"
            return 0
        fi
    done
}

# indent_lines: int, [line] -> [indented_line]
indent_lines() {
    im_numspaces="$1"
    im_text="$2"
    
    im_spaces=$(printf %0${im_numspaces}s)
    
(cat <<END
$im_text
END
) | sed "s/^/$im_spaces/"

}

# strip_blank_lines: [str] -> [str]
strip_blank_lines() {
    sbl_text="$1"
(cat <<END
$sbl_text
END
) | sed '/^\s*$/d'
}

# get_volume_mountpoint: dataset -> path
get_volume_mountpoint() {
    gvm_volume="$1"
    
    mount \
        | grep "$gvm_volume" \
        | grep "$gvm_volume" \
        | grep -oP "(?<= on ).*(?= type )"
}

# output_zfs_root: dataset -> void
output_zfs_root() {
    ozr_dataset=$1 # rpool/ROOT/rootds
    report "Found ZFS root: %s" $ozr_dataset
    
    # ensure root mounted
    ozr_premounted=$(zfs_property mounted $ozr_dataset)
    if [ x$ozr_premounted = xyes ]; then
        ozr_mountpath=$(get_volume_mountpoint $ozr_dataset)
    else
        ozr_mountpath=$(mount_zfs_root $ozr_dataset)
    fi
    
    # enumerate kernels
    ozr_kernels=$(list_kernels $ozr_mountpath)
    
    # choose most recent
    ozr_latestkernel=$(version_find_latest $ozr_kernels)
    
    # output_entry for most recent
    output_entry "$ozr_mountpath" simple $ozr_latestkernel
    
    # start submenu
    echo "submenu '$(get_entry_label "$ozr_mountpath" menu)' \$menuentry_id_option $(get_entry_id "$ozr_mountpath" menu) {"
    
    # for each kernel
    for ozr_kern in $ozr_kernels; do
        report "  Found linux image: %s" "$ozr_kern"
    
        # output advanced option
        output_entry "$ozr_mountpath" advanced "$ozr_kern" "" 4
        
        # output additional advanced options for alternate inits
        for ozr_init in "$(list_extra_inits "$ozr_mountpath")"; do
            output_entry "$ozr_mountpath" advanced "$ozr_kern" "$ozr_init" 4
        done
        
        # output recovery option
        if [ x${GRUB_DISABLE_RECOVERY} != xtrue ]; then
            output_entry "$ozr_mountpath" recovery "$ozr_kern" "" 4
        fi
        
    done
    
    # end submenu
    echo "}"
    
    # ensure tmp-mount unmounted
    if [ x$ozr_premounted != xyes ]; then
        umount_zfs_root $ozr_mountpath
    fi
}

# boot_msg: type, msg[, arg...] -> str|void
# GLOBALS: $quiet_boot
boot_msg() {
    b_type="$1"
    b_msg="$2"
    shift
    shift
    
    if [ "x$quiet_boot" = x0 ] || [ "x$b_type" != xsimple ]; then
        printf "echo '$(gettext "$b_msg")'" "$@"
    fi
}

# get_fs_type: mountpath -> fstype
get_fs_type() {
    gft_mntpath=${1:-/}
    ${grub_probe} --target=fs "$gft_mntpath"
}

# output_entry: mountpath, type, kernelpath[, init[, indent]] -> str
output_entry() {
    oe_mntpath="$1"
    oe_type="$2" # simple|advanced|recovery
    oe_kernel="$3" # /boot/vmlinuz-4.4.0-64-generic[.efi.signed]
    oe_init="$4" # systemd:/lib/systemd/init
    oe_indent="${5:-0}" # 0|4
    
    # switch to efi (is this redundant?)
    if test -d $oe_mntpath/sys/firmware/efi && test -e "$oe_mntpath$oe_kernel.efi.signed"; then
        oe_kernel="$oe_kernel.efi.signed"
    fi
    
    oe_init_type=${oe_init%:*}
    oe_version="$(get_kernel_version "$oe_kernel")"
    oe_label="$(get_entry_label "$oe_mntpath" "$oe_type" "$oe_init_type" "$oe_kernel")"
    oe_entryid="$(get_entry_id "$oe_mntpath" "$oe_type" "$oe_init_type" "$oe_version")"
    oe_pathboot="$("$grub_mkrelpath" "$(dirname "$oe_mntpath$oe_kernel")")"
    oe_initrd="$(find_initrd "$oe_mntpath$(dirname "$oe_kernel")" "$oe_version")"
    oe_devroot="$(get_root_device "$oe_mntpath")"
    oe_args="$(get_grub_args "$oe_mntpath" "${oe_init#*:}")"
    
    oe_text=$(cat << EOF
$(get_recordfail)
$(get_videoload)
$(get_gfxmode "$oe_type")
insmod gzio
if [ x\$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
$(prepare_grub_to_access_device $(get_device $(dirname "$oe_kernel")))
$(boot_msg "$oe_type" "Loading Linux %s ..." $oe_version)
linux $oe_pathboot/$(basename $oe_kernel) root=$oe_devroot ro $(get_recovery_flags $oe_type) $oe_args
$(boot_msg "$oe_type" "Loading initial ramdisk ...")
initrd $oe_pathboot/$oe_initrd
EOF
)
    
    indent_lines "$oe_indent" "
menuentry '$oe_label' $CLASS \$menuentry_id_option '$oe_entryid' {
$(indent_lines 4 "$oe_text")
}
"
}


if [ "$(which zfs)" != "" ]; then

    # generate entries for all zfs roots
    for i in $(list_zfs_roots); do
        output_zfs_root $i
    done
    
fi
