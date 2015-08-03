#!/bin/bash

TOPDIR=$PWD

if test "$MAKE_ARGS" = ""; then
    MAKE_ARGS=-j5
fi

. setenv.sh

shift

PKG_DIR=/tmp/sdksysroot$$

mkdir -p ${PKG_DIR}/${TARGET_SYSROOT}

while test ! $1 = ""; do
    dpkg-deb -x $1 ${PKG_DIR}/${TARGET_SYSROOT}
    shift
done

echo $TARGET_ARCH

case $TARGET_ARCH in
x86_64*|aarch64*)
    rm -f ${PKG_DIR}/${TARGET_SYSROOT}/lib64
    ln -sf lib ${PKG_DIR}/${TARGET_SYSROOT}/lib64
    ;;
esac

if test -d ${PKG_DIR}/${TARGET_SYSROOT}/lib/tls; then
    for f in ${PKG_DIR}/${TARGET_SYSROOT}/lib/tls/*; do
	rm -f ${PKG_DIR}/${TARGET_SYSROOT}/lib/$(basename $f)
	mv $f ${PKG_DIR}/${TARGET_SYSROOT}/lib
    done
    rmdir ${PKG_DIR}/${TARGET_SYSROOT}/lib/tls
fi

if test -d ${PKG_DIR}/${TARGET_SYSROOT}/usr/lib/nptl; then
    for f in ${PKG_DIR}/${TARGET_SYSROOT}/usr/lib/nptl/*.a; do
	rm -f ${PKG_DIR}/${TARGET_SYSROOT}/usr/lib/$(basename $f)
	mv $f ${PKG_DIR}/${TARGET_SYSROOT}/usr/lib
    done
    rm -rf ${PKG_DIR}/${TARGET_SYSROOT}/usr/lib/nptl
fi

if test -d ${PKG_DIR}/${TARGET_SYSROOT}/usr/include/nptl; then
    cp -R ${PKG_DIR}/${TARGET_SYSROOT}/usr/include/nptl/* ${PKG_DIR}/${TARGET_SYSROOT}/usr/include
    rm -rf ${PKG_DIR}/${TARGET_SYSROOT}/usr/include/nptl
fi

find ${PKG_DIR}/${TARGET_SYSROOT}/usr/lib -type l | while read l; do
    case $(readlink $l) in
    /*)
	ln -sf ../..$(readlink $l) $l
	;;
    esac
done

if test "$(which xz)" = ""; then
    tar zcf ${TOPDIR}/${TARGET_ARCH}-sysroot_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.gz -C ${PKG_DIR} .
else
    tar Jcf ${TOPDIR}/${TARGET_ARCH}-sysroot_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.xz -C ${PKG_DIR} .
fi

rm -rf ${PKG_DIR}
