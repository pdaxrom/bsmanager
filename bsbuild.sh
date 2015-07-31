#!/bin/bash

TOPDIR=$PWD

if test "$MAKE_ARGS" = ""; then
    MAKE_ARGS=-j5
fi

. setenv.sh

INST_HOST_PREFIX=${TOPDIR}/tmp/hostinst

mkdir -p ${INST_HOST_PREFIX}/bin

export PATH=${INST_HOST_PREFIX}/bin:$PATH
export PKG_CONFIG_PATH="${INST_HOST_PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH"

TAR=tar

error() {
    echo "ERROR: $@"
    exit 1
}


download() {
    local file="$2"
    if [ "$file" = "" ]; then
	file=$(basename $1)
    fi
    if [ ! -e $file ]; then
	mkdir -p `dirname $file`
	echo "Downloading..."
	local opt
	case $1 in
	https*)
	    opt="--no-check-certificate"
	    ;;
	esac
	if wget $opt $1 -O $file ; then
	    return
	fi
	rm -f $file

	local mirror
	for mirror in "http://mirror.cctools.info/packages/src" "http://cctools.info/packages/src"; do
	    local f=${1/*\/}
	    if wget -c ${mirror}/${f} -O $file ; then
		return
	    fi
	    rm -f $file
	done

	error "downloading $PKG_URL"
    fi
}

get_dir() {
    case $1 in
    *.tar.gz) echo ${1/.tar.gz} ;;
    *.tar.bz2) echo ${1/.tar.bz2} ;;
    *.tar.xz) echo ${1/.tar.xz} ;;
    *.zip) echo ${1/.zip} ;;
    *) echo $1
    esac
}

build() {
    local prefix=$INST_PREFIX

    if test "$1" = "host"; then
	prefix=$INST_HOST_PREFIX
	shift
	export CPPFLAGS="-I${INST_HOST_PREFIX}/include"
	export LDFLAGS="-L${INST_HOST_PREFIX}/lib"
    else
	export CPPFLAGS="-I${INST_HOST_PREFIX}/include -I${INST_PREFIX}/include"
	export LDFLAGS="-L${INST_HOST_PREFIX}/lib -L${INST_PREFIX}/lib"
    fi
    
    local nodir
    if test "$1" = "nodir"; then
	nodir="y"
	shift
    fi

    local file="$1"
    local flags="$2"
    local patches="$3"
    local dir="$4"

    if [ "$dir" = "" ]; then
	dir=$(get_dir $file)
    fi

    test -f build/${dir}/install.status && return

    echo "Build $dir"

    ${TAR} xf "$file" -C build

    pushd .

    cd build/$dir

    if test -d ${TOPDIR}/patches/$dir; then
	for f in ${TOPDIR}/patches/$dir/*; do
	    patch -p1 < $f || error "patching sources"
	done
    fi

    if [ ! "$patches" = "" ]; then
	for f in $patches; do
	    patch -p1 < $f || error "patch $f for $file"
	done
    fi

    if test "$nodir" = ""; then
	mkdir buildme
	cd buildme

	eval ../configure --prefix=$prefix $flags || error "Configure $file"
    else
	eval ./configure --prefix=$prefix $flags || error "Configure $file"
    fi

    make ${MAKE_ARGS} || error "make $file"

    make install || error "make install $file"

    if test "$nodir" = ""; then
	touch ../install.status
    else
	touch ./install.status
    fi

    popd
}

cmake_build() {
    local file="$1"
    local flags="$2"
    local patches="$3"
    local dir="$4"

    if [ "$dir" = "" ]; then
	dir=$(get_dir $file)
    fi

    test -f ${dir}/install.status && return

    echo "Build $dir"

    tar xf "$file"

    pushd .

    cd $dir

    if [ ! "$patches" = "" ]; then
	for f in $patches; do
	    patch -p1 < $f || error "patch $f for $file"
	done
    fi

#    cmake ./ -DBUILD_TESTING:BOOL=OFF -DCMAKE_INSTALL_PREFIX=${INST_PREFIX} -DCMAKE_PREFIX_PATH=${INST_PREFIX} || error "Configure $file"
    cmake ./ -DBUILD_TESTING:BOOL=OFF -DCMAKE_PREFIX_PATH:PATH=${INST_PREFIX} -DCMAKE_INSTALL_PREFIX:PATH=${INST_PREFIX} || error "Configure $file"

    make ${MAKE_ARGS} || error "make $file"

    make install || error "make install $file"

    touch install.status

    popd
}

check_and_install_packages() {
    local packages=""
    local p

    for p in $@; do
    if ! $(dpkg -l | grep -q $p); then
        packages="$packages $p"
    fi
    done

    if test ! "$packages" = ""; then
	sudo apt-get update
	sudo apt-get -y install $packages
    fi
}

fix_target_libm() {
    if test -d ${TARGET_SYSROOT}/usr/lib/$TARGET_ARCH ; then
	pushd . &>/dev/null

	cd ${TARGET_SYSROOT}/usr/lib/$TARGET_ARCH

	local LINK=$(readlink libm.so)

	if test ! -e $LINK ; then
	    echo "Broken symlink for target libm.so"
	    sudo ln -sf ../../..$LINK libm.so
	fi

	popd &>/dev/null
    fi
}

check_and_install_packages build-essential pkg-config bzip2
#libxml-parser-perl cmake

fix_target_libm

mkdir -p tmp/build
cd tmp

if test "$(which xz)" = ""; then
    download http://tukaani.org/xz/xz-5.2.1.tar.gz
    download http://alpha.gnu.org/gnu/tar/tar-1.23.90.tar.gz
    build host xz-5.2.1.tar.gz
    build host tar-1.23.90.tar.gz
    TAR=${INST_HOST_PREFIX}/bin/tar
fi

download http://zlib.net/zlib-1.2.8.tar.xz
download https://gmplib.org/download/gmp/gmp-6.0.0a.tar.xz
download http://www.mpfr.org/mpfr-current/mpfr-3.1.3.tar.xz
download ftp://ftp.gnu.org/gnu/mpc/mpc-1.0.2.tar.gz
download http://isl.gforge.inria.fr/isl-0.15.tar.xz
download http://bugseng.com/products/ppl/download/ftp/releases/1.1/ppl-1.1.tar.xz
download http://www.bastoul.net/cloog/pages/download/cloog-0.18.3.tar.gz
#download http://www.bastoul.net/cloog/pages/download/cloog-parma-0.16.1.tar.gz
download http://ftp.gnu.org/gnu/binutils/binutils-${TARGET_BINUTILS_VERSION}.tar.bz2
download http://gcc.cybermirror.org/releases/gcc-${TARGET_GCC_VERSION}/gcc-${TARGET_GCC_VERSION}.tar.bz2

build host nodir zlib-1.2.8.tar.xz "--static"
build host gmp-6.0.0a.tar.xz "--enable-cxx --disable-shared" "" gmp-6.0.0
build host mpfr-3.1.3.tar.xz "--disable-shared"
build host mpc-1.0.2.tar.gz "--disable-shared"
build host isl-0.15.tar.xz "--disable-shared"
build host ppl-1.1.tar.xz "--disable-shared --with-gmp=$INST_HOST_PREFIX"
build host cloog-0.18.3.tar.gz "--disable-shared"
#build host cloog-parma-0.16.1.tar.gz "--disable-shared"
build binutils-${TARGET_BINUTILS_VERSION}.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror"
rm -rf ${INST_PREFIX}/include ${INST_PREFIX}/lib
build gcc-${TARGET_GCC_VERSION}.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror --enable-shared --disable-bootstrap --with-system-zlib \
--with-gmp=$INST_PREFIX --with-mpfr=$INST_PREFIX --with-mpc=$INST_PREFIX --with-cloog=$INST_PREFIX --with-isl=$INST_PREFIX --with-ppl=$INST_PREFIX \
--disable-ppl-version-check --disable-cloog-version-check --disable-isl-version-check --enable-cloog-backend=isl \
--enable-languages=c,c++ --enable-linker-build-id --enable-threads=posix \
--enable-libstdcxx-debug --enable-libstdcxx-time=yes --enable-gnu-unique-object --enable-plugin \
--disable-sjlj-exceptions $GCC_CONFIG_FLAGS"

# prepare crosscompiler pack

PKG_DIR=/tmp/rootfs$$

umask 022

mkdir -p ${PKG_DIR}/${INST_PREFIX}

cp -R ${INST_PREFIX}/* ${PKG_DIR}/${INST_PREFIX}/

#rm -rf ${PKG_DIR}/${INST_PREFIX}/include ${PKG_DIR}/${INST_PREFIX}/lib/cloog-isl ${PKG_DIR}/${INST_PREFIX}/lib/isl \
#    ${PKG_DIR}/${INST_PREFIX}/lib/pkgconfig ${PKG_DIR}/${INST_PREFIX}/lib/lib*.a ${PKG_DIR}/${INST_PREFIX}/lib/lib*.la \
#    ${PKG_DIR}/${INST_PREFIX}/bin/cloog ${PKG_DIR}/${INST_PREFIX}/bin/ppl* \
#    ${PKG_DIR}/${INST_PREFIX}/share/aclocal ${PKG_DIR}/${INST_PREFIX}/share/doc ${PKG_DIR}/${INST_PREFIX}/share/info

#find ${PKG_DIR}/${INST_PREFIX}/share/man -name "ppl*" -o -name "libppl*" -o -name "zlib*" | xargs rm -f

strip ${PKG_DIR}/${INST_PREFIX}/bin/* ${PKG_DIR}/${INST_PREFIX}/${TARGET_ARCH}/bin/* \
    ${PKG_DIR}/${INST_PREFIX}/libexec/gcc/${TARGET_ARCH}/${TARGET_GCC_VERSION}/* \
    ${PKG_DIR}/${INST_PREFIX}/libexec/gcc/${TARGET_ARCH}/${TARGET_GCC_VERSION}/install-tools/* \
    ${PKG_DIR}/${INST_PREFIX}/libexec/gcc/${TARGET_ARCH}/${TARGET_GCC_VERSION}/plugin/*

test -e ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-cc || ln -sf ${TARGET_ARCH}-gcc ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-cc
test -e ${PKG_DIR}/${INST_PREFIX}/bin/cc || ln -sf ${TARGET_ARCH}-gcc ${PKG_DIR}/${INST_PREFIX}/bin/cc

cat > ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-sysroot-path << EOF
#!/bin/sh
if test "\$1" = "--install"; then
    ARCH=\$(uname -i)
    if test "\$ARCH" = "unknown"; then
	ARCH=\$(uname -m)
    fi
    if test "\$ARCH" != $(uname -m); then
	mkdir -p $(dirname $TARGET_SYSROOT)
	ln -sf / $TARGET_SYSROOT

	mv ${INST_PREFIX}/${TARGET_ARCH}/bin/ld ${INST_PREFIX}/${TARGET_ARCH}/bin/ld.bin
	cat > ${INST_PREFIX}/${TARGET_ARCH}/bin/ld << EOX
#!/bin/bash

OPT=
for p in \\\$(echo \\\$LD_LIBRARY_PATH | tr ':' ' '); do
    OPT="\\\$OPT -rpath-link=\\\$p"
done
exec \\\$0.bin \\\$OPT \\\$@
EOX

	chmod 755 ${INST_PREFIX}/${TARGET_ARCH}/bin/ld

    else
	echo "Please, install sysroot to $TARGET_SYSROOT"
    fi
else
    echo $TARGET_SYSROOT
fi
EOF

chmod 755 ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-sysroot-path

if test "$TAR" = "tar"; then
    ${TAR} Jcf ${TOPDIR}/${TARGET_ARCH}-gcc_${TARGET_GCC_VERSION}_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.xz -C ${PKG_DIR} .
else
    ${TAR} zcf ${TOPDIR}/${TARGET_ARCH}-gcc_${TARGET_GCC_VERSION}_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.gz -C ${PKG_DIR} .
fi

rm -rf ${PKG_DIR}
