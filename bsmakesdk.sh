#!/bin/bash

TOPDIR=$PWD

if test "$MAKE_ARGS" = ""; then
    MAKE_ARGS=-j5
fi

. setenv.sh

shift

error() {
    echo "ERROR: $@"
    exit 1
}

PKG_DIR=/tmp/sdksysroot$$

mkdir -p ${PKG_DIR}/${TARGET_SYSROOT}

ARCH=""
OPTLIST=""

case ${TARGET_ARCH} in
arm*)		ARCH=armhf ;;
aarch64*)	ARCH=arm64 ;;
x86_64*)
    ARCH=amd64
    OPTLIST="libc6-dev-i386 libc6-dev-x32 libc6-i386 libc6-x32"
    ;;
*)
    error "Not supported arch $TARGET_ARCH" ;;
esac

LIST="libc6:${ARCH} libc6-dev:${ARCH} linux-libc-dev:${ARCH} $OPTLIST"
#" libgcc1:${ARCH} libgcc-5-dev:${ARCH} libstdc++6:${ARCH} libstdc++-5-dev:${ARCH}"

mkdir -p ${TOPDIR}/tmp/deb-${ARCH}

cd ${TOPDIR}/tmp/deb-${ARCH}

dpkg-architecture -i $ARCH || dpkg --add-architecture $ARCH

apt-get update
apt-get download $LIST

dpkg-architecture -i $ARCH || dpkg --remove-architecture $ARCH

for p in *.deb; do
    dpkg-deb -x $p ${PKG_DIR}/${TARGET_SYSROOT}
done

#case $TARGET_ARCH in
#x86_64*|aarch64*)
#    rm -f ${PKG_DIR}/${TARGET_SYSROOT}/lib64
#    ln -sf lib ${PKG_DIR}/${TARGET_SYSROOT}/lib64
#    ;;
#esac

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

DIRS=""

for d in /lib /lib32 /lib64 /libx32 /usr/lib /usr/lib32 /usr/lib64 /usr/libx32; do
    if test -d ${PKG_DIR}/${TARGET_SYSROOT}/$d; then
	DIRS="$DIRS ${PKG_DIR}/${TARGET_SYSROOT}/$d"
    fi
done

find $DIRS -type l | while read l; do
    case $(readlink $l) in
    /*)
	from="$(readlink $l)"
	ex="${PKG_DIR}/${TARGET_SYSROOT}"
	to="$(realpath -ms /${l/$ex})"
	todir=$(dirname $to)
	toname=$(basename $to)
	new=$(realpath -ms --relative-to=$todir $from)
	ln -sf $new $l
	;;
    esac
done

if test "$(which xz)" = ""; then
    tar zcf ${TOPDIR}/$(echo $TARGET_ARCH | sed 's/_/-/')-sysroot${PACKAGE_ID}_all.tar.gz -C ${PKG_DIR} .
else
    tar Jcf ${TOPDIR}/$(echo $TARGET_ARCH | sed 's/_/-/')-sysroot${PACKAGE_ID}_all.tar.xz -C ${PKG_DIR} .
fi

rm -rf ${PKG_DIR}
