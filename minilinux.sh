#!/bin/sh

KERNEL="$1"		# e.g. 'latest' or '5.4.89' or '4.19.x' or URL-to-tarball
[ -n "$2" ] && {
	shift
	OPTIONS="$*"	# see has_arg()
}

BASEDIR='minilinux'
CPU="$( nproc || sysctl -n hw.ncpu || lsconf | grep -c 'proc[0-9]' )"
[ "${CPU:-0}" -lt 1 ] && CPU=1

URL_TOYBOX='http://landley.net/toybox/downloads/toybox-0.8.4.tar.gz'
URL_BUSYBOX='https://busybox.net/downloads/busybox-1.33.0.tar.bz2'
URL_DASH='https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-0.5.11.3.tar.gz'
URL_MUSL='https://musl.libc.org/releases/musl-1.2.2.tar.gz'

export LC_ALL=C
export STORAGE="/tmp/storage"
mkdir -p "$STORAGE"
echo "[OK] cache/storage is here: '$STORAGE'"

# change from comma to space delimited list
OPTIONS="$OPTIONS $( echo "$FEATURES" | tr ',' ' ' )"

has_arg()
{
	case " $OPTIONS " in *" $1 "*) true ;; *) false ;; esac
}

install_dep()
{
	local package="$1"	# e.g. gcc-i686-linux-gnu

	dpkg -l "$package" >/dev/null || {
		[ -n "$APT_UPDATE" ] || {
			if sudo apt-get update; then
				APT_UPDATE='true'
			else
				msg_and_die "$?" "sudo apt-get update"
			fi
		}

		sudo apt-get install -y "$package" || msg_and_die "$?" "sudo apt-get install -y $package"
	}
}

has_arg 'UML' && DSTARCH='uml'
#
case "$DSTARCH" in
	armel)	# FIXME! on arm / qemu-system-arm / we should switch to qemu -M virt without DTB and smaller config
		# old ARM, 32bit
		export ARCH='ARCH=arm' CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabi-'
		export BOARD='versatilepb' DTB='versatile-pb.dtb' DEFCONFIG='versatile_defconfig'
		install_dep 'gcc-arm-linux-gnueabi'
	;;
	armhf)	# https://superuser.com/questions/1009540/difference-between-arm64-armel-and-armhf
		# arm7 / 32bit with power / hard float
		export ARCH='ARCH=arm' CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabihf-'
		export BOARD='vexpress-a9' DTB='vexpress-v2p-ca9.dtb' DEFCONFIG='vexpress_defconfig'
		install_dep 'gcc-arm-linux-gnueabihf'
	;;
	arm64)	# new arm, 64bit
		export ARCH='ARCH=arm64' CROSSCOMPILE='CROSS_COMPILE=aarch64-linux-gnu-'
		export BOARD='virt' DEFCONFIG='allnoconfig'
		install_dep 'gcc-aarch64-linux-gnu'
	;;
	um|uml)	export ARCH='ARCH=um'
		export DEFCONFIG='tinyconfig'
		export DSTARCH='uml'

		# https://unix.stackexchange.com/questions/90078/which-one-is-lighter-security-and-cpu-wise-lxc-versus-uml

		has_arg '32bit' && test "$(arch)" != i686 && \
			export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-' && \
			install_dep 'gcc-i686-linux-gnu'
	;;
	i386|i486|i586|i686)
		DSTARCH='i686'		# 32bit
		export DEFCONFIG='tinyconfig'
		export ARCH='ARCH=i386'

		OPTIONS="$OPTIONS 32bit"
		has_arg '32bit' && test "$(arch)" != i686 && \
			export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-' && \
			install_dep 'gcc-i686-linux-gnu'
	;;
	*)	export DEFCONFIG='tinyconfig'
	;;
esac

has_arg 'tinyconfig'	&& DEFCONFIG='tinyconfig'
has_arg 'allnoconfig'	&& DEFCONFIG='allnoconfig'
has_arg 'defconfig'	&& DEFCONFIG='defconfig'
has_arg 'config'	&& DEFCONFIG='config'		# e.g. kernel 2.4.x

case "$DSTARCH" in
	uml)
	;;
	*)
		install_dep 'qemu-system'
	;;
esac

has_arg 'debug' || {
	SILENT_MAKE='-s'
	SILENT_CONF='--enable-silent-rules'
}

