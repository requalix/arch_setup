#!/bin/bash

# get the directory the script resides in
DIR=$(cd "$(dirname "$0")" ; pwd -P)
cd "$DIR"

# we must have an internet connection to continue
echo "- testing internet connectivity" 
if ! ping google.com -c 1 > /dev/null; then
    echo "ERROR: failed to ping google.com, are you connected to the internet?"
    exit
fi

# install required dependicies
for dep in abs xmlto docbook-xsl kmod inetutils bc; do
    echo "checking dependency :: $dep"
    CHECK=$(pacman -Q "$dep")
    if [ -z "$CHECK" ]; then
        pacman -S "$dep"
    fi
done

# check for files from previous builds
echo "[ secure roofix-kernel builder ]"
CHECK=$(ls core 2>/dev/null)
if [ -n "$CHECK" ]; then
    echo "WARNING: previous build detected!"
    read -p "Would you like to remove previous build? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "> proceeding to other build options"
    else
        echo "- removing previous grsecurity/kernel versions"
        rm -rf gr*
        rm -rf core
        rm -rf pax*
    fi
fi

# obtain the latest ArchBuildSystem (ABS) core kernel, if required
CHECK=$(ls core 2>/dev/null)
if [ -z "$CHECK" ]; then
    echo "- fetching latest arch kernel core"
    OUTPUT=$(ABSROOT=$DIR abs core/linux)
fi

# find kernel core version
CORE_VERSION=$(head "$DIR/core/linux/PKGBUILD" |
               egrep -o '[0-9]\.[0-9]\.[0-9]')
echo "[ ARCH KERNEL CORE version $CORE_VERSION ]"

# determine what version of grsecurity matches the kernel
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

# check grsecurity version is compatible
if [ -z "$GR_VER" ]; then
    echo "ERROR: no compatible version of grsecurity patch found!"
    exit
else
    echo "[ GRSECURITY version $GR_VER ]"
fi

# determine what the gradm version is
echo "- checking gradm patch version"
GR_GRADM=$(echo $GR_PAGE |
           egrep -o "test/gradm\-$GR_VER\-[^ ]*.tar.gz" |
           tr '\n' ' ' |
           awk '{print $1;}')

# determine what the PaX version is
#echo "- checking PaX version"
#GR_PAX=$(echo $GR_PAGE |
#         egrep -o "test/pax-linux\-$CORE_VERSION\-[^ ]*.patch" |
#         tr '\n' ' ' |
#         awk '{print $1;}')

# pull all compatible patches (only download if they don't exist)
echo "[ patching kernel ]"

# download grsecurity
CHECK=$(ls 2>/dev/null | egrep -o "grsecurity\-$GR_VER*\-$CORE_VERSION\-[^ ]*.patch")
if [ -z "$CHECK" ]; then
    echo "- fetching compatible version of grsecurity"
    wget --quiet "$GR_HTTP/$GR_LINK"
else
    echo "- using local grsecurity patch"
fi

# download gradm
CHECK=$(ls 2>/dev/null | egrep -o "gradm\-$GR_VER\-[^ ]*.tar.gz")
if [ -z "$CHECK" ]; then
    if [ -n "$GR_GRADM" ]
    then
        echo "- fetching gradm patch"
        wget --quiet "$GR_HTTP/$GR_GRADM"
    else
        echo "WARNING: no compatible gradm patch found!"
    fi
else
    echo "- using local gradm patch"
fi

# download pax
#CHECK=$(ls 2>/dev/null | egrep -o "pax\-$CORE_VERSION\-[^ ]*.patch")
#if [ -z "$CHECK" ]; then
#    if [ -n "$GR_PAX" ]
#    then
#        echo "- fetching PaX patch"
#        wget --quiet "$GR_HTTP/$GR_PAX"
#    else
#        echo "WARNING: no compatible PaX patch found!"
#    fi
#else
#    echo "- using local PaX patch"
#fi

# modify the kernel build script
# - enable multicore compilation using max number of cores in the system
# - add grsecurity patches to the patching function
cd "$DIR/core/linux"
CHECK=$(ls 2>/dev/null | egrep -o "roofix\-$CORE_VERSION\-[^ ]*.tar.xz")
if [ -z "$CHECK" ]; then
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
fi

# option 1 - BUILD KERNEL
read -p "Would you like to build the kernel now? (Y/n): " -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "> skipping kernel compilation"
else
    cd "$DIR/core/linux"
    makepkg --asroot
fi

# option 2 - INSTALL KERNEL TO /BOOT
read -p "Would you like to install the kernel to the local machine? (y/N): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mv '/etc/mkinitcpio.d/roofix.preset' "/etc/mkinitcpio.d/linuxroofix.preset" 2>/dev/null
    pacman -U "$DIR/core/linux/roofix-$CORE_VERSION-1-x86_64.pkg.tar.xz"
    grub-mkconfig > '/boot/grub/grub.cfg'
else
    echo "> skipping kernel boot installation"
fi

# option 3 - INSTALL GRANDM
read -p "Would you like to install gradm for managing RABC? (Y/n): " -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "> skipping gradm installation"    
else
    cd "$DIR"
    GRADM_TAR=$(ls | egrep -o "gradm\-[^ ]*.tar.gz")
    tar xf "$DIR/$GRADM_TAR"
    cd "$DIR/gradm2"
    make -j$(nproc) --quiet
    make install
fi

# option 4 - INSTALL PAXCTL
PAXCTL=$(pacman -Q paxctl)
if [ -z "$PAXCTL" ]; then
    echo "WARNING: no paxctl package found!"
    read -p "Would you like to install paxctl from the AUR? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "> skipping paxctl installation"
    else
        pacaur --asroot --noconfirm -S paxctl
    fi
else
    echo "found $PAXCTL"
fi
