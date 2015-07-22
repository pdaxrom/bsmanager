#!/bin/bash

TOPDIR=$PWD

MAKE_ARGS=-j5

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

    mkdir buildme
    cd buildme

    eval ../configure --prefix=$INST_PREFIX $flags || error "Configure $file"

    make ${MAKE_ARGS} || error "make $file"

    make install || error "make install $file"

    touch install.status

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

check_and_install_packages build-essential pkg-config yasm bison flex 
#libxml-parser-perl cmake

mkdir -p tmp/build
cd tmp

download https://gmplib.org/download/gmp/gmp-6.0.0a.tar.xz
download http://www.mpfr.org/mpfr-current/mpfr-3.1.3.tar.xz
download ftp://ftp.gnu.org/gnu/mpc/mpc-1.0.2.tar.gz
download http://isl.gforge.inria.fr/isl-0.15.tar.xz
download http://bugseng.com/products/ppl/download/ftp/releases/1.1/ppl-1.1.tar.xz
download http://www.bastoul.net/cloog/pages/download/cloog-0.18.3.tar.gz
download http://ftp.gnu.org/gnu/binutils/binutils-2.25.1.tar.bz2
download http://gcc.cybermirror.org/releases/gcc-4.9.3/gcc-4.9.3.tar.bz2
download http://www.bastoul.net/cloog/pages/download/cloog-parma-0.16.1.tar.gz

build gmp-6.0.0a.tar.xz "--enable-cxx" "" gmp-6.0.0
build mpfr-3.1.3.tar.xz
build mpc-1.0.2.tar.gz
build isl-0.15.tar.xz
build ppl-1.1.tar.xz "--with-gmp=$INST_DIR"
build cloog-0.18.3.tar.gz
build cloog-parma-0.16.1.tar.gz
build binutils-2.25.1.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror"
build gcc-4.9.3.tar.bz2 "--target=$TARGET_ARCH --host=$(uname -m)-linux-gnu --build=$(uname -m)-linux-gnu \
--with-sysroot=$TARGET_SYSROOT --disable-nls --disable-werror --disable-bootstrap \
--enable-languages=c,c++ --enable-shared --enable-linker-build-id --enable-threads=posix \
--enable-libstdcxx-debug --enable-libstdcxx-time=yes --enable-gnu-unique-object --enable-plugin \
--disable-sjlj-exceptions $GCC_CONFIG_FLAGS"

#
#--with-gmp=$INST_DIR --with-mpfr=$INST_DIR --with-mpc=$INST_DIR --with-cloog=$INST_DIR --with-isl=$INST_DIR --with-ppl=$INST_DIR \
#--disable-ppl-version-check --disable-cloog-version-check --disable-isl-version-check --enable-cloog-backend=ppl \
