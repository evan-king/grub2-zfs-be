
# Grub2 ZFS Boot Environments

Utilities to add support for maintaining multiple boot environments for
Linux root installations on ZFS.  Intended to work with environments based
on following [this guide](https://github.com/zfsonlinux/zfs/wiki/Ubuntu-16.04-Root-on-ZFS)
modified to split `/boot/grub` into a separate dataset shared across
boot environments and identifying boot environments as datasets with zfs
properties `mountpoint=/` and `canmount=noauto`.

This project is primarily an effort to satisfy a personal need
(See [Issue 5809](https://github.com/zfsonlinux/zfs/issues/5809)) in absence
of a mature `beadm`-like toolset for Ubuntu's current LTS release.

**Warning**: this is an experimental project with currently no participation
by experienced members of the ZOL project, package maintainers, or distribution
developers.  Use at your own risk.

## grub-mkconfig

At present the primary utility provided is a grub-mkconfig helper script
`11_linux_zfs`, built to run alongside/after and eventually replace
`/etc/grub.d/10_linux`.  In its current state, the script *only* supports
zfs roots with some menu entry details still hard-coded to my specific local
environment and configuration.

**Warning**: I have no prior experience scripting bootloader configuration
logic.  My goal is to *theoretically* restore full generality as reverse
-engineered from the original script, but only to test and maintain support
for my own systems and the narrow conditions they represent (bios not
efi, zfs and ext4 roots, systemd as init, Ubuntu 16.04 as distribution,
minimal to no variation in hardware or disc setup, and root device identified
by uuid).  Any path to maturity and stability will depend on the interest
and participation of more experienced systems developers, who may not
find original `10_linux` script nearly as objectionable as I do, nor extending
its functionality nearly as daunting.