deps_check()
{
	local cmd list='arch basename cat chmod cp file find grep gzip make mkdir rm sed strip tar tee test touch tr wget'
	# these commands are used, but are not essential:
	# logger, vimdiff, xz, zstd, dpkg, apt

	for cmd in $list; do {
		command -v "$cmd" >/dev/null || {
			printf '%s\n' "[ERROR] missing command: '$cmd' - please install"
			return 1
		}
	} done

	install_dep 'build-essential'

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
	local cache

	cache="$STORAGE/$( basename "$url" )"

	if [ -s "$cache" ]; then
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
	exit "$rc"
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
		# e.g. 1 or 22 or latest
		KERNEL_URL="$( kernels "$KERNEL" )"
		echo "[OK] choosing '$KERNEL_URL'"
	;;
	[0-9].*)
		# e.g. 4.19.x -> 4.19.169
		case "$KERNEL" in
			*'.x')
				# this will fail, if not on mainpage anymore!
				KERNEL="$( echo "$KERNEL" | cut -d'x' -f1 )"
				KERNEL="$( wget -qO - https://www.kernel.org | sed -n "s/.*<strong>\(${KERNEL}[0-9]*\)<.*/\1/p" )"
			;;
		esac

		case "$KERNEL" in
			*'-rc'*)
				# recent mainline:
				KERNEL_URL="https://git.kernel.org/torvalds/t/linux-${KERNEL}.tar.gz"
			;;
			*)
				# e.g. 5.4.89 -> dir v5.x + file 5.4.89
				KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL%%.*}.x/linux-${KERNEL}.tar.xz"
			;;
		esac

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
mkdir -p "$BASEDIR" && {
	cd "$BASEDIR" || exit
}

export OPT="$PWD/opt"
mkdir -p "$OPT"

export BUILDS="$PWD/builds"
mkdir -p "$BUILDS"

export LINUX="$OPT/linux"
mkdir -p "$LINUX"

export LINUX_BUILD="$BUILDS/linux"
mkdir -p "$LINUX_BUILD"

rm -f "$LINUX_BUILD/doc.txt" 2>/dev/null

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
# CONFIG_IA32_EMULATION=y

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
# CONFIG_PROC_FS=y
# CONFIG_SYSFS=y
#
# ARM64_PTR_AUTH is not set
# ARM64_TLB_RANGE is not set
EOF
}

initrd_format()
{
	local testformat="$1"	# e.g. BZIP2
	local o=

	case "$( file -b "$INITRD_FILE" )" in
		'gzip compressed data'*)  o='GZIP' ;;
		'bzip2 compressed data'*) o='BZIP2' ;;
		'LZMA compressed data'*)  o='LZMA' ;;
		'XZ compressed data'*)    o='XZ' ;;
		'lzop compressed data'*)  o='LZO' ;;
		'LZ4 compressed data'*)   o='LZ4' ;;
		'Zstandard compressed '*) o='ZSTD' ;;
	esac

	case "$testformat" in
		  '') echo "$o" ;;
		"$o") true ;;
		   *) false ;;
	esac
}

