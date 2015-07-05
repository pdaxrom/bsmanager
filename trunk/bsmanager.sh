#!/bin/bash

SUPPORTED_ARCHITECTURES="armv5 armv6 armv7 \
aarch64 \
i386 i486 i586 i686 x86_64 amd64 \
mipsel mips64el mipsn32el \
powerpc ppc"

error() {
    echo
    echo "ERROR: $@"
    echo

    exit 1
}

usage() {
    echo "Usage:"
    echo
    echo "$1 create <architecture> <path to rootfs archive> <user>"
    echo
    exit 0
}

if test "$1" = "help"; then
    usage $0
fi

check_packages() {
    local packages=""
    local p

    for p in shellinabox qemu-user-static distcc; do
	if ! $(dpkg -l | grep -q $p); then
	    packages="$packages $p"
	else
	    echo "$p installed!"
	fi
    done

    if test ! "$packages" = ""; then
	apt-get update
	apt-get -y install $packages
    fi
}

check_valid_architecture() {
    local name
    local ret="0"
    for name in $SUPPORTED_ARCHITECTURES; do
	if test "$1" = "$name"; then
	    ret="1"
	    break
	fi
    done
    echo "$ret"
}

unpack_rootfs() {
    local rootfsdir=$1
    local rootfsfile=$2

    tar xf "$rootfsfile" -C $ROOTFSDIR || error "Unpacking rootfs!"

    if test ! -d ${rootfsdir}/bin; then

	local unpacked_rootfsdir=$(echo $(ls $rootfsdir) | cut -f1 -d' ')

	if test -d ${rootfsdir}/${unpacked_rootfsdir}/bin; then

	    echo "Move unpacked files to rootfs directory!"

	    mv ${rootfsdir}/${unpacked_rootfsdir} ${rootfsdir}/${unpacked_rootfsdir}orig
	    mv ${rootfsdir}/${unpacked_rootfsdir}orig/* ${rootfsdir}/
	    rmdir ${rootfsdir}/${unpacked_rootfsdir}orig

	fi

    fi
}

if test "$1" = "create"; then

    ARCH=$2
    ROOTFSFILE="$3"
    USERNAME="${4}"
    GROUPNAME="${4}users"
    ROOTFSDIR="/rootfs/${USERNAME}"

    if test $(check_valid_architecture "$ARCH") = "0"; then
	echo "Invalid architecture $ARCH!"
	echo "Supported architectures: $SUPPORTED_ARCHITECTURES"
	exit 1
    fi

    if test "$USERNAME" = ""; then
	echo "Username can not be empty!"
	exit 1
    fi

    check_packages

    echo
    echo "Creating new virtual chroot"
    echo
    echo "Architecture    : $ARCH"
    echo "Rootfs          : $ROOTFSFILE"
    echo "Chroot directory: $ROOTFSDIR"
    echo "User            : $USERNAME"
    echo
    echo

    echo "Preparing rootfs"

    mkdir -p "$ROOTFSDIR"

    case "$ROOTFSFILE" in
    http://*|https://*|ftp://*)
	ROOTFSTMP="/tmp/rootfs$$.dat"
	wget "$ROOTFSFILE" -O "$ROOTFSTMP" || error "downloading rootfs!"
	unpack_rootfs $ROOTFSDIR $ROOTFSTMP
	rm -f "$ROOTFSTMP"
	;;
    *)
	unpack_rootfs $ROOTFSDIR $ROOTFSFILE
	;;
    esac

    groupadd $GROUPNAME
    useradd  -g $GROUPNAME -s /bin/bash $USERNAME

    QEMU=""
    case $ARCH in
    arm*)	QEMU=qemu-arm-static ;;
    aarch64)	QEMU=qemu-aarch64-static ;;
    i*86)	QEMU=qemu-i386-static ;;
    x86_64|amd64) QEMU=qemu-x86_64-static ;;
    powerpc|ppc) QEMU=qemu-ppc-static ;;
    mipsel)	QEMU=qemu-mipsel-static ;;
    mips64el)	QEMU=qemu-mips64el-static ;;
    mipsn32el)	QEMU=qemu-mipsn32el-static ;;
    esac

    if test ! "$QEMU" = ""; then

	echo "Installing qemu to chroot"
	cp -f /usr/bin/${QEMU} ${ROOTFSDIR}/usr/bin/${QEMU}

    fi

    chroot $ROOTFSDIR groupadd -g $(id -g $USERNAME) $GROUPNAME
    chroot $ROOTFSDIR useradd  -u $(id -u $USERNAME) -g $GROUPNAME -N -m -s /bin/bash $USERNAME

    for dir in /dev /proc; do
	FS="$dir ${ROOTFSDIR}${dir} none bind 0 0"
	echo "$FS" >> /etc/fstab
	mount ${ROOTFSDIR}${dir}
    done

    cat >> /etc/ssh/sshd_config << EOF
# begin of $GROUPNAME
Match group $GROUPNAME
	ChrootDirectory $ROOTFSDIR
	X11Forwarding no
	AllowTcpForwarding no
# end of $GROUPNAME
EOF

    service ssh restart

    passwd $USERNAME

elif test "$1" = "remove"; then

    USERNAME="${2}"
    GROUPNAME="${2}users"
    ROOTFSDIR="/rootfs/${USERNAME}"

    if ! id $USERNAME &>/dev/null ; then
	echo "User '$USERNAME' does not exists!"
	exit 1
    fi

    cp /etc/fstab /etc/fstab.vcpu-config.bak

    for dir in /dev /proc; do
	mountpoint -q ${ROOTFSDIR}${dir} && umount ${ROOTFSDIR}${dir}
	FS="$dir ${ROOTFSDIR}${dir} none bind 0 0"
	grep -v "$FS" /etc/fstab > /tmp/fstab.new.$$
	cp /tmp/fstab.new.$$ /etc/fstab
    done

    rm -f /tmp/fstab.new.$$

    if id $USERNAME &>/dev/null ; then
	userdel $USERNAME
	groupdel $GROUPNAME
    fi

    sed -n -i -e "1,/# begin of $GROUPNAME/p;/# end of $GROUPNAME/,\$p" /etc/ssh/sshd_config
    sed -i -e "/# begin of $GROUPNAME/,/# end of $GROUPNAME/d" /etc/ssh/sshd_config

    echo "Now, you can remove rootfs directory $ROOTFSDIR"

else

    usage

fi

#O=`getopt -n vcpu-session -l create,remove,help -o crh -- "$@"` || exit 1
#eval set -- "$O"
#while true; do
#    case "$1" in
#    -c|--create)
#    P_BUILD="yes"; shift;;
#    -r|--remove)
#    P_RUN="yes"; shift;;
#    -h|--help)
#    usage; shift;;
#    --)
#    shift; break;;
#    *)
#    echo Error; exit 1;;
#    esac
#done

