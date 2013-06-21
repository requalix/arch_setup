## Upgrades

Upgrading should be possible without having to reinstall. The first step
towards this is to make the scripts in packages/setup/ run inside the chroot by
default (no need for the $TARGET variable everywhere). That way, the script
that calls these scripts should simply run them on the current system if TARGET
is not set.

In order to avoid globbering the user's changes if they exist during an
upgrade, I think we should just save the old files to whatever.backup by
convention.