list_kernel_symbols()
{
	case "$DSTARCH" in
		armel|armhf)
			echo '# CONFIG_64BIT is not set'
		;;
		*)
			if has_arg '32bit'; then
				echo '# CONFIG_64BIT is not set'
			else
				echo 'CONFIG_64BIT=y'

				# support for 32bit binaries
				# note: does not work/exist in uml: https://uml.devloop.org.uk/faq.html
				case "$DSTARCH" in
					uml) ;;
					*) echo 'CONFIG_IA32_EMULATION=y' ;;
				esac
			fi
		;;
	esac

	has_arg 'net' && {
		echo 'CONFIG_NET=y'
		echo 'CONFIG_NETDEVICES=y'

		echo 'CONFIG_PACKET=y'
		echo 'CONFIG_UNIX=y'
		echo 'CONFIG_INET=y'

		echo 'CONFIG_IP_PNP=y'
		echo 'CONFIG_IP_PNP_DHCP=y'

		if [ "$DSTARCH" = uml ]; then
			echo 'CONFIG_UML_NET=y'
			echo 'CONFIG_UML_NET_SLIRP=y'
		else
			echo 'CONFIG_PCI=y'
			# echo 'CONFIG_E1000=y'		# lspci -nk will show attached driver
			echo 'CONFIG_8139CP=y'		# needs: -net nic,model=rtl8139 (but kernel is ~32k smaller)
		fi
	}

	cat <<EOF
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_$( initrd_format )=y
$( initrd_format GZIP  || echo '# CONFIG_RD_GZIP is not set'  )
$( initrd_format BZIP2 || echo '# CONFIG_RD_BZIP2 is not set' )
$( initrd_format LZMA  || echo '# CONFIG_RD_LZMA is not set'  )
$( initrd_format XZ    || echo '# CONFIG_RD_XZ is not set'    )
$( initrd_format LZO   || echo '# CONFIG_RD_LZO is not set'   )
$( initrd_format LZ4   || echo '# CONFIG_RD_LZ4 is not set'   )
$( initrd_format ZSTD  || echo '# CONFIG_RD_ZSTD is not set'  )
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TTY=y
EOF

	case "$DSTARCH" in
		uml)
			echo 'CONFIG_STATIC_LINK=y'
		;;
		*)
			echo 'CONFIG_SERIAL_8250=y'
			echo 'CONFIG_SERIAL_8250_CONSOLE=y'
		;;
	esac

	if has_arg 'swap'; then
		echo 'CONFIG_SWAP=y'
	else
		echo '# CONFIG_SWAP is not set'
	fi

	if has_arg 'printk'; then
		echo 'CONFIG_PRINTK=y'
		echo 'CONFIG_EARLY_PRINTK=y'
	else
		echo '# CONFIG_PRINTK is not set'
		echo '# CONFIG_EARLY_PRINTK is not set'
	fi

	has_arg 'procfs' && echo 'CONFIG_PROC_FS=y'
	has_arg 'sysfs'  && echo 'CONFIG_SYSFS=y'

	true
}

emit_doc()
{
	local message="$1"
	local context file="$LINUX_BUILD/doc.txt"

	context="$( basename "$( pwd )" )"	# e.g. busybox or linux

	echo >>"$file" "# doc | $context | $message"
}

apply()
{
	local symbol="$1"		# e.g. CONFIG_PRINTK=y
	local word="${symbol%=*}"	# e.g. CONFIG_PRINTK

	echo "[OK] applying symbol '$symbol'"

	case "$symbol" in
		'')
			return 0
		;;
		'#'*)
			# e.g. '# CONFIG_PRINTK is not set'
			# e.g. '# CONFIG_64BIT is not set'
			# shellcheck disable=SC2086
			set -- $symbol

			if   grep -q ^"$2=y"$ .config; then
				sed -i "/^$2=y/d" '.config'
				echo "$symbol" >>.config
				emit_doc "delete symbol: $2=y | write symbol: $symbol"

				yes "" | make $SILENT_MAKE $ARCH oldconfig || emit_doc "failed: make $ARCH oldconfig"
			elif grep -q ^"$symbol"$ .config; then
				:
				# emit_doc "already found symbol needed: $symbol"
			else
				emit_doc "write unfound symbol: $symbol"
				echo "$symbol" >>'.config'
				yes "" | make $SILENT_MAKE $ARCH oldconfig || emit_doc "failed: make $ARCH oldconfig"
			fi

			return 0
		;;
	esac

#	emit_doc "word: $word symbol: $symbol"

	# TODO: work without -i
	sed -i "/^$word=.*/d" '.config'		# delete line e.g. 'CONFIG_PRINTK=y'
	sed -i "/.*$word .*/d" '.config'	# delete line e.g. '# CONFIG_PRINTK is not active'
	echo "$symbol" >>'.config'		# write line e.g.  'CONFIG_PRINTK=y'
	emit_doc "write symbol: $symbol"

	# see: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/scripts/config
	yes "" | make $SILENT_MAKE $ARCH oldconfig || {
		emit_doc "failed: make $ARCH oldconfig"
		# return 0
	}

	grep -q ^"$symbol"$ .config || {
		echo "#"
		echo "[ERROR] added symbol '$symbol' not found in file '.config' pwd '$PWD'"
		echo "#"

		emit_doc "symbol after make notfound: $symbol"
		false
	}

	true	# FIXME!
}

###
### busybox|tyobox|dash + rootfs/initrd ####
###

install_dep 'build-essential'		# prepare for 'make'

export MUSL="$OPT/musl"
mkdir -p "$MUSL"

export MUSL_BUILD="$BUILDS/musl"
mkdir -p "$MUSL_BUILD"

