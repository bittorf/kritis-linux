#!/bin/sh
#
# TODO:
# - add maybe -no-reboot?
# - builddir = mark_cache = no_backup
# - net: nameserver?
# - nproc/memsize
# - UML http://user-mode-linux.sourceforge.net/network.html
# - api kernel+busybox+toybox+gcc... download/version
# - different recipes: minimal, net, compiler, net-compiler
# - which programs where called? hash?
# - upload/api: good + bad things
# - upload bootable images
# - safe versions of all deps (cc, ld, libc)
# - filesizes
# - needed space


# possible vars to export into this script:
#
# OWN_KCONFIG=file
# DSTARCH=armhf		# https://superuser.com/questions/1009540/difference-between-arm64-armel-and-armhf
# INITRD_DIR_ADD= ...	# e.g. /tmp/foo
# KEEP_LIST= ...	# e.g. '/bin/busybox /bin/sh /bin/cat'
			# busybox find / -xdev -name 'sh'
			# busybox find / -xdev -type l
			# busybox find / -xdev -type f

KERNEL="$1"
[ -n "$2" ] && {
	shift
	OPTIONS="$*"		# e.g. 64bit,32bit,no_pie,no_printk,net and 'toybox' and 'UML' and 'menuconfig'
}

CPU="$( nproc || echo 1 )"
BASEDIR='minilinux'

URL_TOYBOX='http://landley.net/toybox/downloads/toybox-0.8.4.tar.gz'
URL_BUSYBOX='https://busybox.net/downloads/busybox-1.33.0.tar.bz2'

export STORAGE="/tmp/storage"
mkdir -p "$STORAGE"
echo "[OK] cache/storage is here: '$STORAGE'"

has_arg()
{
	case " $OPTIONS " in *" $1 "*) true ;; *) false ;; esac
}

# FIXME! on arm / qemu-system-arm / we should switch to qemu -M virt without DTB and smaller config
#   apt: gcc-arm-linux-gnueabi   = armel = older 32bit
#   apt: gcc-arm-linux-gnueabihf = armhf = arm7 / 32bit with power / hard float
#   apt: gcc-aarch64-linux-gnu   = arm64 = 64bit
#
has_arg 'UML' && DSTARCH='uml'
#
case "$DSTARCH" in
	uml)	export ARCH='ARCH=um'
		export DEFCONFIG='allnoconfig'
	;;
	armel)	export ARCH='ARCH=arm' CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabi-'
		export BOARD='versatilepb' DTB='versatile-pb.dtb' DEFCONFIG='versatile_defconfig'
	;;
	armhf)	export ARCH='ARCH=arm' CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabihf-'
		export BOARD='vexpress-a9' DTB='vexpress-v2p-ca9.dtb' DEFCONFIG='vexpress_defconfig'
	;;
	arm64)	export ARCH='ARCH=arm64' CROSSCOMPILE='CROSS_COMPILE=aarch64-linux-gnu-'
		export BOARD='virt' DEFCONFIG='allnoconfig'
	;;
	i386)
		OPTIONS="$OPTIONS,32bit"
		export CFLAGS=-m32
		export DEFCONFIG='allnoconfig'
	;;
	*)	export DEFCONFIG='allnoconfig'
	;;
esac

deps_check()
{
	local cmd list='gzip xz zstd wget cp basename mkdir rm cat make sed grep tar test find touch chmod file'
	# hint: 'vimdiff' and 'logger' are used, but not essential

	for cmd in $list; do {
		command -v "$cmd" >/dev/null || {
			printf '%s\n' "[ERROR] missing command: '$cmd' - please install"
			return 1
		}
	} done

	true
}

deps_check || exit

