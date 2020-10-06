#!/bin/sh
#
# TODO:
# - net: nameserver?
# - nproc/memsize
# - UML http://user-mode-linux.sourceforge.net/network.html
# - api kernel+busybox+toybox+gcc... download/version
# - different recipes: minimal, net, compiler, net-compiler
# - which programs where called? hash?
# - include tinyCC or HEX
# - upload/api: good + bad things
# - upload bootable images
# - safe versions of all deps (cc, ld, libc)
# - filesizes
# - needed space


KERNEL="$1"
[ -n "$2" ] && {
	shift
	OPTIONS="$*"		# e.g. 64bit,32bit,no_pie,no_printk and 'toybox' and 'UML' and 'menuconfig'
}

CPU="$( nproc || echo 1 )"
BASEDIR='minilinux'

export STORAGE="/tmp/storage"
mkdir -p "$STORAGE"
echo "[OK] cache/storage is here: '$STORAGE'"

kernels()
{
	case "$1" in
		 0) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.16.83.tar.xz' ;;		# TODO: 32bit
		 1) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.4.222.tar.xz' ;;
		 2) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/linux-2.6.39.tar.xz' ;;	# TODO: 32bit?
		 3) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.9.222.tar.xz' ;;
		 4) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.121.tar.xz' ;;
		 5) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.39.tar.xz' ;;
		 6) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.5.19.tar.xz' ;;
		 7) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.6.11.tar.xz' ;;
		 8) echo 'https://git.kernel.org/torvalds/t/linux-5.7-rc4.tar.gz' ;;
		 9) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/linux-2.6.39.4.tar.xz' ;;
		10) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-5.0.1.tar.gz' ;;
		11) echo 'https://git.kernel.org/pub/scm/linux/kernel/git/wtarreau/linux-2.4.git/snapshot/linux-2.4-2.4.37.11.tar.gz' ;;
		12) echo 'https://git.kernel.org/torvalds/t/linux-5.7-rc6.tar.gz' ;;
		13) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.7.tar.xz' ;;
		14) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.8.12.tar.xz' ;;
		15) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc1.tar.gz' ;;
		16) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc2.tar.gz' ;;
		17) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc3.tar.gz' ;;
		18) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc4.tar.gz' ;;
		19) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc5.tar.gz' ;;
		20) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc6.tar.gz' ;;
		21) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc7.tar.gz' ;;
		22) echo 'https://git.kernel.org/torvalds/t/linux-5.9-rc8.tar.gz' ;;
		 *) false ;;
	esac
}

download()
{
	local url="$1"
	local cache="$STORAGE/$( basename "$url" )"

	if [ -f "$cache" ]; then
		echo "[OK] download, using cache: '$cache' url: '$url'"
		cp "$cache" .
	else
		wget -O "$cache" "$url"
		cp "$cache" .
	fi
}

untar()
{
	case "$1" in
		*.xz)  tar xJf "$1" ;;
		*.bz2) tar xjf "$1" ;;
		*.gz)  tar xzf "$1" ;;
	esac
}

msg_and_die()
{
	local rc="$1"
	local txt="$2"

	echo >&2 "[ERROR] rc:$rc | pwd: $PWD | $txt"
	exit $rc
}

case "$KERNEL" in
	'clean')
		rm -fR "$BASEDIR"
		exit
	;;
	'fill_cache')
		mkdir -p fake
		cd fake || exit

		I=0
		while KERNEL_URL="$( kernels $I )"; do {
			download "$KERNEL_URL"
			I=$(( I + 1 ))
		} done

		cd ..
		rm -fR 'fake'

		exit
	;;
	[0-9]|[0-9][0-9])
		KERNEL_URL="$( kernels $KERNEL )"
		echo "[OK] choosing '$KERNEL_URL'"
	;;
	'')
		echo "Usage: <number or clean or fill_cache> <option>"
		echo
		echo "choose 0,1,2,3..."
		echo

		I=0
		while KERNEL_URL="$( kernels $I )"; do {
			MINOR="$( echo "$KERNEL_URL" | sed -n 's/.*linux-\([0-9].*\)/\1/p' )"	# 5.4.39.tar.xz

			while case "$MINOR" in
				*[0-9]) false ;;
				*) true ;;
			      esac; do {
				MINOR="${MINOR%.*}"
			} done
			echo "$I | $MINOR"

			I=$((I+1))
		} done

		exit 1
	;;
	
esac

has_arg()
{
	case " $OPTIONS " in *" $1 "*) true ;; *) false ;; esac
}

rm -fR "$BASEDIR"
mkdir -p "$BASEDIR" && cd "$BASEDIR"

export OPT="$PWD/opt"
mkdir -p "$OPT"

