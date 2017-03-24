
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
`15_linux_zfs`, built to run alongside/after and eventually replace
`/etc/grub.d/10_linux`.  In its current state, the script *only* supports
zfs roots with some menu entry details still hard-coded to my specific
local environment and configuration.

Use the included test.sh script to non-destructively determine whether
your configuration is supported.  EFI booting is theoretically supported
but untested.  Due to the limited range of test environments and unstable
state, even when installed the script will not replace stock grub scripts
the entries they generate.  Boot-environment-specific entries will appear
after the stock entries.

## beadm-alt

Lightweight partial implementation of beadm that can list, create, destroy,
and activate boot environments.  (Activation requires `GRUB_DEFAULT=saved`
in `/etc/default/grub`.)

Supported options:
 - beadm list
 - beadm create [-a] [-e bename@snapname] bename
 - beadm destroy bename
 - beadm activate bename

Creating boot environments across pools is not supported, nor even is
creating a boot environment in a location separate from the origin dataset.
However, manually created boot environments in separate datasets will
be correctly understood so long as no collissions occur on dataset name.