kernels()
{
	case "$1" in
		 0) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.16.83.tar.xz' ;;		# TODO: 32bit
		 1) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.4.222.tar.xz' ;;
		 2) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/linux-2.6.39.tar.xz' ;;	# TODO: 32bit?
		 3) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.9.222.tar.xz' ;;
		 4) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.121.tar.xz' ;;
		 5) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.5.19.tar.xz' ;;
		 6) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.6.11.tar.xz' ;;
		 7) echo 'https://git.kernel.org/torvalds/t/linux-5.7-rc4.tar.gz' ;;
		 8) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/linux-2.6.39.4.tar.xz' ;;
		 9) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-5.0.1.tar.gz' ;;
		10) echo 'https://git.kernel.org/pub/scm/linux/kernel/git/wtarreau/linux-2.4.git/snapshot/linux-2.4-2.4.37.11.tar.gz' ;;
		11) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.7.tar.xz' ;;
		12) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.8.12.tar.xz' ;;
		13) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.9.tar.xz' ;;
		14) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.10.1.tar.bz2' ;;
		15) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.17.tar.xz' ;;
		16) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.18.tar.xz' ;;
		17) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.19.tar.xz' ;;
		18) echo 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.19.8.tar.xz' ;;
		19) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.9.1.tar.xz' ;;
		20) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.10.6.tar.xz' ;;
		21) echo 'https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.215.tar.xz' ;;
		22) echo 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.89.tar.xz' ;;
		latest) wget -qO - https://www.kernel.org | grep -A1 "latest_link" | tail -n1 | cut -d'"' -f2 ;;
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
	[0-9]|[0-9][0-9]|latest)
		KERNEL_URL="$( kernels $KERNEL )"
		echo "[OK] choosing '$KERNEL_URL'"
	;;
	[0-9].*)
		# e.g. 5.4.89 -> dir v5.x + file 5.4.89
		KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL%.*}.x/linux-${KERNEL}.tar.xz"
		echo "[OK] choosing '$KERNEL_URL'"
	;;
	'http'*)
		KERNEL_URL="$KERNEL"
		echo "[OK] choosing '$KERNEL_URL'"
	;;
	'')
		echo "Usage: <number> or <url> or '5.4.89' or 'clean' or 'fill_cache' <option>"
		echo
		echo "choose 0,1,2,3..."
		echo

		minor_from_url() {	# outputs e.g. 5.4.39
			MINOR="$( echo "$1" | sed -n 's/.*linux-\([0-9].*\)/\1/p' )"	# e.g. 5.4.39.tar.xz

			while case "$MINOR" in
				*[0-9]) false ;;
				*) true ;;
			      esac; do {
				MINOR="${MINOR%.*}"
			} done

			echo "$MINOR"
		}

		I=0
		while KERNEL_URL="$( kernels $I )"; do {
			MINOR="$( minor_from_url "$KERNEL_URL" )"
			echo "$I | $MINOR"
			I=$((I+1))
		} done

		echo "latest | $( minor_from_url "$( kernels latest )" )"

		exit 1
	;;
	
esac

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

# https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e
# CONFIG_64BIT=y			| 64-bit kernel
# CONFIG_BLK_DEV_INITRD=y		| General setup ---> Initial RAM filesystem and RAM disk (initramfs/initrd) support
# CONFIG_PRINTK=y			| General setup ---> Configure standard kernel features ---> Enable support for printk 
# CONFIG_BINFMT_ELF=y			| Executable file formats / Emulations ---> Kernel support for ELF binaries
# CONFIG_BINFMT_SCRIPT=y		| Executable file formats / Emulations ---> Kernel support for scripts starting with #!		// support since 3.10?
# CONFIG_DEVTMPFS=y			| Device Drivers ---> Generic Driver Options ---> Maintain a devtmpfs filesystem to mount at /dev
# CONFIG_DEVTMPFS_MOUNT=y		| Device Drivers ---> Generic Driver Options ---> Automount devtmpfs at /dev, after the kernel mounted the rootfs
# CONFIG_TTY=y				| Device Drivers ---> Character devices ---> Enable TTY
# CONFIG_SERIAL_8250=y			| Device Drivers ---> Character devices ---> Serial drivers ---> 8250/16550 and compatible serial support
# CONFIG_SERIAL_8250_CONSOLE=y		| Device Drivers ---> Character devices ---> Serial drivers ---> Console on 8250/16550 and compatible serial port
# CONFIG_PROC_FS=y			| File systems ---> Pseudo filesystems ---> /proc file system support
# CONFIG_SYSFS=y			| File systems ---> Pseudo filesystems ---> sysfs file system support


list_kernel_symbols_arm64()
{
	cat <<EOF
CONFIG_BLK_DEV_INITRD=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TTY=y
CONFIG_PRINTK=y
CONFIG_SERIAL_AMBA_PL011=y
CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
CONFIG_SLUB=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
# ARM64_PTR_AUTH is not set
# ARM64_TLB_RANGE is not set
EOF
}

