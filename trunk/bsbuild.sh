#!/bin/bash

TOPDIR=$PWD

if test "$MAKE_ARGS" = ""; then
    MAKE_ARGS=-j5
fi

. setenv.sh

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

    tar xf "$file" -C build

    pushd .

    cd build/$dir

    if [ ! "$patches" = "" ]; then
	for f in $patches; do
	    patch -p1 < $f || error "patch $f for $file"
	done
    fi

    export CPPFLAGS="-I${INST_PREFIX}/include"
    export LDFLAGS="-L${INST_PREFIX}/lib"

    if test "$nodir" = ""; then
	mkdir buildme
	cd buildme

	eval ../configure --prefix=$INST_PREFIX $flags || error "Configure $file"
    else
	eval ./configure --prefix=$INST_PREFIX $flags || error "Configure $file"
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
    pushd . &>/dev/null

    cd ${TARGET_SYSROOT}/usr/lib/$TARGET_ARCH

    local LINK=$(readlink libm.so)

    if test ! -e $LINK ; then
	echo "Broken symlink for target libm.so"
	sudo ln -sf ../../..$LINK libm.so
    fi

    popd &>/dev/null
}

check_and_install_packages build-essential pkg-config yasm bison flex 
#libxml-parser-perl cmake

fix_target_libm

mkdir -p tmp/build
cd tmp

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

build nodir zlib-1.2.8.tar.xz "--static"
build gmp-6.0.0a.tar.xz "--enable-cxx --disable-shared" "" gmp-6.0.0
build mpfr-3.1.3.tar.xz "--disable-shared"
build mpc-1.0.2.tar.gz "--disable-shared"
build isl-0.15.tar.xz "--disable-shared"
build ppl-1.1.tar.xz "--disable-shared --with-gmp=$INST_PREFIX"
build cloog-0.18.3.tar.gz "--disable-shared"
#build cloog-parma-0.16.1.tar.gz "--disable-shared"
build binutils-${TARGET_BINUTILS_VERSION}.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror"
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

rm -rf ${PKG_DIR}/${INST_PREFIX}/include ${PKG_DIR}/${INST_PREFIX}/lib/cloog-isl ${PKG_DIR}/${INST_PREFIX}/lib/isl \
    ${PKG_DIR}/${INST_PREFIX}/lib/pkgconfig ${PKG_DIR}/${INST_PREFIX}/lib/lib*.a ${PKG_DIR}/${INST_PREFIX}/lib/lib*.la \
    ${PKG_DIR}/${INST_PREFIX}/bin/cloog ${PKG_DIR}/${INST_PREFIX}/bin/ppl* \
    ${PKG_DIR}/${INST_PREFIX}/share/aclocal ${PKG_DIR}/${INST_PREFIX}/share/doc ${PKG_DIR}/${INST_PREFIX}/share/info

find ${PKG_DIR}/${INST_PREFIX}/share/man -name "ppl*" -o -name "libppl*" -o -name "zlib*" | xargs rm -f

strip ${PKG_DIR}/${INST_PREFIX}/bin/* ${PKG_DIR}/${INST_PREFIX}/${TARGET_ARCH}/bin/* \
    ${PKG_DIR}/${INST_PREFIX}/libexec/gcc/${TARGET_ARCH}/${TARGET_GCC_VERSION}/* \
    ${PKG_DIR}/${INST_PREFIX}/libexec/gcc/${TARGET_ARCH}/${TARGET_GCC_VERSION}/install-tools/* \
    ${PKG_DIR}/${INST_PREFIX}/libexec/gcc/${TARGET_ARCH}/${TARGET_GCC_VERSION}/plugin/*

cat > ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-sysroot-path << EOF
#!/bin/sh
if test "\$1" = "--install"; then
    ARCH=\$(uname -i)
    if test "\$ARCH" = ""; then
	ARCH=\$(uname -m)
    fi
    if test "\$ARCH" != $(uname -m); then
	mkdir -p $(dirname $TARGET_SYSROOT)
	ln -sf / $TARGET_SYSROOT
    else
	echo "Please, install sysroot to $TARGET_SYSROOT"
    fi
else
    echo $TARGET_SYSROOT
fi
EOF

chmod 755 ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-sysroot-path

tar Jcf ${TOPDIR}/${TARGET_ARCH}-gcc_${TARGET_GCC_VERSION}_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.xz -C ${PKG_DIR} .

rm -rf ${PKG_DIR}
