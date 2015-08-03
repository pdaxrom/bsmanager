#!/bin/bash

#
# Virtual machine shell access management
#
# (c) sashz, 2015
#

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
    echo "BuildServer Management Utility <http://buildserver.io>"
    echo "(c) sashz <sashz@pdaXrom.org>, 2007-2015"
    echo
    echo "Usage:"
    echo
    echo "Account:"
    echo "$1 create <user> <URL | rootfs archive | raw disk image> [<architecture>]"
    echo "$1 remove <user>"
    echo
    echo "Webshell:"
    echo "$1 enable webshell [port 1..65534]"
    echo "$1 disable webshell"
    echo
    echo "Admin shell:"
    echo "$1 shell <user>"
    echo
    echo "List all available accounts"
    echo "$1 list"
    echo
    echo "Native shell binaries:"
    echo "$1 enable native"
    echo "$1 disable native"
    echo
    echo "Toolchain:"
    echo "$1 toolchain <user> <URL | toolchain archive> [URL | sysroot archive]"
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

    if file -z $rootfsfile | grep -q partition; then
	local compressed=$(file $rootfsfile | sed 's/^.*: //')
	local tmpimage=""
	local unpack=""

	case $compressed in
	XZ*)	unpack="xz" ;;
	gzip*)	unpack="gzip" ;;
	bzip2*)	unpack="bzip2" ;;
	esac

	if test ! "$unpack" = ""; then
	    tmpimage=/tmp/disk$$.img
	    $unpack -cd $rootfsfile > $tmpimage || error "unpacking disk image!"
	    rootfsfile=$tmpimage
	fi

	TMPMOUNT="/tmp/mnt$$"
	mkdir -p $TMPMOUNT

	for p in `parted $rootfsfile unit B print | awk '/^ [0-9]/{ print substr($2, 1, length($2)-1); }'`; do
	    echo "Partition offset $p"
	    mount -o loop,ro,offset=$p "$rootfsfile" $TMPMOUNT
	    if test -d ${TMPMOUNT}/bin; then
		echo "Found system partition at $p"
		pushd . &>/dev/null
		cd $TMPMOUNT
		cp -ax . ${rootfsdir}/
		chown root:root $rootfsdir
		popd &>/dev/null
		umount $TMPMOUNT
		break
	    fi
	    sleep 2
	    umount $TMPMOUNT
	done

	rmdir $TMPMOUNT

	if test ! "$tmpimage" = ""; then
	    rm -f $tmpimage
	fi

    else
	tar xf "$rootfsfile" -C $rootfsdir || error "Unpacking rootfs!"

	if test ! -d ${rootfsdir}/bin; then

	    local unpacked_rootfsdir=$(echo $(ls $rootfsdir) | cut -f1 -d' ')

	    if test -d ${rootfsdir}/${unpacked_rootfsdir}/bin; then

		echo "Move unpacked files to rootfs directory!"

		mv ${rootfsdir}/${unpacked_rootfsdir} ${rootfsdir}/${unpacked_rootfsdir}orig
		mv ${rootfsdir}/${unpacked_rootfsdir}orig/* ${rootfsdir}/
		rmdir ${rootfsdir}/${unpacked_rootfsdir}orig

	    fi

	fi
    fi
}

get_uniq_id() {
    local n
    local id=1000

    for n in $(cat $@ | cut -f3 -d: | sort -g | uniq); do
	if test $id -lt $n; then
	    break
	elif test $id -eq $n; then
	    id=$((id + 1))
	fi
    done

    echo $id
}

if test "$1" = "create"; then

    ARCH=$4
    ROOTFSFILE="$3"
    USERNAME="$2"
    GROUPNAME="${2}users"
    ROOTFSDIR="/opt/madisa/rootfs/${USERNAME}"

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

    check_and_install_packages qemu-user-static binfmt-support xz-utils

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

    NEWGID=$(get_uniq_id /etc/group ${ROOTFSDIR}/etc/group)
    NEWUID=$(get_uniq_id /etc/passwd ${ROOTFSDIR}/etc/passwd)

    groupadd -g $NEWGID $GROUPNAME
    useradd  -u $NEWUID -g $GROUPNAME -s /bin/bash $USERNAME

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

    chroot $ROOTFSDIR groupadd -g $NEWGID $GROUPNAME
    chroot $ROOTFSDIR useradd  -u $NEWUID -g $GROUPNAME -N -m -s /bin/bash $USERNAME

    ln -sf ${ROOTFSDIR}/home/$USERNAME /home/$USERNAME

    for dir in $(cat /etc/fstab | awk '/^devpts \/opt\/madisa\/rootfs\//{ print $2; }'); do
	mountpoint -q $dir && umount $dir
    done

    for dir in /dev /proc; do
	FS="$dir ${ROOTFSDIR}${dir} none bind 0 0"
	echo "$FS" >> /etc/fstab
	mount ${ROOTFSDIR}${dir}
    done

    FS="devpts ${ROOTFSDIR}/dev/pts devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000 0 0"
    echo "$FS" >> /etc/fstab
    mount ${ROOTFSDIR}/dev/pts

    ## Post config
    case $ARCH in
    armv6*)
	echo "export QEMU_CPU=arm1176" >> ${ROOTFSDIR}/home/${USERNAME}/.bashrc
	;;
    esac

    cp -f /etc/resolv.conf ${ROOTFSDIR}/etc/
    ##

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

    USERNAME="$2"
    GROUPNAME="${2}users"
    ROOTFSDIR="/opt/madisa/rootfs/${USERNAME}"

    if ! id $USERNAME &>/dev/null ; then
	echo "User '$USERNAME' does not exists!"
	exit 1
    fi

    cp /etc/fstab    /root/fstab.bsmanager.bak

    mountpoint -q ${ROOTFSDIR}/dev/pts && umount ${ROOTFSDIR}/dev/pts
    FS="devpts ${ROOTFSDIR}/dev/pts devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000 0 0"
    grep -v "$FS" /etc/fstab > /tmp/fstab.new.$$
    cp /tmp/fstab.new.$$ /etc/fstab

    for dir in /dev /proc; do
	mountpoint -q ${ROOTFSDIR}${dir} && umount ${ROOTFSDIR}${dir}
	FS="$dir ${ROOTFSDIR}${dir} none bind 0 0"
	grep -v "$FS" /etc/fstab > /tmp/fstab.new.$$
	cp /tmp/fstab.new.$$ /etc/fstab
    done
    rm -f /tmp/fstab.new.$$

    for dir in $(cat /etc/fstab | awk '/^devpts \/opt\/madisa\/rootfs\//{ print $2; }'); do
	mountpoint -q $dir || mount $dir
    done

    if id $USERNAME &>/dev/null ; then
	userdel $USERNAME
	groupdel $GROUPNAME
	rm -f /home/$USERNAME
    fi

    sed -n -i -e "1,/# begin of $GROUPNAME/p;/# end of $GROUPNAME/,\$p" /etc/ssh/sshd_config
    sed -i -e "/# begin of $GROUPNAME/,/# end of $GROUPNAME/d" /etc/ssh/sshd_config

    echo "You can remove rootfs directory $ROOTFSDIR"

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

    elif test "$2" = "native"; then
	USERNAME="$3"
	GROUPNAME="${3}users"
	ROOTFSDIR="/opt/madisa/rootfs/${USERNAME}"

	if ! id $USERNAME &>/dev/null ; then
	    echo "User '$USERNAME' does not exists!"
	    exit 1
	fi

	mkdir -p ${ROOTFSDIR}/opt/madisa/backup
	for f in /bin/bash /bin/dash /bin/sed /bin/grep /bin/sleep; do
	    if test -x ${ROOTFSDIR}$f -a -x $f -a ! -e ${ROOTFSDIR}/opt/madisa/backup/$f ; then
		echo "Installing $f"
		mkdir -p $(dirname ${ROOTFSDIR}/opt/madisa/backup/$f)
		cp ${ROOTFSDIR}$f $(dirname ${ROOTFSDIR}/opt/madisa/backup/$f)
		rm -f ${ROOTFSDIR}$f
		cp $f $(dirname ${ROOTFSDIR}$f)
	    fi
	done
    fi

elif test "$1" = "disable"; then

    if test "$2" = "webshell"; then

	apt-get -y purge shellinabox

    elif test "$2" = "native"; then
	USERNAME="$3"
	GROUPNAME="${3}users"
	ROOTFSDIR="/opt/madisa/rootfs/${USERNAME}"

	if ! id $USERNAME &>/dev/null ; then
	    echo "User '$USERNAME' does not exists!"
	    exit 1
	fi

	for f in /bin/bash /bin/dash /bin/sed /bin/grep /bin/sleep; do
	    if test -x ${ROOTFSDIR}$f -a -x ${ROOTFSDIR}/opt/madisa/backup/$f ; then
		echo "Uninstalling $f"
		rm -f ${ROOTFSDIR}$f
		cp ${ROOTFSDIR}/opt/madisa/backup/$f $(dirname ${ROOTFSDIR}$f)
		rm -f ${ROOTFSDIR}/opt/madisa/backup/$f
	    fi
	done
    fi

elif test "$1" = "shell"; then
    USERNAME="$2"
    GROUPNAME="${2}users"
    ROOTFSDIR="/opt/madisa/rootfs/${USERNAME}"

    chroot $ROOTFSDIR

elif test "$1" = "list"; then

    ls /opt/madisa/rootfs

elif test "$1" = "toolchain"; then
    USERNAME="$2"
    GROUPNAME="${2}users"
    ROOTFSDIR="/opt/madisa/rootfs/${USERNAME}"
    TOOLSFILE="$3"
    SYSROOTFILE="$4"

    if ! id $USERNAME &>/dev/null ; then
	echo "User '$USERNAME' does not exists!"
	exit 1
    fi

    case "$TOOLSFILE" in
    http://*|https://*|ftp://*)
	ROOTFSTMP="/tmp/rootfs$$.dat"
	wget "$TOOLSFILE" -O "$TOOLSTMP" || error "downloading toolchain!"
	tar --no-same-owner -xf $TOOLSTMP -C $ROOTFSDIR
	rm -f "$TOOLSTMP"
	;;
    *)
	tar --no-same-owner -xf $TOOLSFILE -C $ROOTFSDIR
	;;
    esac

    HOST_ARCH=$(basename $TOOLSFILE | cut -f3 -d_ | sed 's/-gcc$//' | sed 's/x86-64/x86_64/')
    TARGET_ARCH=$(basename $TOOLSFILE | cut -f1 -d_ | sed 's/-gcc$//' | sed 's/x86-64/x86_64/')

    if test ! "$SYSROOTFILE" = ""; then
	case "$SYSROOTFILE" in
	http://*|https://*|ftp://*)
	    ROOTFSTMP="/tmp/rootfs$$.dat"
	    wget "$SYSROOTFILE" -O "$TOOLSTMP" || error "downloading sysroot!"
	    tar --no-same-owner -xf $TOOLSTMP -C $ROOTFSDIR
	    rm -f "$TOOLSTMP"
	    ;;
	*)
	    tar --no-same-owner -xf $SYSROOTFILE -C $ROOTFSDIR
	    ;;
    esac
    fi

    SYSROOT_SETUP=${TARGET_ARCH}-sysroot-path

    if test -x "${ROOTFSDIR}/opt/madisa/toolchain/bin/${SYSROOT_SETUP}"; then

	chroot ${ROOTFSDIR} /opt/madisa/toolchain/bin/${SYSROOT_SETUP} --install

    fi

    ln -s /opt/madisa/toolchain/bin/${TARGET_ARCH}-setenv ${ROOTFSDIR}/home/${USERNAME}/

    cd ${ROOTFSDIR}/opt/madisa/toolchain/bin

    for f in ${TARGET_ARCH}-*; do

	ln -sf $f ${f/$TARGET_ARCH-}

    done

    ln -sf ${TARGET_ARCH}-gcc cc

    case $HOST_ARCH in
    x86-64)
	mkdir -p ${ROOTFSDIR}/lib64/ ${ROOTFSDIR}/lib/x86_64-linux-gnu/
	cp -a /lib64/* ${ROOTFSDIR}/lib64/
	cp -a /lib/x86_64-linux-gnu/* ${ROOTFSDIR}/lib/x86_64-linux-gnu/
	;;
    *)
	;;
    esac

else

    usage $0

fi