list_kernel_symbols()
{
	case "$DSTARCH" in
		uml|armel|armhf)
			echo '# CONFIG_64BIT is not set'
		;;
		*)
			if has_arg '32bit'; then
				echo '# CONFIG_64BIT is not set'
			else
				echo 'CONFIG_64BIT=y'
			fi
		;;
	esac

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

	echo "[OK] applying symbol '$symbol'"

	case "$symbol" in
		'#'*)
			return 0
		;;
	esac

	sed -i "/^$word=.*/d" '.config'
	sed -i "/.*$word .*/d" '.config'
	echo "$symbol" >>'.config'

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
	download "$URL_TOYBOX" || exit
	mv *toybox* $BUSYBOX_BUILD/
else
	download "$URL_BUSYBOX" || exit	
fi

has_arg 'toybox' && cd $BUSYBOX_BUILD

untar *
cd * || exit		# there is only 1 dir

if has_arg 'toybox'; then
	BUSYBOX_BUILD=$PWD
	LDFLAGS="--static" make $ARCH $CROSSCOMPILE root || msg_and_die "$?" "LDFLAGS=--static make $ARCH $CROSSCOMPILE root"
else
	make O=$BUSYBOX_BUILD $ARCH $CROSSCOMPILE defconfig || msg_and_die "$?" "make O=$BUSYBOX_BUILD $ARCH $CROSSCOMPILE defconfig"
fi

cd $BUSYBOX_BUILD || msg_and_die "$?" "$_"

if has_arg 'toybox'; then
	:
else
	for SYMBOL in 'CONFIG_STATIC=y'; do apply "$SYMBOL" || exit; done
fi

has_arg 'menuconfig' && {
	while :; do {
		make $ARCH menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && read GO && test "$GO" && break
	} done

#	comparing manually configured vs. apply()
#	cmp .config /home/bastian/software/minilinux/.config_busybox || vimdiff .config /home/bastian/software/minilinux/.config_busybox
}

CONFIG2="$PWD/.config"

if has_arg 'toybox'; then
	LDFLAGS="--static" make -j$CPU $ARCH $CROSSCOMPILE toybox || msg_and_die "$?" "LDFLAGS=--static make -j$CPU $ARCH $CROSSCOMPILE toybox"
	test -f toybox || msg_and_die "$?" "test -f toybox"

	mkdir '_install'
	PREFIX="$BUSYBOX_BUILD/_install" make $ARCH $CROSSCOMPILE install || msg_and_die "$?" "PREFIX='$BUSYBOX_BUILD/_install' make $ARCH $CROSSCOMPILE install"
else
	make -j$CPU $ARCH $CROSSCOMPILE || msg_and_die "$?" "make -j$CPU $ARCH $CROSSCOMPILE"
	make $ARCH $CROSSCOMPILE install || msg_and_die "$?" "make $ARCH $CROSSCOMPILE install"
fi

cd ..

export INITRAMFS_BUILD=$BUILDS/initramfs
mkdir -p $INITRAMFS_BUILD
cd $INITRAMFS_BUILD || exit