has_arg 'dash' && {
	export DASH="$OPT/dash"
	mkdir -p "$DASH"

	export DASH_BUILD="$BUILDS/dash"
	mkdir -p "$DASH_BUILD"

	download "$URL_MUSL" || exit
	mv ./*musl* "$MUSL_BUILD/" || exit
	cd "$MUSL_BUILD" || exit
	untar ./*
	cd ./* || exit
	./configure $SILENT_CONF --prefix="$MUSL" --disable-shared || exit
	make $SILENT_MAKE install || exit
	export CC_MUSL="$MUSL/bin/musl-gcc"

	download "$URL_DASH" || exit
	mv ./*dash* "$DASH_BUILD/" || exit
	cd "$DASH_BUILD" || exit
	untar ./*
	cd ./* || exit		# there is only 1 dir

	# https://github.com/amuramatsu/dash-static/blob/master/build.sh
	./autogen.sh || exit			# -> ./configure
	./configure $SILENT_CONF "CC=$CC_MUSL -static" "CPP=$CC_MUSL -static -E" --enable-static || exit
	make $SILENT_MAKE "-j$CPU" || exit

	DASH="$(pwd)/src/dash"
	strip "$DASH" || exit
}

export BUSYBOX="$OPT/busybox"
mkdir -p "$BUSYBOX"

export BUSYBOX_BUILD="$BUILDS/busybox"
mkdir -p "$BUSYBOX_BUILD"

cd "$BUSYBOX" || msg_and_die "$?" "cd $BUSYBOX"

if [ -f "$OWN_INITRD" ]; then
	:
elif has_arg 'toybox'; then
	download "$URL_TOYBOX" || exit
	mv ./*toybox* "$BUSYBOX_BUILD/"
else
	download "$URL_BUSYBOX" || exit	
fi

[ -f "$OWN_INITRD" ] || {
	has_arg 'toybox' && {
		cd "$BUSYBOX_BUILD" || exit
	}

	untar ./*
	cd ./* || exit		# there is only 1 dir
}

if [ -f "$OWN_INITRD" ]; then
	:
elif has_arg 'toybox'; then
	BUSYBOX_BUILD="$PWD"
	LDFLAGS="--static" make $SILENT_MAKE $ARCH $CROSSCOMPILE root || msg_and_die "$?" "LDFLAGS=--static make $ARCH $CROSSCOMPILE root"
else
	make $SILENT_MAKE O="$BUSYBOX_BUILD" $ARCH $CROSSCOMPILE defconfig || msg_and_die "$?" "make O=$BUSYBOX_BUILD $ARCH $CROSSCOMPILE defconfig"
fi

cd "$BUSYBOX_BUILD" || msg_and_die "$?" "$_"

if [ -f "$OWN_INITRD" ]; then
	:
elif has_arg 'toybox'; then
	:
else
	apply "CONFIG_STATIC=y" || exit
fi

has_arg 'menuconfig' && {
	while :; do {
		make $SILENT_MAKE $ARCH menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && \
			read -r GO && test "$GO" && break
	} done

#	comparing manually configured vs. apply()
#	cmp .config /home/bastian/software/minilinux/.config_busybox || vimdiff .config /home/bastian/software/minilinux/.config_busybox
}

CONFIG2="$PWD/.config"

if [ -f "$OWN_INITRD" ]; then
	:
elif has_arg 'toybox'; then
	LDFLAGS="--static" make $SILENT_MAKE "-j$CPU" $ARCH $CROSSCOMPILE toybox || \
		msg_and_die "$?" "LDFLAGS=--static make $ARCH $CROSSCOMPILE toybox"
	test -s toybox || msg_and_die "$?" "test -s toybox"

	LDFLAGS="--static" make $SILENT_MAKE "-j$CPU" $ARCH $CROSSCOMPILE sh || \
		msg_and_die "$?" "LDFLAGS=--static make $ARCH $CROSSCOMPILE sh"
	test -s sh || msg_and_die "$?" "test -s sh"

	mkdir '_install'
	PREFIX="$BUSYBOX_BUILD/_install" make $SILENT_MAKE $ARCH $CROSSCOMPILE install || msg_and_die "$?" "PREFIX='$BUSYBOX_BUILD/_install' make $ARCH $CROSSCOMPILE install"
else
	# busybox:
	make $SILENT_MAKE "-j$CPU" $ARCH $CROSSCOMPILE || msg_and_die "$?" "make $ARCH $CROSSCOMPILE"
	make $SILENT_MAKE $ARCH $CROSSCOMPILE install  || msg_and_die "$?" "make $ARCH $CROSSCOMPILE install"
fi

cd ..

if [ -f "$OWN_INITRD" ]; then
	:
else
	export INITRAMFS_BUILD="$BUILDS/initramfs"
	mkdir -p "$INITRAMFS_BUILD"
	cd "$INITRAMFS_BUILD" || exit

	mkdir -p bin sbin etc proc sys usr/bin usr/sbin dev tmp
	cp -a "$BUSYBOX_BUILD/_install/"* .
fi

[ -n "$KEEP_LIST" ] && {
	find . | while read -r LINE; do {
		# e.g. ./bin/busybox -> dot is removed in check

		case " $KEEP_LIST " in
			*" ${LINE#?} "*) logger -s "KEEP_LIST: keeping '$LINE'" ;;
			*) test -d "$LINE" || rm -f "$LINE" ;;
		esac
	} done
}

[ -s "$DASH" ] && cp -v "$DASH" bin/dash	# FIXME! it still does not run

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
	command -v 'ip' >/dev/null && \
	  ip link show dev eth0 && \
	    ip address add 10.0.2.15/24 dev eth0 && \
	      ip link set dev eth0 up && \
	        ip route add default via 10.0.2.2 && \
	          printf '%s\\n' 'nameserver 8.8.4.4' >/etc/resolv.conf
}

UNAME="\$( command -v uname || printf '%s' false )"
printf '%s\n' "# BOOTTIME_SECONDS \${UP:--1}"
printf '%s\n' "# MEMFREE_KILOBYTES \${MEMAVAIL_KB:--1}"
printf '%s\n' "# UNAME \$( \$UNAME -a || printf uname_unavailable )"
printf '%s\n' "# READY - to quit $( test "$DSTARCH" = uml && echo "type 'exit'" || echo "press once CTRL+A and then 'x' or kill qemu" )"

# hack for MES:
test -f init.user && busybox sleep 2 && AUTO=true ./init.user	# wait for dmesg-trash

exec /bin/sh 2>/dev/null
EOF

chmod +x 'init'

case "$( file -b 'init' )" in
	ELF*) ;;
	*) sh -n 'init' || { RC=$?; echo "$PWD/init"; exit $RC; } ;;
esac

if [ -f "$OWN_INITRD" ]; then
	INITRD_FILE="$OWN_INITRD"
else
	# xz + zstd only for comparison, not productive
	find . -print0 | cpio --create --null --format=newc | xz -9  --format=lzma    >"$BUILDS/initramfs.cpio.xz"    || true
	find . -print0 | cpio --create --null --format=newc | xz -9e --format=lzma    >"$BUILDS/initramfs.cpio.xz.xz" || true
	find . -print0 | cpio --create --null --format=newc | zstd -v -T0 --ultra -22 >"$BUILDS/initramfs.cpio.zstd"  || true
	find . -print0 | cpio --create --null --format=newc | gzip -9                 >"$BUILDS/initramfs.cpio.gz"

	INITRD_FILE="$(  readlink -e "$BUILDS/initramfs.cpio.gz" )"
	INITRD_FILE2="$( readlink -e "$BUILDS/initramfs.cpio.xz"    || true )"
	INITRD_FILE3="$( readlink -e "$BUILDS/initramfs.cpio.xz.xz" || true )"
	INITRD_FILE4="$( readlink -e "$BUILDS/initramfs.cpio.zstd"  || true )"
fi

BB_FILE="$BUSYBOX_BUILD/busybox"
has_arg 'toybox' && BB_FILE="$BUSYBOX_BUILD/toybox"

###
### linux kernel ###
###

cd "$LINUX" || exit
download "$KERNEL_URL" || exit
untar ./*
cd ./* || exit		# there is only 1 dir

# kernel 2,3,4 but nut 5.x - FIXME!
# sed -i 's|-Wall -Wundef|& -fno-pie|' Makefile


# e.g.: gcc (Debian 10.2.1-6) 10.2.1 20210110
for WORD in $( gcc --version ); do {
	test 2>/dev/null "${WORD%%.*}" -gt 1 || continue
	VERSION="${WORD%%.*}"	# e.g. 10.2.1-6 -> 10

	# /home/bastian/software/minilinux/minilinux/opt/linux/linux-3.19.8/include/linux/compiler-gcc.h:106:1:
	# fatal error: linux/compiler-gcc9.h: file or directory not found
	[ -f "include/linux/compiler-gcc${VERSION}.h" ] || \
		cp -v include/linux/compiler-gcc5.h "include/linux/compiler-gcc${VERSION}.h"
	break
} done


make $SILENT_MAKE $ARCH O="$LINUX_BUILD" distclean  || msg_and_die "$?" "make $ARCH O=$LINUX_BUILD distclean"	# needed?

make $SILENT_MAKE $ARCH O="$LINUX_BUILD" $DEFCONFIG || {
	RC=$?
	make $ARCH help
	msg_and_die "$RC" "make $ARCH O=$LINUX_BUILD $DEFCONFIG"
}

[ "$DEFCONFIG" = config ] && {
	make $SILENT_MAKE $ARCH O="$LINUX_BUILD" dep || msg_and_die "$?" "make $ARCH O=$LINUX_BUILD dep"
}

cd "$LINUX_BUILD" || exit

if [ -f "$OWN_KCONFIG" ]; then
	cp -v "$OWN_KCONFIG" .config
else
#	TODO: apply "CONFIG_INITRAMFS_SOURCE=\"$INITRD_FILE\""
#	list_kernel_symbols_arm64 | while read -r SYMBOL; do {

	list_kernel_symbols | while read -r SYMBOL; do {
		apply "$SYMBOL" || emit_doc "error: $?"
	} done

	list_kernel_symbols | while read -r SYMBOL; do {
		grep -q ^"$SYMBOL"$ .config || emit_doc "not-in-config | $SYMBOL"
	} done
fi

has_arg 'menuconfig' && {
	while :; do {
		make $SILENT_MAKE $ARCH menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && \
			read -r GO && test "$GO" && break
	} done
}

CONFIG1="$PWD/.config"

# logger -s "please make changes in '$( pwd )' now and press enter | FIXME!"
# read NOP

if has_arg 'no_pie'; then
	T0="$( date +%s )"
	echo "make        $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie -j$CPU"
	make $SILENT_MAKE $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie -j"$CPU" || \
		msg_and_die "$?" "make $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie"
	T1="$( date +%s )"
else
	T0="$( date +%s )"
	echo "make        $ARCH $CROSSCOMPILE -j$CPU"
	make $SILENT_MAKE $ARCH $CROSSCOMPILE -j"$CPU" || msg_and_die "$?" "make $ARCH $CROSSCOMPILE"
	T1="$( date +%s )"
fi
KERNEL_TIME=$(( T1 - T0 ))

# e.g. $LINUX_BUILD/arch/x86_64/boot/bzImage
# e.g. $LINUX_BUILD/arch/arm/boot/zImage
KERNEL_FILE="$( find "$LINUX_BUILD" -type f -name '*zImage' )"
[ -f "$KERNEL_FILE" ] || KERNEL_FILE="$LINUX_BUILD/vmlinux"	# e.g. arm64 or uml

if [ -f "$KERNEL_FILE" ]; then
	case "$( file -b "$KERNEL_FILE" )" in
		*'not stripped'*) strip "$KERNEL_FILE" ;;
	esac
else
	msg_and_die "$?" "no file found: '$KERNEL_FILE' in pwd: $( pwd )"
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
			DTB="$( find "$LINUX_BUILD/" -type f -name "$DTB" )"
		fi
	;;
	uml)
		has_arg 'net' && {
			SLIRP_DIR="$( mktemp -d )"
			cd "$SLIRP_DIR" || exit
			git clone --depth 1 https://github.com/bittorf/slirp-uml-and-compiler-friendly.git

			cd ./*
			OK="$( ./run.sh | grep 'everything worked, see folder' )"
			SLIRP_BIN="$( echo "$OK" | cut -d"'" -f2 )"
			SLIRP_BIN="$( find "$SLIRP_BIN" -type f -name 'slirp.stripped' )"
		}
	;;
esac

INITRD_TEMP="$( mktemp -d )" || exit
( cd "$INITRD_TEMP" && gzip -cd "$INITRD_FILE" | cpio -idm )
INITRD_FILES="$( find "$INITRD_TEMP" -type f | wc -l )"
INITRD_LINKS="$( find "$INITRD_TEMP" -type l | wc -l )"
INITRD_DIRS="$(  find "$INITRD_TEMP" -type d | wc -l )"
INITRD_BYTES="$( find "$INITRD_TEMP" -type f -exec cat {} \; | wc -c )"
rm -fR "$INITRD_TEMP"

# TODO: include build-instructions
cat >"$LINUX_BUILD/run.sh" <<!
#!/bin/sh

ACTION="\$1"		# autotest|boot
PATTERN="\$2"		# in autotest-mode pattern for end-detection
MAX="\${3:-86400}"	# max running time [seconds] in autotest-mode

[ -z "\$MEM" ] && MEM="${MEM:-256M}"	# if not given via ENV
[ -z "\$LOG" ] && LOG="${LOG:-/dev/null}"
[ -z "\$LOGTIME" ] && LOGTIME=true

# generated: $( date )
#
# ARCHITECTURE: ${DSTARCH:-default} / ${ARCH:-default}
# COMPILER: ${CROSSCOMPILE:-cc}
#
# KERNEL_URL: $KERNEL_URL
# KERNEL_CONFIG: $CONFIG1
$( sed -n '1,5s/^/#                /p' "$CONFIG1" )
# KERNEL_BUILD_TIME: $KERNEL_TIME sec
# KERNEL: $KERNEL_FILE
# KERNEL_ELF: $KERNEL_ELF
# KERNEL_SIZE: $( wc -c <"$KERNEL_FILE" ) bytes compressed
# KERNEL_ELF: $(  wc -c <"$KERNEL_ELF" ) bytes
#   show sections with: readelf -S $KERNEL_ELF
#
# BUSYBOX: $BB_FILE
# BUSYBOX_SIZE: $( wc -c <"$BB_FILE" || echo 0 ) bytes
# BUSYBOX_CONFIG: $CONFIG2
#
# INITRD:  $(  wc -c <"$INITRD_FILE"  || echo 0 ) bytes = $INITRD_FILE
# INITRD2: $(  wc -c <"$INITRD_FILE2" || echo 0 ) bytes = ${INITRD_FILE2:-<nofile>}
# INITRD3: $(  wc -c <"$INITRD_FILE3" || echo 0 ) bytes = ${INITRD_FILE3:-<nofile>}
# INITRD3: $(  wc -c <"$INITRD_FILE4" || echo 0 ) bytes = ${INITRD_FILE4:-<nofile>}
#   decompress: gzip -cd $INITRD_FILE | cpio -idm
#
# INITRD files......: $INITRD_FILES
#        symlinks...: $INITRD_LINKS
#        directories: $INITRD_DIRS
#        bytes......: $INITRD_BYTES
# ---
$( cat "$LINUX_BUILD/doc.txt" )
# ---

QEMU='qemu-system-$( has_arg '32bit' && echo 'i386' || echo 'x86_64' )'
KERNEL_ARGS='console=ttyS0'
[ -z "\$PATTERN" ] && PATTERN="<hopefully_this_pattern_will_never_match>"

grep -q svm /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
grep -q vmx /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
[ -n "\$KVM_SUPPORT" ] && test "\$( id -u )" -gt 0 && KVM_PRE="\$( command -v sudo )"

case "${DSTARCH:-\$( arch || echo native )}" in armel|armhf|arm|arm64)
	DTB='$DTB'
	KVM_SUPPORT="-M $BOARD \${DTB:+-dtb }\$DTB" ; KVM_PRE=; QEMU='qemu-system-arm'; KERNEL_ARGS='console=ttyAMA0'
	[ "$DSTARCH" = arm64 ] && QEMU='qemu-system-aarch64' && KVM_SUPPORT="\$KVM_SUPPORT -cpu max"
	;;
	uml)
		QEMU="$( basename "$KERNEL_FILE" )"	# for later kill
		KVM_PRE=				# sudo unneeded?
	;;
esac

$( test -f "$BIOS" && echo "BIOS='-bios \"$BIOS\"'" )
$( has_arg 'net' && echo "KERNEL_ARGS='console=ttyS0 ip=dhcp nameserver=8.8.8.8'" )
QEMU_OPTIONS=
$( has_arg 'net' && echo "QEMU_OPTIONS='-net nic,model=rtl8139 -net user'" )
$( test -x "$SLIRP_BIN" && echo "UMLNET='eth0=slirp,FE:FD:01:02:03:04,$SLIRP_BIN'" )

case "\$ACTION" in
	autotest)
	;;
	boot|'')
		set -x

		case "$DSTARCH" in
			uml)
				echo "INTERACTIVE: will start now UML-linux:"
				echo

				DIR="\$( mktemp -d )" || exit
				export TMPDIR="\$DIR"

				$KERNEL_FILE mem=\$MEM \$UMLNET \\
					initrd=$INITRD_FILE

				rm -fR "\$DIR"
			;;
			*)
				echo "INTERACTIVE: will start now QEMU: \$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT ..."
				echo

				\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\
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
	case "$DSTARCH" in
		uml)
			echo "AUTOTEST for \$MAX sec: will start now UML-linux"
			echo

			DIR="\$( mktemp -d )" || exit
			export TMPDIR="\$DIR"

			$KERNEL_FILE mem=\$MEM \$UMLNET \\
				initrd=$INITRD_FILE >"\$PIPE.out"

			rm -fR "\$DIR"
		;;
		*)
			echo "AUTOTEST for \$MAX sec: will start now QEMU: \$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT ..."
			echo

			\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\
				-kernel $KERNEL_FILE \\
				-initrd $INITRD_FILE \\
				-nographic \\
				-serial pipe:\$PIPE \\
				-append "\$KERNEL_ARGS" \$QEMU_OPTIONS
		;;
	esac
) &

PID=\$!
T0="\$( date +%s )"

(
	while read -r LINE; do {
		case "\$LOGTIME" in
			true)
				DIFF="\$( date +%s )"
				DIFF=\$(( DIFF - T0 ))

				HOUR=\$(( DIFF / 3600 ))
				REST=\$(( DIFF - (HOUR*3600) ))
				MINU=\$(( REST / 60 ))
				REST=\$(( REST - (MINU * 60) ))

				# e.g. 01h45m23s | message_xy
				printf '%02d%s%02d%s%02d%s | %s\n' "\$HOUR" h "\$MINU" m "\$REST" s "\$LINE"
			;;
			*)
				printf '%s\n' "\$LINE"
			;;
		esac

		case "\$LINE" in
			'# BOOTTIME_SECONDS '*|'# UNAME '*)
				echo "\$LINE" >>"\$PIPE"
			;;
			"\$PATTERN"*|*' Attempted to kill init'*|'ABORTING HARD'*|'Bootstrapping completed.'|'Aborted (core dumped)')
				echo 'READY' >>"\$PIPE"
				break
			;;
		esac
	} done <"\$PIPE.out" | tee "\$LOG"
) &

RC=1
[ -z "\$PATTERN" ] && RC=0
[ "\$PATTERN" = '<hopefully_this_pattern_will_never_match>' ] && RC=0

I=\$MAX
while [ \$I -gt 0 ]; do {
	kill -0 \$PID || break
	LINE="\$( tail -n1 "\$PIPE" )"

	case "\$LINE" in
		READY) RC=0 && break ;;
		*) sleep 1; I=\$(( I - 1 )) ;;
	esac
} done

[ -s "\$LOG" ] && {
	LOGLINES="\$( wc -l <"\$LOG" )"
	LOGSIZE="\$(  wc -c <"\$LOG" )"
	LOGINFO="(\$LOGLINES lines, \$LOGSIZE bytes) "
}

echo
echo "# autotest-mode ready after \$(( MAX - I )) (out of max \$MAX) seconds"
echo "# RC:\$RC | PATTERN:\$PATTERN | logfile \${LOGINFO}written to '\$LOG'"
echo "#"
echo "# you can manually startup again:"
echo "# \$0"
echo "# in dir '\$(pwd)'"
echo

echo "will now stop '\$QEMU' with pid \$PID" && \$KVM_PRE echo
while \$KVM_PRE kill -0 \$PID; do \$KVM_PRE kill \$PID \$( pidof \$QEMU ); sleep 1; done
rm -f "\$PIPE" "\$PIPE.in" "\$PIPE.out"

test \$RC -eq 0
!

ABORT_PATTERN='# READY'
[ -f "$OWN_INITRD" ] && ABORT_PATTERN=

chmod +x "$LINUX_BUILD/run.sh" && \
	 "$LINUX_BUILD/run.sh" 'autotest' "$ABORT_PATTERN" 5
RC=$?

echo
echo "# RC:$RC | see: $LINUX_BUILD/run.sh"
echo "#"
echo "# thanks for using:"
echo "# https://github.com/bittorf/kritis-linux"
echo

test $RC -eq 0
