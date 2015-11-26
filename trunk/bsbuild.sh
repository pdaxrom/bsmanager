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

check_and_install_packages build-essential pkg-config m4
#libxml-parser-perl cmake

fix_target_libm

case $TARGET_ARCH in
x86_64*|aarch64*)
    mkdir -p ${INST_PREFIX}/lib64
    ln -sf lib64 ${INST_PREFIX}/lib
    ;;
esac

mkdir -p tmp/build
cd tmp

download http://zlib.net/zlib-1.2.8.tar.gz
download http://ftp.suse.com/pub/people/sbrabec/bzip2/tarballs/bzip2-1.0.6.0.1.tar.gz
download http://tukaani.org/xz/xz-5.2.1.tar.gz
download http://ftp.gnu.org/gnu/tar/tar-1.28.tar.gz
build host nodir zlib-1.2.8.tar.gz "--static"
build bzip2-1.0.6.0.1.tar.gz "--disable-static"
build host xz-5.2.1.tar.gz
build host tar-1.28.tar.gz "FORCE_UNSAFE_CONFIGURE=1"
TAR=${INST_HOST_PREFIX}/bin/tar

download http://ftp.gnu.org/pub/gnu/ncurses/ncurses-5.9.tar.gz
download http://downloads.sourceforge.net/project/beecrypt/beecrypt/4.2.1/beecrypt-4.2.1.tar.gz
download http://rpm5.org/files/popt/popt-1.16.tar.gz
download http://rpm.org/releases/rpm-4.4.x/rpm-4.4.2.3.tar.gz

build host ncurses-5.9.tar.gz "--disable-shared --enable-static --disable-nls"
build host beecrypt-4.2.1.tar.gz "--enable-shared=no --enable-static=yes --with-python=no --with-java=no --disable-openmp --with-pic --disable-nls"
build host popt-1.16.tar.gz "--disable-shared --enable-static --with-pic --disable-nls"
build nodir rpm-4.4.2.3.tar.gz "--without-python --without-apidocs --without-selinux --without-lua --disable-nls"

rm -f ${INST_PREFIX}/var/tmp
ln -sf /var/tmp ${INST_PREFIX}/var

for f in libpopt librpm librpmbuild librpmdb librpmio; do
    rm -f ${INST_PREFIX}/lib/${f}.la
    rm -f ${INST_PREFIX}/lib/${f}.a
done
rm -rf ${INST_PREFIX}/include/rpm
rm -rf ${INST_PREFIX}/include/popt.h

download http://ftp.gnu.org/gnu/make/make-${MAKE_VERSION-4.1}.tar.bz2
download http://pkgconfig.freedesktop.org/releases/pkg-config-0.28.tar.gz
download http://ftp.gnu.org/gnu/m4/m4-1.4.17.tar.xz
download https://www.python.org/ftp/python/2.7.9/Python-2.7.9.tar.xz

build make-${MAKE_VERSION-4.1}.tar.bz2 "--disable-nls"
build pkg-config-0.28.tar.gz "--with-internal-glib --disable-nls"
build m4-1.4.17.tar.xz "--disable-nls"
build Python-2.7.9.tar.xz