mkdir -p bin sbin etc proc sys usr/bin usr/sbin dev tmp
cp -a $BUSYBOX_BUILD/_install/* .

[ -n "$KEEP_LIST" ] && {
	find . | while read -r LINE; do {
		# e.g. ./bin/busybox -> dot is removed in check

		case " $KEEP_LIST " in
			*" ${LINE#?} "*) logger -s "KEEP_LIST: keeping '$LINE'" ;;
			*) test -d "$LINE" || rm -f "$LINE" ;;
		esac
	} done
}

# TODO: https://stackoverflow.com/questions/36529881/qemu-bin-sh-cant-access-tty-job-control-turned-off?rq=1

[ -d "$INITRD_DIR_ADD" ] && {
	# FIXME! we do not include a directory names 'x'
	test -d "$INITRD_DIR_ADD/x" && mv -v "$INITRD_DIR_ADD/x" ~/tmp.cheat.$$
	cp -R "$INITRD_DIR_ADD/"* .
	test -d ~/tmp.cheat.$$ && mv -v ~/tmp.cheat.$$ "$INITRD_DIR_ADD/x"

	[ -d kritis-linux ] && rm -fR kritis-linux

	test -f "$MYINIT" && mv -v "$MYINIT" 'init'

	test -f 'run-amd64.sh' && {		# FIXME! is a hack for MES
		mv 'run-amd64.sh' init.user
		rm -fR sys usr sbin etc root proc
		rm -f "LICENSE" "README.md" kernel.bin initramfs.cpio.gz initrd.xz
		touch 'tmp/hex0.bin' && chmod +x 'tmp/hex0.bin'
	}
}

[ -f init ] || cat >'init' <<EOF
#!/bin/sh
command -v mount && {
	mount -t proc  none /proc && {
		read -r UP _ </proc/uptime || UP=\$( cut -d' ' -f1 /proc/uptime )
		while read -r LINE; do case "\$LINE" in MemAvailable:*) set -- \$LINE; MEMAVAIL_KB=\$2; break ;; esac; done </proc/meminfo
	}

	mount -t sysfs none /sys

	# https://github.com/bittorf/slirp-uml-and-compiler-friendly
	# https://github.com/lubomyr/bochs/blob/master/misc/slirp.conf
	command -v 'ip' >/dev/null && {
		ip link show dev eth0 && {
			ip address add 10.0.2.15/24 dev eth0 && {
				ip link set dev eth0 up && {
					ip route add default via 10.0.2.2
				}
			}
		}
	}
}

UNAME="\$( command -v uname || printf '%s' false )"
printf '%s\n' "# BOOTTIME_SECONDS \${UP:--1}"
printf '%s\n' "# MEMFREE_KILOBYTES \${MEMAVAIL_KB:--1}"
printf '%s\n' "# UNAME \$( \$UNAME -a || printf uname_unavailable )"
printf '%s\n' "# READY - to quit $( if has_arg 'UML'; then echo "type 'exit'"; else echo "press once CTRL+A and then 'x' or kill qemu"; fi )"

# hack for MES:
test -f init.user && busybox sleep 2 && AUTO=true ./init.user	# wait for dmesg-trash

exec /bin/sh 2>/dev/null
EOF

chmod +x 'init'

case "$( file -b 'init' )" in
	ELF*) ;;
	*) sh -n 'init' || { RC=$?; echo "$PWD/init"; exit $RC; } ;;
esac

find . -print0 | cpio --create --null --format=newc | xz -9  --format=lzma    >$BUILDS/initramfs.cpio.xz
find . -print0 | cpio --create --null --format=newc | xz -9e --format=lzma    >$BUILDS/initramfs.cpio.xz.xz
find . -print0 | cpio --create --null --format=newc | zstd -v -T0 --ultra -22 >$BUILDS/initramfs.cpio.zstd
find . -print0 | cpio --create --null --format=newc | gzip -9                 >$BUILDS/initramfs.cpio.gz

INITRD_FILE="$(  readlink -e "$BUILDS/initramfs.cpio.gz"    )"
INITRD_FILE2="$( readlink -e "$BUILDS/initramfs.cpio.xz"    )"
INITRD_FILE3="$( readlink -e "$BUILDS/initramfs.cpio.xz.xz" )"
INITRD_FILE4="$( readlink -e "$BUILDS/initramfs.cpio.zstd"  )"
BB_FILE="$BUSYBOX_BUILD/busybox"
has_arg 'toybox' && BB_FILE="$BUSYBOX_BUILD/toybox"

###
### linux kernel ###
###

cd "$LINUX" || exit
download "$KERNEL_URL" || exit
untar *
cd * || exit		# there is only 1 dir

# kernel 2,3,4 but nut 5.x - FIXME!
# sed -i 's|-Wall -Wundef|& -fno-pie|' Makefile

# FIXME!
#[ -f 'include/linux/compiler-gcc9.h' ] || {
#	cp -v include/linux/compiler-gcc5.h include/linux/compiler-gcc9.h
#	cp -v include/linux/compiler-gcc5.h include/linux/compiler-gcc10.h
#}
#
# TODO:
# home/bastian/software/minilinux/minilinux/opt/linux/linux-3.19.8/include/linux/compiler-gcc.h:106:1: fatal error: linux/compiler-gcc9.h: Datei oder Verzeichnis nicht gefunden 

make $ARCH O=$LINUX_BUILD distclean		# needed?
make $ARCH O=$LINUX_BUILD $DEFCONFIG || exit
cd $LINUX_BUILD

if [ -f "$OWN_KCONFIG" ]; then
	cp -v "$OWN_KCONFIG" .config
elif has_arg 'UML'; then
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

#	set -x
#	apply "CONFIG_INITRAMFS_SOURCE=\"$INITRD_FILE\""
#	grep CONFIG_INITRAMFS_SOURCE= .config || {
#		echo "FIXME!" && exit
#	}
else
#	list_kernel_symbols_arm64 | while read -r SYMBOL; do {
	list_kernel_symbols | while read -r SYMBOL; do {
		apply "$SYMBOL" || exit
	} done
fi

has_arg 'menuconfig' && {
	while :; do {
		make $ARCH menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && read GO && test "$GO" && break
	} done
}

CONFIG1="$PWD/.config"

# logger -s "please make changes in '$( pwd )' now and press enter | FIXME!"
# read NOP

if has_arg 'no_pie'; then
	echo "make $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie -j$CPU"
	make       $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie -j$CPU || exit
else
	echo "make $ARCH $CROSSCOMPILE -j$CPU"
	make       $ARCH $CROSSCOMPILE -j$CPU || exit
fi

# e.g. $LINUX_BUILD/arch/x86_64/boot/bzImage
# e.g. $LINUX_BUILD/arch/arm/boot/zImage
KERNEL_FILE="$( find "$LINUX_BUILD" -type f -name '*zImage' )"
[ -f "$KERNEL_FILE" ] || KERNEL_FILE="$LINUX_BUILD/vmlinux"	# e.g. arm64 or uml

if [ -f "$KERNEL_FILE" ]; then
	logger -s "pwd: $( pwd ) found: '$KERNEL_FILE'"
else
	logger -s "pwd: $( pwd ) no file found: '$KERNEL_FILE'"
	exit 1
fi

cd .. || exit

if has_arg 'UML'; then
	KERNEL_FILE="$LINUX_BUILD/vmlinux"
else
	KERNEL_FILE="$( readlink -e "$KERNEL_FILE" )"
fi

KERNEL_ELF="$KERNEL_FILE.elf"
EXTRACT="$( find "$LINUX" -type f -name 'extract-vmlinux' )"
if [ -f "$EXTRACT" ]; then
	$EXTRACT "$KERNEL_FILE" >"$KERNEL_ELF"

	if [ -f "$KERNEL_ELF" ]; then
		:
	else
		logger -s "extracting ELF failed"
	fi
else
	logger -s "extractor for ELF not found"
fi

case "$DSTARCH" in
	arm*)
		if [ "$DTB" = 'auto' ]; then
			qemu-system-aarch64 -machine "$BOARD" -cpu max -machine dumpdtb=auto.dtb -nographic
			DTB="$( pwd )/auto.dtb"
		else
			DTB="$( find $LINUX_BUILD/ -type f -name "$DTB" )"
		fi
	;;
esac

# TODO: include build-instructions
cat >"$LINUX_BUILD/run.sh" <<!
#!/bin/sh

ACTION="\$1"		# autotest|boot
PATTERN="\${2:-READY}"	# in autotest-mode pattern for end-detection
MAX="\${3:-5}"		# max running time [seconds] in autotest-mode

# generated: $( LC_ALL=C date )
#
# ARCHITECTURE: ${DSTARCH:-default} / ${ARCH:-default}
# COMPILER: ${CROSSCOMPILE:-cc}
#
# KERNEL_URL: $KERNEL_URL
# KERNEL_CONFIG: $CONFIG1
$( sed -n '1,5s/^/#                /p' "$CONFIG1" )
# KERNEL: $KERNEL_FILE
# KERNEL_ELF: $KERNEL_ELF
# KERNEL_SIZE: $( wc -c <$KERNEL_FILE ) bytes compressed
# KERNEL_ELF: $(  wc -c <$KERNEL_ELF ) bytes
#   show sections with: readelf -S $KERNEL_ELF
#
# BUSYBOX: $BB_FILE
# BUSYBOX_SIZE: $( wc -c <$BB_FILE ) bytes
# BUSYBOX_CONFIG: $CONFIG2
#
# INITRD:  $(  wc -c <$INITRD_FILE ) bytes = $INITRD_FILE
# INITRD2: $(  wc -c <$INITRD_FILE2 ) bytes = $INITRD_FILE2
# INITRD3: $(  wc -c <$INITRD_FILE3 ) bytes = $INITRD_FILE3
# INITRD3: $(  wc -c <$INITRD_FILE4 ) bytes = $INITRD_FILE4
#   decompress: gzip -cd $INITRD_FILE | cpio -idm

QEMU='qemu-system-$( has_arg '32bit' && echo 'i386' || echo 'x86_64' )'
KERNEL_ARGS='console=ttyS0'

grep -q svm /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
grep -q vmx /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
[ -n "\$KVM_SUPPORT" ] && test "\$( id -u )" -gt 0 && KVM_PRE="\$( command -v sudo )"

case "${DSTARCH:-\$( arch || echo native )}" in armel|armhf|arm|arm64)
	DTB='$DTB'
	KVM_SUPPORT="-M $BOARD \${DTB:+-dtb }\$DTB" ; KVM_PRE=; QEMU='qemu-system-arm'; KERNEL_ARGS='console=ttyAMA0'
	[ "$DSTARCH" = arm64 ] && QEMU='qemu-system-aarch64' && KVM_SUPPORT="\$KVM_SUPPORT -cpu max"
esac

$( test -f "$BIOS" && echo "BIOS='-bios \"$BIOS\"'" )
$( has_arg 'net' && echo "KERNEL_ARGS='console=ttyS0 ip=dhcp nameserver=8.8.8.8'" )
QEMU_OPTIONS=
$( has_arg 'net' && echo "QEMU_OPTIONS='-net nic,model=rtl8139 -net user'" )

case "\$ACTION" in
	autotest)
	;;
	boot|'')
		set -x

		case "$DSTARCH" in
			uml)
				$KERNEL_FILE \\
					initrd=$INITRD_FILE
			;;
			*)
				\$KVM_PRE \$QEMU \$KVM_SUPPORT \$BIOS \\
					-kernel $KERNEL_FILE \\
					-initrd $INITRD_FILE \\
					-nographic \\
					-append "\$KERNEL_ARGS" \$QEMU_OPTIONS && set +x
			;;
		esac

		RC=\$? && set +x
		echo
		echo "# thanks for using:"
		echo "# https://github.com/bittorf/kritis-linux"
		echo
		exit \$RC
	;;
esac

PIPE="\$( mktemp )" || exit
mkfifo "\$PIPE.in"  || exit
mkfifo "\$PIPE.out" || exit
\$KVM_PRE echo			# cache sudo-pass for (maybe) next interactive run

(
	\$KVM_PRE \$QEMU \$KVM_SUPPORT \$BIOS \\
		-kernel $KERNEL_FILE \\
		-initrd $INITRD_FILE \\
		-nographic \\
		-serial pipe:\$PIPE \\
		-append "\$KERNEL_ARGS" \$QEMU_OPTIONS
) &

PID=\$!

(
	while read -r LINE; do {
		printf '%s\n' "\$LINE"

		case "\$LINE" in
			'# BOOTTIME_SECONDS '*|'# UNAME '*)
				echo "\$LINE" >>"\$PIPE"
			;;
			"\$PATTERN"*|"Kernel panic"*)
				echo 'READY' >>"\$PIPE"
				break
			;;
		esac
	} done <"\$PIPE.out"
) &

I=\$MAX
while [ \$I -gt 0 ]; do {
	LINE="\$( tail -n1 "\$PIPE" )"

	case "\$LINE" in
		READY) break ;;
		*) sleep 1; I=\$(( I - 1 )) ;;
	esac
} done

\$KVM_PRE kill -0 \$PID && \$KVM_PRE kill \$PID

rm -f "\$PIPE" "\$PIPE.in" "\$PIPE.out"

echo
echo "# autotest-mode ready after \$(( MAX - I )) (out of max \$MAX) seconds"
echo "# manual startup: \$0"
!

chmod +x "$LINUX_BUILD/run.sh" && \
	  $LINUX_BUILD/run.sh 'autotest' '# READY'

echo
echo "# see: $LINUX_BUILD/run.sh"
echo "#"
echo "# thanks for using:"
echo "# https://github.com/bittorf/kritis-linux"
echo
