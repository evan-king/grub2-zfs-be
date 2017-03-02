#!/bin/bash
set -e

restore_grub_cfg() {
    cp "/boot/grub/grub.cfg-orig" "/boot/grub/grub.cfg"
}
cp "/boot/grub/grub.cfg" "/boot/grub/grub.cfg-orig"
trap restore_grub_cfg EXIT

cp "./15_linux_zfs.sh" "/etc/grub.d/15_linux_zfs"

update-grub

cp "/boot/grub/grub.cfg" "./current.sh"