export BUILDS="$PWD/builds"
mkdir -p "$BUILDS"

export LINUX="$OPT/linux"
mkdir -p "$LINUX"

export LINUX_BUILD="$BUILDS/linux"
mkdir -p "$LINUX_BUILD"

ARCH=
has_arg 'UML' && ARCH='ARCH=um'

# https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e
# CONFIG_64BIT=y			| 64-bit kernel
# CONFIG_BLK_DEV_INITRD=y		| General setup ---> Initial RAM filesystem and RAM disk (initramfs/initrd) support
# CONFIG_PRINTK=y			| General setup ---> Configure standard kernel features ---> Enable support for printk 
# CONFIG_BINFMT_ELF=y			| Executable file formats / Emulations ---> Kernel support for ELF binaries
# CONFIG_BINFMT_SCRIPT=y		| Executable file formats / Emulations ---> Kernel support for scripts starting with #!
# CONFIG_DEVTMPFS=y			| Device Drivers ---> Generic Driver Options ---> Maintain a devtmpfs filesystem to mount at /dev
# CONFIG_DEVTMPFS_MOUNT=y		| Device Drivers ---> Generic Driver Options ---> Automount devtmpfs at /dev, after the kernel mounted the rootfs
# CONFIG_TTY=y				| Device Drivers ---> Character devices ---> Enable TTY
# CONFIG_SERIAL_8250=y			| Device Drivers ---> Character devices ---> Serial drivers ---> 8250/16550 and compatible serial support
# CONFIG_SERIAL_8250_CONSOLE=y		| Device Drivers ---> Character devices ---> Serial drivers ---> Console on 8250/16550 and compatible serial port
# CONFIG_PROC_FS=y			| File systems ---> Pseudo filesystems ---> /proc file system support
# CONFIG_SYSFS=y			| File systems ---> Pseudo filesystems ---> sysfs file system support

list_kernel_symbols()
{
	if has_arg '32bit'; then
		echo '# CONFIG_64BIT is not set'
	else
		echo 'CONFIG_64BIT=y'
	fi

	if has_arg 'no_printk'; then
		:
	else
		echo 'CONFIG_PRINTK=y'
	fi

	has_arg 'net' && {
		echo 'CONFIG_PCI=y'
		echo 'CONFIG_NET=y'
		echo 'CONFIG_NETDEVICES=y'

		echo 'CONFIG_PACKET=y'
		echo 'CONFIG_UNIX=y'
		echo 'CONFIG_INET=y'

#		echo 'CONFIG_E1000=y'		# lspci -nk will show attached driver
		echo 'CONFIG_8139CP=y'		# needs: -net nic,model=rtl8139 (but kernel is ~32k smaller)

		echo 'CONFIG_IP_PNP=y'
		echo 'CONFIG_IP_PNP_DHCP=y'
	}

	cat <<!
CONFIG_BLK_DEV_INITRD=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TTY=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
!
}

apply()
{
	local symbol="$1"
	local word="${symbol%=*}"

	sed -i "/^$word=.*/d" '.config'
	sed -i "/.*$word .*/d" '.config'
	echo "$symbol" >>'.config'

	echo "[OK] applying symbol '$symbol'"

	# see: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/scripts/config
	yes "" | make $ARCH oldconfig || return 1

	grep -q ^"$symbol"$ .config || {
		echo "#"
		echo "[ERROR] added symbol '$symbol' not found in file '.config' pwd '$PWD'"
		echo "#"

		false
	}
}

###
### busybox + rootfs/initrd ####
###

export BUSYBOX="$OPT/busybox"
mkdir -p "$BUSYBOX"

export BUSYBOX_BUILD="$BUILDS/busybox"
mkdir -p "$BUSYBOX_BUILD"

cd $BUSYBOX || msg_and_die "$?" "cd $BUSYBOX"

if has_arg 'toybox'; then
	download "http://landley.net/toybox/downloads/toybox-0.8.3.tar.gz" || exit
	mv *toybox* $BUSYBOX_BUILD/
else
#	download "https://busybox.net/downloads/busybox-1.31.1.tar.bz2" || exit
	download "https://busybox.net/downloads/busybox-1.32.0.tar.bz2" || exit
fi

has_arg 'toybox' && cd $BUSYBOX_BUILD

untar *
cd * || exit		# there is only 1 dir

if has_arg 'toybox'; then
	BUSYBOX_BUILD=$PWD
	LDFLAGS="--static" make root || msg_and_die "$?" "LDFLAGS=--static make root"
else
	make O=$BUSYBOX_BUILD defconfig || msg_and_die "$?" "make O=$BUSYBOX_BUILD defconfig"
fi

cd $BUSYBOX_BUILD || msg_and_die "$?" "$_"

