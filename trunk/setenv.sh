#!/bin/bash

INST_PREFIX="/opt/madisa/toolchain"

TARGET_ARCH=arm-linux-gnueabihf
TARGET_SYSROOT="/opt/madisa/rootfs/raspbian"
TARGET_GCC_VERSION=4.9.3
TARGET_BINUTILS_VERSION=2.25.1

PACKAGE_ID="-raspbian"

GCC_CONFIG_FLAGS="--with-arch=armv6 --with-fpu=vfp --with-float=hard"

export LD_LIBRARY_PATH="${INST_PREFIX}/lib"
export PKG_CONFIG_PATH="${INST_PREFIX}/lib/pkgconfig"
export PATH="${INST_PREFIX}/bin":$PATH

if [ "$1" = "--prefix" ]; then
    echo "$INST_PREFIX"
fi
