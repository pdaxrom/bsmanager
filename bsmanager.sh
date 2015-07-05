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
    echo
    echo "Usage:"
    echo
    echo "$1 create <user> <URL | path to rootfs archive> [<architecture>]"
    echo "$1 remove <user>"
    echo
    echo "Webshell:"
    echo "$1 enable webshell [port 1..65534]"
    echo "$1 disable webshell"
    echo
    exit 0
}

if test "$1" = "help"; then
    usage $0
fi

check_and_install_packages() {
    local packages=""
    local p

    for p in $@; do
	if ! $(dpkg -l | grep -q $p); then
	    packages="$packages $p"
	#else
	#    echo "$p installed!"
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

detect_rootfs_architecture() {
    local arch=""
    local filearch=$(file $1 | cut -f2 -d',' | sed 's/^ //')
    if test "$filearch" = "ARM"; then
	arch=armv7
    elif test "$filearch" = "ARM aarch64"; then
	arch="aarch64"
    elif test "$filearch" = "Intel 80386"; then
	arch="i386"
    elif test "$filearch" = "x86-64"; then
	arch="x86_64"
    elif test "$filearch" = "PowerPC or cisco 4500"; then
	arch="powerpc"
    elif test "$filearch" = "MIPS"; then
	arch="mipsel"
    fi

    echo $arch
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

    ARCH=$4
    ROOTFSFILE="$3"
    USERNAME="$2"
    GROUPNAME="${2}users"
    ROOTFSDIR="/rootfs/${USERNAME}"

    if test ! "$ARCH" = ""; then
	if test $(check_valid_architecture "$ARCH") = "0"; then
	    echo "Invalid architecture $ARCH!"
	    echo "Supported architectures: $SUPPORTED_ARCHITECTURES"
	    exit 1
	fi
    fi

    if test "$USERNAME" = ""; then
	error "Username can not be empty!"
    fi

    if id "$USERNAME" &>/dev/null; then
	error "User account already exists!"
    fi

    check_and_install_packages qemu-user-static

    echo
    echo "Creating new virtual chroot"
    echo
    if test ! "$ARCH" = ""; then
	echo "Architecture    : $ARCH"
    else
	echo "Architecture    : Autodetect"
    fi
    echo "Rootfs          : $ROOTFSFILE"
    echo "Chroot directory: $ROOTFSDIR"
    echo "User            : $USERNAME"
    echo
    echo

    echo "Installing rootfs"

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

    if test "$ARCH" = ""; then
	ARCH=$(detect_rootfs_architecture ${ROOTFSDIR}/bin/bash)
	if test "$ARCH" = ""; then
	    error "Cannot detect architecture for rootfs!"
	else
	    echo "Detected architecture $ARCH"
	fi
    fi

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

elif test "$1" = "enable"; then

    if test "$2" = "webshell"; then
	if test "$3" = "port"; then
	    PORT="$4"
	    REGXPR='^[0-9]+$'
	    if [[ $PORT =~ $REGXPR ]]; then
		if test "$PORT" -lt 1 || test "$PORT" -ge 65535; then
		    error "Webshell port must be in 1..65534!"
		fi
	    else
		error "Webshell port is not a number!"
	    fi
	fi
	check_and_install_packages shellinabox

	. /etc/default/shellinabox

	if test "$PORT" = ""; then
	    PORT=$SHELLINABOX_PORT
	fi

	if test ! "$SHELLINABOX_PORT" = "$PORT"; then
	    sed -i -e "s|SHELLINABOX_PORT=.*|SHELLINABOX_PORT=$PORT|" /etc/default/shellinabox
	fi

	if echo "$SHELLINABOX_ARGS" | grep -q -v '\--service /:SSH'; then
	    sed -i -e "s|SHELLINABOX_ARGS=.*|SHELLINABOX_ARGS=\"$SHELLINABOX_ARGS --service /:SSH\"|" /etc/default/shellinabox
	fi

	service shellinabox restart
    fi

elif test "$1" = "disable"; then

    if test "$2" = "webshell"; then
	apt-get -y purge shellinabox
    fi

else

    usage $0

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

