#!/bin/bash

INST_PREFIX="/opt/madisa/toolchain"

export LD_LIBRARY_PATH="${INST_PREFIX}/lib"
export PKG_CONFIG_PATH="${INST_PREFIX}/lib/pkgconfig"
export PATH="${INST_PREFIX}/bin":$PATH

if test "$1" = "--prefix" ; then
    echo "$INST_PREFIX"
    exit 0
fi

if test "$1" = ""; then
    TARGET_ARCH=arm-linux-gnueabihf
    TARGET_GCC_VERSION=4.9.3
    TARGET_BINUTILS_VERSION=2.25.1
    TARGET_NAME="raspbian"
    GCC_CONFIG_FLAGS="--with-arch=armv6 --with-fpu=vfp --with-float=hard"

else
    if test -f ${TOPDIR}/configs/$1; then

	. ${TOPDIR}/configs/$1

    fi
fi

TARGET_SYSROOT="$(dirname $INST_PREFIX)/rootfs/$TARGET_NAME"
PACKAGE_ID="_$TARGET_NAME"