if has_arg 'toybox'; then
	:
else
	for SYMBOL in 'CONFIG_STATIC=y'; do apply "$SYMBOL" || exit; done
fi

has_arg 'menuconfig' && {
	while :; do {
		make menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && read GO && test "$GO" && break
	} done

#	comparing manually configured vs. apply()
#	cmp .config /home/bastian/software/minilinux/.config_busybox || vimdiff .config /home/bastian/software/minilinux/.config_busybox
}

CONFIG2="$PWD/.config"

if has_arg 'toybox'; then
	LDFLAGS="--static" make -j$CPU toybox || msg_and_die "$?" "LDFLAGS=--static make -j$CPU"
	test -f toybox || msg_and_die "$?" "test -f toybox"

	mkdir '_install'
	PREFIX="$BUSYBOX_BUILD/_install" make install || msg_and_die "$?" "PREFIX='$BUSYBOX_BUILD/_install' make install"
else
	make -j$CPU || msg_and_die "$?" "make -j$CPU"
	make install || msg_and_die "$?" "make install"
fi

cd ..

export INITRAMFS_BUILD=$BUILDS/initramfs
mkdir -p $INITRAMFS_BUILD
cd $INITRAMFS_BUILD || exit

mkdir -p bin sbin etc proc sys usr/bin usr/sbin dev
cp -a $BUSYBOX_BUILD/_install/* .

# TODO: https://stackoverflow.com/questions/36529881/qemu-bin-sh-cant-access-tty-job-control-turned-off?rq=1

cat >'init' <<EOF
#!/bin/sh
mount -t proc  none /proc && {
	read -r UP _ </proc/uptime || UP=\$( cut -d' ' -f1 /proc/uptime )
	while read -r LINE; do case "\$LINE" in MemAvailable:*) set -- \$LINE; MEMAVAIL_KB=\$2; break ;; esac; done </proc/meminfo
}
mount -t sysfs none /sys

printf '%s\n' "# BOOTTIME_SECONDS \$UP"
printf '%s\n' "# MEMFREE_KILOBYTES \$MEMAVAIL_KB"
printf '%s\n' "# UNAME \$( uname -a )"
printf '%s\n' "# READY - to quit $( if has_arg 'UML'; then echo "type 'exit'"; else echo "press once STRG+A and then 'x'"; fi )"

exec /bin/sh
EOF

chmod +x 'init'
sh -n 'init' || { RC=$?; echo "$PWD/init"; exit $RC; }
find . -print0 | cpio --create --null --format=newc | xz -9  --format=lzma >$BUILDS/initramfs.cpio.xz
find . -print0 | cpio --create --null --format=newc | xz -9e --format=lzma >$BUILDS/initramfs.cpio.xz.xz
find . -print0 | cpio --create --null --format=newc | gzip -9              >$BUILDS/initramfs.cpio.gz

INITRD_FILE="$(  readlink -e "$BUILDS/initramfs.cpio.gz"    )"
INITRD_FILE2="$( readlink -e "$BUILDS/initramfs.cpio.xz"    )"
INITRD_FILE3="$( readlink -e "$BUILDS/initramfs.cpio.xz.xz" )"
BB_FILE="$BUSYBOX_BUILD/busybox"
has_arg 'toybox' && BB_FILE="$BUSYBOX_BUILD/toybox"

###
### linux kernel ###
###

cd "$LINUX" || exit
download "$KERNEL_URL" || exit
untar *
cd * || exit		# there is only 1 dir

make $ARCH O=$LINUX_BUILD allnoconfig || exit
cd $LINUX_BUILD

if has_arg 'UML'; then
	make mrproper
	make mrproper $ARCH
	make defconfig $ARCH

	if has_arg '32bit'; then
		echo '# CONFIG_64BIT is not set'
	else
		echo 'CONFIG_64BIT=y'
	fi

	apply "CONFIG_BLK_DEV_INITRD=y"

	apply "CONFIG_RD_GZIP=y"
	apply "CONFIG_ZLIB_INFLATE=y"
	apply "CONFIG_LZO_DECOMPRESS=y"
	apply "CONFIG_LZ4_DECOMPRESS=y"
	apply "CONFIG_XZ_DEC=y"
	apply "CONFIG_DECOMPRESS_GZIP=y"
	apply "CONFIG_DECOMPRESS_BZIP2=y"
	apply "CONFIG_DECOMPRESS_LZMA=y"
	apply "CONFIG_DECOMPRESS_XZ=y"
	apply "CONFIG_DECOMPRESS_LZO=y"
	apply "CONFIG_DECOMPRESS_LZ4=y"

#	apply "CONFIG_INITRAMFS_SOURCE=\"$INITRD_FILE\""
#	grep CONFIG_INITRAMFS_SOURCE= .config || {
#		echo "### sdfisfsdfzuszdf"
#		sleep 10
#	}
else
	for SYMBOL in $( list_kernel_symbols ); do apply "$SYMBOL" || exit; done
fi

has_arg 'menuconfig' && {
	while :; do {
		make $ARCH menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && read GO && test "$GO" && break
	} done

#	comparing manually configured vs. apply()
#	cmp .config /home/bastian/software/minilinux/.config_kernel || vimdiff .config /home/bastian/software/minilinux/.config_kernel
}

CONFIG1="$PWD/.config"

logger -s "bitte jetzt in '$(pwd)' Aenderungen machen unter enter druecken"
#read NOP


if has_arg 'no_pie'; then
	echo "make $ARCH CFLAGS=-fno-pie LDFLAGS=-no-pie -j$CPU" && sleep 5
	make       $ARCH CFLAGS=-fno-pie LDFLAGS=-no-pie -j$CPU || exit
else
	echo "make $ARCH -j$CPU" && sleep 5
	make       $ARCH -j$CPU || exit
fi

cd .. || exit

if has_arg 'UML'; then
	KERNEL_FILE="$LINUX_BUILD/vmlinux"
else
	KERNEL_FILE="$( readlink -e "$LINUX_BUILD/arch/x86_64/boot/bzImage" )"
fi

# TODO: include build-instructions
cat >"$LINUX_BUILD/run.sh" <<!
#!/bin/sh

ACTION="\$1"		# autotest|boot

# generated: $( LC_ALL=C date )
#
# KERNEL_URL: $KERNEL_URL
# KERNEL: $KERNEL_FILE
# KERNEL_SIZE: $( wc -c <$KERNEL_FILE ) bytes
# KERNEL_CONFIG: $CONFIG1
#
# BUSYBOX: $BB_FILE
# BUSYBOX_SIZE: $( wc -c <$BB_FILE ) bytes
# BUSYBOX_CONFIG: $CONFIG2
#
# INITRD:  $INITRD_FILE
# INITRD2: $INITRD_FILE2
# INITRD3: $INITRD_FILE3
# INITRD_SIZE: $(  wc -c <$INITRD_FILE ) bytes
# INITRD_SIZE2: $( wc -c <$INITRD_FILE2 ) bytes
# INITRD_SIZE3: $( wc -c <$INITRD_FILE3 ) bytes
#   decompress: gzip -cd $INITRD_FILE | cpio -idm

KERNEL_ARGS='console=ttyS0'
$( has_arg 'net' && echo "KERNEL_ARGS='console=ttyS0 ip=dhcp nameserver=8.8.8.8'" )
QEMU_OPTIONS=
$( has_arg 'net' && echo "QEMU_OPTIONS='-net nic,model=rtl8139 -net user'" )

case "\$ACTION" in
	boot|'')
		case "$KERNEL_FILE" in
			*'/vmlinux')
				$KERNEL_FILE \\
					initrd=$INITRD_FILE
			;;
			*)
				qemu-system-x86_64 \\
					-kernel $KERNEL_FILE \\
					-initrd $INITRD_FILE \\
					-nographic \\
					-append "\$KERNEL_ARGS" \$QEMU_OPTIONS
			;;
		esac

		exit 
	;;
esac

PIPE="\$( mktemp )"
mkfifo "\$PIPE.in"
mkfifo "\$PIPE.out"

(
	qemu-system-x86_64 \\
		-kernel $KERNEL_FILE \\
		-initrd $INITRD_FILE \\
		-nographic \\
		-serial pipe:\$PIPE \\
		-append "\$KERNEL_ARGS" \$QEMU_OPTIONS
) &

PID=\$!

(
	while read -r LINE; do {
		case "\$LINE" in
			'# BOOTTIME_SECONDS '*|'# UNAME '*)
				echo "\$LINE" >>"\$PIPE"
			;;
			'# READY'*)
				echo 'READY' >>"\$PIPE"
				break
			;;
		esac
	} done <"\$PIPE.out"
) &

I=5
while [ \$I -gt 0 ]; do {
	LINE="\$( tail -n1 "\$PIPE" )"

	case "\$LINE" in
		READY) break ;;
		*) sleep 1; I=\$((I-1)) ;;
	esac
} done

kill -0 \$PID && kill \$PID

cat "\$PIPE"
rm -f "\$PIPE" "\$PIPE.in" "\$PIPE.out"
!

chmod +x "$LINUX_BUILD/run.sh" && \
	  $LINUX_BUILD/run.sh 'autotest'

echo
echo "see: $LINUX_BUILD/run.sh"
