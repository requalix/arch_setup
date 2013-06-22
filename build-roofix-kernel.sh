#!/bin/bash

# get the directory the script resides in
DIR=$(cd "$(dirname "$0")" ; pwd -P)

# remove files from previous builds
echo "[ secure roofix-kernel builder ]"
echo "- removing previous grsecurity/kernel versions"
rm -rf gr*
rm -rf core

# we must have an internet connection to continue
echo "- testing internet connectivity" 
if ! ping google.com -c 1 > /dev/null; then
    echo "ERROR: failed to ping google.com, are you connected to the internet?"
    exit
fi

# obtain the latest ArchBuildSystem (ABS) core kernel
echo "- fetching latest arch kernel core"
OUTPUT=$(ABSROOT=$DIR abs core/linux)
CORE_VERSION=$(head "$DIR/core/linux/PKGBUILD" |
               egrep -o '[0-9]\.[0-9]\.[0-9]')

# determine what version of grsecurity matches the kernel
echo "[ ARCH KERNEL CORE version $CORE_VERSION ]"
echo "- fetching compatible version of grsecurity"
GR_HTTP="http://grsecurity.net"
GR_PAGE=$(wget -q -O- "$GR_HTTP/test.php")
GR_LINK=$(echo $GR_PAGE |
          egrep -o "test/grsecurity\-[0-9]\.[0-9]\.[0-9]\-$CORE_VERSION\-[^ ]*.patch" |
          tr '\n' ' ' |
          awk '{print $1;}')
GR_VER=$(echo $GR_LINK |
         egrep -o "[0-9]\.[0-9]\.[0-9]" |
         tr '\n' ' ' |
         awk '{print $1;}')

if [ -z "$GR_VER" ]; then
    echo "ERROR: no compatible version of grsecurity patch found!"
    exit
fi

# determine what the gradm version is
echo "[ GR SECURITY is version $GR_VER ]"
echo "- checking gradm patch version"
GR_GRADM=$(echo $GR_PAGE |
           egrep -o "test/gradm\-$GR_VER\-[^ ]*.tar.gz" |
           tr '\n' ' ' |
           awk '{print $1;}')

# determine what the PaX version is
echo "- checking PaX version"
GR_PAX=$(echo $GR_PAGE |
         egrep -o "test/\-$CORE_VERSION\-[^ ]*.patch" |
         tr '\n' ' ' |
         awk '{print $1;}')

# pull all compatible patches
echo "[ patching kernel ]"
echo "- fetching grsecurity patch"
wget --quiet "$GR_HTTP/$GR_LINK"

if [ -n "$GR_GRADM" ]
then
    echo "- fetching gradm patch"
    wget --quiet "$GR_HTTP/$GR_GRADM"
else
    echo "WARNING: no compatible gradm patch found!"
fi

if [ -n "$GR_PAX" ]
then
    echo "- fetching PaX patch"
    wget --quiet "$GR_HTTP/$GR_PAX"
else
    echo "WARNING: no compatible PaX patch found!"
fi

# modify the kernel build script
# - enable multicore compilation using max number of cores in the system
# - add grsecurity patches to the patching function
echo "- configuring the kernel"
sed -i -e "s/{MAKEFLAGS} L/{MAKEFLAGS} -j$(nproc) L/" "$DIR/core/linux/PKGBUILD"
sed -i -e 's/pkgbase=linux/pkgbase=roofix/' "$DIR/core/linux/PKGBUILD"

echo "- applying patches..."
cd $DIR
for i in *; do
    if [[ "$i" == *.patch* ]]; then
        sed -i -e "/loglevel.patch\"/ a\
                   patch -Np1 -i \"$DIR/$i\"" "$DIR/core/linux/PKGBUILD"
    fi
done

# option 1 - BUILD KERNEL
read -p "Would you like to build the kernel now? (Y/n): " -n 1 -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "~"
    echo "> skipping kernel compilation"
else
    echo "~"
    cd "$DIR/core/linux"
    makepkg --asroot
fi

# option 2 - INSTALL KERNEL TO /BOOT
read -p "Would you like to install the kernel to the local machine? (y/N): " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "~"
    cp "$DIR/core/linux/linux.preset" "/etc/mkinitcpio.d/roofix.preset"
    pacman -U "$DIR/core/linux/roofix-$CORE_VERSION.tar.gz"
    mkinitcpio -gk "/boot/vmlinuz-roofix" 
    grub-mkconfig > '/boot/grub/grub.cfg'
else
    echo "~"
    echo "> skipping kernel boot installation"
fi

# option 3 - INSTALL GRANDM
read -p "Would you like to install gradm for managing RABC? (Y/n): " -n 1 -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "~"
    echo "> skipping gradm installation"    
else
    echo "~"
    GRADM_TAR=$(ls | egrep -o "gradm\-[^ ]*.tar.gz")
    tar xf "$DIR/$GRADM_TAR"
    cd "$DIR/gradm2"
    make -j$(nproc)
    make install
fi

# option 4 - INSTALL PAXCTL
PAXCTL=$(pacman -Q paxctl)
if [ -z "$PAXCTL" ]; then
    echo "WARNING: no paxctl package found!"
    read -p "Would you like to install paxctl from the AUR? (Y/n): " -n 1 -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "~"
        echo "> skipping paxctl installation"
    else
        pacaur --asroot -S paxctl
    fi
else
    echo "found $PAXCTL"
fi