rm -rf ${INST_PREFIX}/lib/libbz2.la ${INST_PREFIX}/lib/libpython2.7.a ${INST_PREFIX}/lib/pkgconfig ${INST_PREFIX}/include/*

for f in libbz2.so.1.0.6 librpm-4.4.so librpmbuild-4.4.so librpmdb-4.4.so librpmio-4.4.so; do
    strip ${INST_PREFIX}/lib/$f
done

find ${INST_PREFIX}/lib/python2.7 -name "*.so" -exec strip {} \;

strip ${INST_PREFIX}/lib/rpm/* &>/dev/null

download https://gmplib.org/download/gmp/gmp-${GMP_VERSION-6.0.0a}.tar.xz
download http://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION-3.1.3}.tar.xz
download ftp://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION-1.0.2}.tar.gz
download http://isl.gforge.inria.fr/isl-${ISL_VERSION-0.15}.tar.xz
download http://bugseng.com/products/ppl/download/ftp/releases/1.1/ppl-${PPL_VERSION-1.1}.tar.xz
download http://www.bastoul.net/cloog/pages/download/cloog-${CLOOG_VERSION-0.18.3}.tar.gz
#download http://www.bastoul.net/cloog/pages/download/cloog-parma-0.16.1.tar.gz
download http://ftp.gnu.org/gnu/binutils/binutils-${TARGET_BINUTILS_VERSION}.tar.bz2
download http://gcc.cybermirror.org/releases/gcc-${TARGET_GCC_VERSION}/gcc-${TARGET_GCC_VERSION}.tar.bz2

build host gmp-${GMP_VERSION-6.0.0a}.tar.xz "--enable-cxx --disable-shared" "" ${GMP_SOURCE_DIR-gmp-6.0.0}
build host mpfr-${MPFR_VERSION-3.1.3}.tar.xz "--disable-shared"
build host mpc-${MPC_VERSION-1.0.2}.tar.gz "--disable-shared"
build host isl-${ISL_VERSION-0.15}.tar.xz "--disable-shared"
build host ppl-${PPL_VERSION-1.1}.tar.xz "--disable-shared --with-gmp=$INST_HOST_PREFIX"
build host cloog-${CLOOG_VERSION-0.18.3}.tar.gz "--disable-shared"
#build host cloog-parma-0.16.1.tar.gz "--disable-shared"
build binutils-${TARGET_BINUTILS_VERSION}.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror"

# remove binutils headers and libs
for f in ansidecl.h bfd.h bfdlink.h dis-asm.h plugin-api.h symcat.h; do
    rm -f ${INST_PREFIX}/include/$f
done
for f in libbfd.a libbfd.la libopcodes.a libopcodes.la; do
    rm -f ${INST_PREFIX}/lib/$f
done
#

build gcc-${TARGET_GCC_VERSION}.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror --enable-shared --disable-bootstrap --with-system-zlib \
--with-gmp=$INST_HOST_PREFIX --with-mpfr=$INST_HOST_PREFIX --with-mpc=$INST_HOST_PREFIX --with-cloog=$INST_HOST_PREFIX --with-isl=$INST_HOST_PREFIX --with-ppl=$INST_HOST_PREFIX \
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

	if test -e $TARGET_SYSROOT; then
	    echo "Sysroot installed to $TARGET_SYSROOT"
	else
	    mkdir -p $(dirname $TARGET_SYSROOT)
	    ln -sf / $TARGET_SYSROOT
	fi

	if test ! -f ${INST_PREFIX}/${TARGET_ARCH}/bin/ld.bin; then
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
	fi
    else
	if test ! -e $TARGET_SYSROOT; then
	    echo "Please, install sysroot to $TARGET_SYSROOT"
	fi
    fi

    cat > ${INST_PREFIX}/bin/${TARGET_ARCH}-setenv << EOX
#!/bin/bash

export LD_LIBRARY_PATH=\\\$(dirname \\\$(readlink -f \\\$(${INST_PREFIX}/bin/gcc -print-file-name=libstdc++.so))):\\\$LD_LIBRARY_PATH
export PATH=${INST_PREFIX}/bin:\\\$PATH

EOX
    chmod 755 ${INST_PREFIX}/bin/${TARGET_ARCH}-setenv
else
    echo $TARGET_SYSROOT
fi
EOF

chmod 755 ${PKG_DIR}/${INST_PREFIX}/bin/${TARGET_ARCH}-sysroot-path

if test "$TAR" = "tar"; then
    ${TAR} Jcf ${TOPDIR}/$(echo $TARGET_ARCH | sed 's/_/-/')-gcc_${TARGET_GCC_VERSION}_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.xz -C ${PKG_DIR} .
else
    ${TAR} zcf ${TOPDIR}/$(echo $TARGET_ARCH | sed 's/_/-/')-gcc_${TARGET_GCC_VERSION}_$(uname -m | sed 's/_/-/')${PACKAGE_ID}.tar.gz -C ${PKG_DIR} .
fi

rm -rf ${PKG_DIR}
