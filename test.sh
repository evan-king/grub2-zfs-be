#!/bin/bash
set -e

function findUser() {
    thisPID=$$
    origUser=$(whoami)
    thisUser=$origUser

    while [ "$thisUser" = "$origUser" ]
    do
        ARR=($(ps h -p$thisPID -ouser,ppid;))
        thisUser="${ARR[0]}"
        myPPid="${ARR[1]}"
        thisPID=$myPPid
    done

    getent passwd "$thisUser" | cut -d: -f1
}

echo "logged in: $(findUser)"

restore_grub_cfg() {
    cp "/boot/grub/grub.cfg-orig" "/boot/grub/grub.cfg"
}
cp "/boot/grub/grub.cfg" "/boot/grub/grub.cfg-orig"
trap restore_grub_cfg EXIT

cp "./15_linux_zfs.sh" "/etc/grub.d/15_linux_zfs"

out="/boot/grub/grub.cfg"
fail="$out.new"
rm "$fail" 2>/dev/null || true

update-grub

test -e "$fail" && out="$fail"

cat "$out" | sed '/### BEGIN \/etc\/grub.d\/15_linux_zfs ###/,/### END \/etc\/grub.d\/15_linux_zfs ###/!d' > "./current.sh"
chown $(findUser) ./current.sh
chmod u+rw ./current.sh