#!/bin/sh

KERNEL="$1"		# e.g. 'latest' or '5.4.89' or '4.19.x' or URL-to-tarball
[ -n "$2" ] && {
	shift
	export OPTIONS="$*"	# see has_arg(), spaces are not working
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
		echo "[OK] need to install package '$package'"

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
		export QEMU='qemu-system-arm'
		install_dep 'gcc-arm-linux-gnueabi'
	;;
	armhf)	# https://superuser.com/questions/1009540/difference-between-arm64-armel-and-armhf
		# arm7 / 32bit with power / hard float
		export ARCH='ARCH=arm' CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabihf-'
		export BOARD='vexpress-a9' DTB='vexpress-v2p-ca9.dtb' DEFCONFIG='vexpress_defconfig'
		export QEMU='qemu-system-arm'
		install_dep 'gcc-arm-linux-gnueabihf'
	;;
	arm64)	# new ARM, 64bit
		# https://github.com/ssrg-vt/hermitux/wiki/Aarch64-support
		export ARCH='ARCH=arm64' CROSSCOMPILE='CROSS_COMPILE=aarch64-linux-gnu-'
		export BOARD='virt' DEFCONFIG='tinyconfig'
		export QEMU='qemu-system-aarch64'
		install_dep 'gcc-aarch64-linux-gnu'
	;;
	or1k)	# OpenRISC, 32bit
		# https://wiki.qemu.org/Documentation/Platforms/OpenRISC
		export ARCH='ARCH=openrisc' CROSSCOMPILE='CROSS_COMPILE=or1k-linux-musl-'
		export BOARD='or1k-sim' DEFCONFIG='tinyconfig'
		export QEMU='qemu-system-or1k'

		CROSS_DL="https://musl.cc/or1k-linux-musl-cross.tgz"
		OPTIONS="$OPTIONS 32bit"
	;;
	m68k)
		# see: arch/m68k/Kconfig.cpu
		# TODO: coldfire vs. m68k_classic vs. freescale/m68000 (nommu)
		# https://www.reddit.com/r/archlinux/comments/ejkp1x/what_is_the_name_of_this_font/fczfy60/
		# https://news.ycombinator.com/item?id=25027213
		# http://users.telenet.be/geertu/Linux/68000/
		export ARCH='ARCH=m68k' CROSSCOMPILE='CROSS_COMPILE=m68k-linux-gnu-'
		export BOARD='q800' DEFCONFIG='virt_defconfig'
		DEFCONFIG='mac_defconfig'
		export QEMU='qemu-system-m68k'
		install_dep 'gcc-m68k-linux-gnu'
	;;
	um|uml)	# http://uml.devloop.org.uk/kernels.html
		# https://unix.stackexchange.com/questions/90078/which-one-is-lighter-security-and-cpu-wise-lxc-versus-uml
		export ARCH='ARCH=um'
		export DEFCONFIG='tinyconfig'
		export DSTARCH='uml'

		has_arg '32bit' && {
			test "$(arch)" != i686 && \
			export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-' && \
			install_dep 'gcc-i686-linux-gnu'
		}
	;;
	i386|i486|i586|i686)
		DSTARCH='i686'		# 32bit
		export DEFCONFIG='tinyconfig'
		export ARCH='ARCH=i386'
		export QEMU='qemu-system-i386'

		OPTIONS="$OPTIONS 32bit"
		test "$(arch)" != i686 && \
			export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-' && \
			install_dep 'gcc-i686-linux-gnu'
	;;
	*)
		DSTARCH='x86_64'
		export DEFCONFIG='tinyconfig'
		export QEMU='qemu-system-x86_64'
	;;
esac

has_arg 'tinyconfig'	&& DEFCONFIG='tinyconfig'
has_arg 'allnoconfig'	&& DEFCONFIG='allnoconfig'
has_arg 'defconfig'	&& DEFCONFIG='defconfig'
has_arg 'config'	&& DEFCONFIG='config'		# e.g. kernel 2.4.x

case "$DSTARCH" in
	uml)
	;;
	or1k)
		install_dep 'qemu-system'
		install_dep 'qemu-system-misc'
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
	local cmd list='arch basename cat chmod cp file find grep gzip head make mkdir rm sed strip tar tee test touch tr wget'
	# these commands are used, but are not essential:
	# apt, bc, dpkg, ent, logger, vimdiff, xz, zstd

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
		23) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v2.4/linux-2.4.26.tar.xz' ;;
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
		*.gz|*.tgz)  tar xzf "$1" ;;
		*) false ;;
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
		*'cpio archive'*)	  o='CPIO' ;;
	esac

	case "$testformat" in
		  '') echo "$o" ;;
		"$o") true ;;
		   *) false ;;
	esac
}

file_iscompressed()
{
	local file="$1"
	local line word parse=

	# of this 952040 byte file by 0 percent.
	line="$( ent "$file" | grep "percent."$ )"

	for word in $line; do {
		case "$parse" in
			true) break ;;
			*) test "$word" = "by" && parse='true' ;;
		esac
	} done

	test "${word:-99}" -lt 3
}

list_kernel_symbols()
{
	case "$DSTARCH" in
		armel|armhf)
			echo '# CONFIG_64BIT is not set'
		;;
		or1k|m68k)
		;;
		*)
			if has_arg '32bit'; then
				echo '# CONFIG_64BIT is not set'
			elif [ "$DSTARCH" = 'i686' ]; then
				echo '# CONFIG_64BIT is not set'
			else
				echo 'CONFIG_64BIT=y'

				# support for 32bit binaries
				# note: does not work/exist in uml: https://uml.devloop.org.uk/faq.html
				case "$DSTARCH" in
					uml|arm64) ;;
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

	has_arg 'wireguard' && {
		echo 'CONFIG_NET_FOU=y'
		echo 'CONFIG_CRYPTO=y'
		echo 'CONFIG_CRYPTO_MANAGER=y'
		echo 'CONFIG_WIREGUARD=y'
		echo 'CONFIG_WIREGUARD_DEBUG=y'
	}

	cat <<EOF
CONFIG_BLK_DEV_INITRD=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TTY=y
EOF

	if [ -f "$INITRD_FILE_PLAIN" ]; then
		echo "CONFIG_INITRAMFS_SOURCE=\"$INITRD_FILE_PLAIN\""
		echo 'CONFIG_INITRAMFS_COMPRESSION_NONE=y'
		echo '# CONFIG_RD_GZIP is not set'
		echo '# CONFIG_RD_BZIP2 is not set'
		echo '# CONFIG_RD_LZMA is not set'
		echo '# CONFIG_RD_XZ is not set'
		echo '# CONFIG_RD_LZO is not set'
		echo '# CONFIG_RD_LZ4 is not set'
		echo '# CONFIG_RD_ZSTD is not set'
	else
		echo "CONFIG_RD_$( initrd_format )=y"
		initrd_format GZIP  || echo '# CONFIG_RD_GZIP is not set'
		initrd_format BZIP2 || echo '# CONFIG_RD_BZIP2 is not set'
		initrd_format LZMA  || echo '# CONFIG_RD_LZMA is not set'
		initrd_format XZ    || echo '# CONFIG_RD_XZ is not set'
		initrd_format LZO   || echo '# CONFIG_RD_LZO is not set'
		initrd_format LZ4   || echo '# CONFIG_RD_LZ4 is not set'
		initrd_format ZSTD  || echo '# CONFIG_RD_ZSTD is not set'
	fi

	case "$DSTARCH" in
		i686)
			case "$MEM" in
				*G|[0-9][0-9][0-9][0-9]*)
					echo 'CONFIG_HIGHMEM=y'
					echo 'CONFIG_HIGHMEM4G=y'
				;;
			esac
		;;
	esac

	case "$DSTARCH" in
		i686|x86_64)
			# support 16bit or segmented code (e.g. DOSEMU)
			echo 'CONFIG_MODIFY_LDT_SYSCALL=y'
		;;
	esac

	case "$DSTARCH" in
		uml)
			echo 'CONFIG_STATIC_LINK=y'
		;;
		m68k)
#			echo 'CONFIG_VIRT=y'
#			echo 'CONFIG_MMU=y'
		;;
		arm64)
			echo 'CONFIG_SERIAL_AMBA_PL011=y'
			echo 'CONFIG_SERIAL_AMBA_PL011_CONSOLE=y'
		;;
		or1k)
			echo 'CONFIG_OPENRISC_BUILTIN_DTB="or1ksim"'
			echo 'CONFIG_SERIAL_8250=y'
			echo 'CONFIG_SERIAL_8250_CONSOLE=y'
			echo 'CONFIG_SERIAL_OF_PLATFORM=y'
			echo '# CONFIG_VT is not set'
			echo '# CONFIG_VT_CONSOLE is not set'
		;;
		*)
			echo 'CONFIG_SERIAL_8250=y'
			echo 'CONFIG_SERIAL_8250_CONSOLE=y'
		;;
	esac

	if [ "$DSTARCH" = 'or1k' ]; then
		:
	elif has_arg 'swap'; then
		echo 'CONFIG_SWAP=y'
	else
		echo '# CONFIG_SWAP is not set'
	fi

	if has_arg 'printk'; then
		echo 'CONFIG_PRINTK=y'

		case "$DSTARCH" in
			or1k|arm64) ;;
			*) echo 'CONFIG_EARLY_PRINTK=y' ;;
		esac
	else
		echo '# CONFIG_PRINTK is not set'
		echo '# CONFIG_EARLY_PRINTK is not set'	# n/a on arm64
	fi

	has_arg 'procfs' && echo 'CONFIG_PROC_FS=y'
	has_arg 'sysfs'  && echo 'CONFIG_SYSFS=y'

	has_arg 'debug' || {
		echo '# CONFIG_INPUT_MOUSE is not set'
		echo '# CONFIG_INPUT_MOUSEDEV is not set'
		echo '# CONFIG_INPUT_KEYBOARD is not set'
		echo '# CONFIG_HID is not set'
	}

	# FIXME! spaces are not working
	# we can overload CONFIG_SYMBOLS via ARGS
	for _ in $OPTIONS; do {
		case "$_" in
			CONFIG_*) echo "$_" ;;
		esac
	} done

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

[ -n "$CROSS_DL" ] && {
	export CROSSC="$OPT/cross-${DSTARCH:-native}"
	mkdir -p "$CROSSC"

	cd "$CROSSC" || exit
	download "$CROSS_DL" || exit
	untar ./* || exit
	cd ./* || exit

	export PATH="$PWD/bin:$PATH"
}

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
	untar ./* || exit
	cd ./* || exit
	./configure $SILENT_CONF --prefix="$MUSL" --disable-shared || exit
	make $SILENT_MAKE install || exit
	export CC_MUSL="$MUSL/bin/musl-gcc"

	download "$URL_DASH" || exit
	mv ./*dash* "$DASH_BUILD/" || exit
	cd "$DASH_BUILD" || exit
	untar ./* || exit
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

	untar ./* || exit
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
	command -v 'ip' >/dev/null && \\
	  ip link show dev eth0 && \\
	    printf '%s\\n' 'nameserver 8.8.4.4' >/etc/resolv.conf && \\
	      ip address add 10.0.2.15/24 dev eth0 && \\
	        ip link set dev eth0 up && \\
	          ip route add default via 10.0.2.2
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

[ -n "$ONEFILE" ] && {
	INITRD_FILE_PLAIN="$BUILDS/initramfs.cpio"
	gzip -cdk "$INITRD_FILE" >"$INITRD_FILE_PLAIN"
}

BB_FILE="$BUSYBOX_BUILD/busybox"
has_arg 'toybox' && BB_FILE="$BUSYBOX_BUILD/toybox"

###
### linux kernel ###
###

cd "$LINUX" || exit
download "$KERNEL_URL" || exit
untar ./* || exit
cd ./* || exit		# there is only 1 dir


# FIXME! autoadd to documentation
# Kernel PATCHES:
#
# GCC10 + kernel3.18 workaround:
# https://github.com/Tomoms/android_kernel_oppo_msm8974/commit/11647f99b4de6bc460e106e876f72fc7af3e54a6
F1="scripts/dtc/dtc-lexer.l"
F2="scripts/dtc/dtc-lexer.lex.c_shipped"
[ -f "$F1" ] && sed -i 's/^YYLTYPE yylloc;/extern &/' "$F1"
[ -f "$F2" ] && sed -i 's/^YYLTYPE yylloc;/extern &/' "$F2"
#
# or1k/openrisc/3.x workaround:
# https://opencores.org/forum/OpenRISC/0/5435
[ "$DSTARCH" = 'or1k' ] && F1='arch/openrisc/kernel/vmlinux.lds.S' && sed -i 's/elf32-or32/elf32-or1k/g' "$F1"


# kernel 2,3,4 but nut 5.x - FIXME!
# sed -i 's|-Wall -Wundef|& -fno-pie|' Makefile

T0="$( date +%s )"

# e.g.: gcc (Debian 10.2.1-6) 10.2.1 20210110
for WORD in $( gcc --version ); do {
	test 2>/dev/null "${WORD%%.*}" -gt 1 || continue
	VERSION="${WORD%%.*}"	# e.g. 10.2.1-6 -> 10

	# /home/bastian/software/minilinux/minilinux/opt/linux/linux-3.19.8/include/linux/compiler-gcc.h:106:1:
	# fatal error: linux/compiler-gcc9.h: file or directory not found
	[ -f "include/linux/compiler-gcc${VERSION}.h" ] || {
		[ -f 'include/linux/compiler-gcc5.h' ] && \
			cp -v include/linux/compiler-gcc5.h "include/linux/compiler-gcc${VERSION}.h"
	}

	break
} done

# or 'make mrproper' ?
make $SILENT_MAKE $ARCH O="$LINUX_BUILD" distclean || msg_and_die "$?" "make $ARCH O=$LINUX_BUILD distclean"	# needed?

emit_doc "make $ARCH $DEFCONFIG"
make $SILENT_MAKE $ARCH O="$LINUX_BUILD" $DEFCONFIG || {
	RC=$?
	make $ARCH help
	msg_and_die "$RC" "make $ARCH O=$LINUX_BUILD $DEFCONFIG"
}

if [ -f "$OWN_KCONFIG" ]; then
	:
	# kernel2.4:
	# make config or oldconfig (when .config provided)
	# make dep
	# make bzimage
else
	[ "$DEFCONFIG" = config ] && {
		make $SILENT_MAKE $ARCH O="$LINUX_BUILD" dep || msg_and_die "$?" "make $ARCH O=$LINUX_BUILD dep"
	}
fi

cd "$LINUX_BUILD" || exit

if [ -f "$OWN_KCONFIG" ]; then
	cp -v "$OWN_KCONFIG" .config
	yes "" | make $SILENT_MAKE $ARCH oldconfig || emit_doc "oldconfig failed"
else
	list_kernel_symbols | while read -r SYMBOL; do {
		apply "$SYMBOL" || emit_doc "error: $?"
	} done

	emit_doc "not-in-config \\/ maybe only in newer kernels?"
	list_kernel_symbols | while read -r SYMBOL; do {
		grep -q ^"$SYMBOL"$ .config || emit_doc "not-in-config | $SYMBOL"
	} done
fi

T1="$( date +%s )"
KERNEL_TIME_CONFIG=$(( T1 - T0 ))

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
	yes "" | make $SILENT_MAKE $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie -j"$CPU" || \
		msg_and_die "$?" "make $ARCH $CROSSCOMPILE CFLAGS=-fno-pie LDFLAGS=-no-pie"
	T1="$( date +%s )"
else
	T0="$( date +%s )"
	echo "make        $ARCH $CROSSCOMPILE -j$CPU"
	yes "" | make $SILENT_MAKE $ARCH $CROSSCOMPILE -j"$CPU" || msg_and_die "$?" "make $ARCH $CROSSCOMPILE"
	T1="$( date +%s )"
fi
KERNEL_TIME=$(( T1 - T0 ))

# FIXME! define it initially for every arch
# e.g. $LINUX_BUILD/arch/x86_64/boot/bzImage
# e.g. $LINUX_BUILD/arch/arm/boot/zImage
# e.g. $LINUX_BUILD/arch/arm64/boot/Image.gz
KERNEL_FILE="$( find "$LINUX_BUILD" -type f -name '*zImage' )"
[ -f "$KERNEL_FILE" ] || KERNEL_FILE="$LINUX_BUILD/arch/arm64/boot/Image"
[ -f "$KERNEL_FILE" ] || KERNEL_FILE="$LINUX_BUILD/vmlinux"	# e.g. uml

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
		KERNEL_ELF="$KERNEL_FILE"
		[ -f "$KERNEL_FILE.gz" ] && KERNEL_FILE="$KERNEL_FILE.gz"

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

			cd ./* || exit
			OK="$( ./run.sh | grep 'everything worked, see folder' )"
			SLIRP_BIN="$( echo "$OK" | cut -d"'" -f2 )"
			SLIRP_BIN="$( find "$SLIRP_BIN" -type f -name 'slirp.stripped' )"
		}
	;;
esac

# shellcheck disable=SC2046
set -- $( head -n3 "$CONFIG1" )
KERNEL_VERSION="${11}"

INITRD_TEMP="$( mktemp -d )" || exit
( cd "$INITRD_TEMP" && gzip -cd "$INITRD_FILE" | cpio -idm )
INITRD_FILES="$( find "$INITRD_TEMP" -type f | wc -l )"
INITRD_LINKS="$( find "$INITRD_TEMP" -type l | wc -l )"
INITRD_DIRS="$(  find "$INITRD_TEMP" -type d | wc -l )"
INITRD_BYTES="$( find "$INITRD_TEMP" -type f -exec cat {} \; | wc -c )"
rm -fR "$INITRD_TEMP"

gain()
{
	echo "scale=2; $1 * 100 / $2" | bc -l
}

B1="$(  wc -c <"$INITRD_FILE"  || echo 0 )"
B2="$(  wc -c <"$INITRD_FILE2" || echo 0 )"
B3="$(  wc -c <"$INITRD_FILE3" || echo 0 )"
B4="$(  wc -c <"$INITRD_FILE4" || echo 0 )"

P1="[$( gain "$B1" "$INITRD_BYTES" )%]"
P2="[$( gain "$B2" "$INITRD_BYTES" )%]"
P3="[$( gain "$B3" "$INITRD_BYTES" )%]"
P4="[$( gain "$B4" "$INITRD_BYTES" )%]"

# TODO: include build-instructions
cat >"$LINUX_BUILD/run.sh" <<!
#!/bin/sh

ACTION="\$1"		# autotest|boot
PATTERN="\$2"		# in autotest-mode pattern for end-detection
MAX="\${3:-86400}"	# max running time [seconds] in autotest-mode

[ -z "\$MEM" ] && MEM="${MEM:-256M}"	# if not given via ENV
[ -z "\$LOG" ] && LOG="${LOG:-/dev/null}"
[ -z "\$LOGTIME" ] && LOGTIME=true
[ -z "\$QEMU" ] && QEMU="${QEMU:-qemu-system-i386}"

# generated: $( date )
#
# ARCHITECTURE: ${DSTARCH:-default} / ${ARCH:-default}
# COMPILER: ${CROSSCOMPILE:-cc}
# CMDLINE_OPTIONS: $OPTIONS
#
# KERNEL_VERSION: $KERNEL_VERSION
# KERNEL_URL: $KERNEL_URL
# KERNEL_CONFIG: $CONFIG1
$( sed -n '1,5s/^/#                /p' "$CONFIG1" )
# KERNEL_CONFG_TIME: $KERNEL_TIME_CONFIG sec ("make $DEFCONFIG" +more)
# KERNEL_BUILD_TIME: $KERNEL_TIME sec
# KERNEL: $KERNEL_FILE
# KERNEL_ELF: $KERNEL_ELF
# KERNEL_SIZE: $( wc -c <"$KERNEL_FILE" ) bytes [is $( file_iscompressed "$KERNEL_FILE" || echo 'NOT ' )compressed]
# KERNEL_ELF: $(  wc -c <"$KERNEL_ELF" ) bytes
#   show sections with: readelf -S $KERNEL_ELF
#
# BUSYBOX: $BB_FILE
# BUSYBOX_SIZE: $( wc -c <"$BB_FILE" || echo 0 ) bytes
# BUSYBOX_CONFIG: $CONFIG2
#
# INITRD files......: $INITRD_FILES
#        symlinks...: $INITRD_LINKS
#        directories: $INITRD_DIRS
#        bytes......: $INITRD_BYTES [100%]
#
# INITRD:  $B1 bytes $P1 = $INITRD_FILE
# INITRD2: $B2 bytes $P2 = ${INITRD_FILE2:-<nofile>}
# INITRD3: $B3 bytes $P3 = ${INITRD_FILE3:-<nofile>}
# INITRD3: $B4 bytes $P4 = ${INITRD_FILE4:-<nofile>}
#   decompress: gzip -cd $INITRD_FILE | cpio -idm
#
# ---
$( cat "$LINUX_BUILD/doc.txt" )
# ---

KERNEL_ARGS='console=ttyS0'
[ -z "\$PATTERN" ] && PATTERN="<hopefully_this_pattern_will_never_match>"

grep -q svm /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
grep -q vmx /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
[ -n "\$KVM_SUPPORT" ] && test "\$( id -u )" -gt 0 && KVM_PRE="\$( command -v sudo )"

case "${DSTARCH:-\$( arch || echo native )}" in armel|armhf|arm|arm64)
	DTB='$DTB'
	KVM_SUPPORT="-M $BOARD \${DTB:+-dtb }\$DTB" ; KVM_PRE=; KERNEL_ARGS='console=ttyAMA0'
	[ "$DSTARCH" = arm64 ] && KVM_SUPPORT="\$KVM_SUPPORT -cpu max"
	;;
	m68k)
		KVM_SUPPORT="-M $BOARD"
		KVM_PRE=
	;;
	or1k)
		KVM_PRE=
		KVM_SUPPORT="-M $BOARD \${DTB:+-dtb }\$DTB -cpu or1200"
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
				initrd=$INITRD_FILE >"\$PIPE.out" 2>&1

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

{
	echo "# images generated using:"
	echo "# https://github.com/bittorf/kritis-linux"
	echo
	grep ^'#' "\$0"
	echo
	echo "# startup:"

	case "$DSTARCH" in
		uml)
			echo "$KERNEL_FILE mem=\$MEM \$UMLNET \\\\"
			echo "	initrd=$INITRD_FILE"
		;;
		*)
			echo "\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\\\"
			echo "	-kernel $KERNEL_FILE \\\\"
			echo "	-initrd $INITRD_FILE \\\\"
			echo "	-nographic \\\\"
			echo "	-append "\$KERNEL_ARGS" \$QEMU_OPTIONS"
		;;
	esac

	echo
} >"\$LOG"

(
	FIRSTLINE=true

	while read -r LINE; do {
		LENGTH="\${#LINE}"	# hacky: convert lineend x0D x0A -> x0A
		case "\$LENGTH" in
			0) UNIXLINE="%s" ;;
			*) UNIXLINE="%.\$((LENGTH-1))s"	;;
		esac

		case "\$FIRSTLINE" in true) FIRSTLINE= ; printf '\n' ;; esac

		case "\$LOGTIME" in
			true)
				# TODO: pipe to ts, e.g. foo | ts -i "%H:%M:%.S"
				DIFF="\$( date +%s )"
				DIFF=\$(( DIFF - T0 ))

				HOUR=\$(( DIFF / 3600 ))
				REST=\$(( DIFF - (HOUR*3600) ))
				MINU=\$(( REST / 60 ))
				REST=\$(( REST - (MINU * 60) ))

				# e.g. 01h45m23s | message_xy
				printf "%02d%s%02d%s%02d%s | \${UNIXLINE}\n" "\$HOUR" h "\$MINU" m "\$REST" s "\$LINE"
			;;
			*)
				printf '\${UNIXLINE}\n' "\$LINE"
			;;
		esac

		case "\$LINE" in
			'# BOOTTIME_SECONDS '*|'# UNAME '*)
				echo "\$LINE" >>"\$PIPE"
			;;
			"\$PATTERN"*|*' Attempted to kill init'*|'ABORTING HARD'*|'Bootstrapping completed.'*|'Aborted (core dumped)')
				echo 'READY' >>"\$PIPE"
				break
			;;
		esac
	} done <"\$PIPE.out" | tee -a "\$LOG"
) &

RC=1
[ -z "\$PATTERN" ] && RC=0
[ "\$PATTERN" = '<hopefully_this_pattern_will_never_match>' ] && RC=0

I=\$MAX
while [ \$I -gt 0 ]; do {
	kill -0 \$PID || break
	LINE="\$( tail -n1 "\$PIPE" )"

	case "\$LINE" in
		READY) RC=0 && break ;;		# TODO: more finegraned
		*) sleep 1; I=\$(( I - 1 )) ;;
	esac
} done

[ -s "\$LOG" ] && {
	{
		echo
		echo "# exit with RC:\$RC"
		echo "# see: $LINUX_BUILD/run.sh"
		echo "#"
		echo "# thanks for using:"
		echo "# https://github.com/bittorf/kritis-linux"
	} >>"\$LOG"

	LOGLINES="\$( wc -l <"\$LOG" )"
	LOGSIZE="\$(  wc -c <"\$LOG" )"
	LOGINFO="(\$LOGLINES lines, \$LOGSIZE bytes) "
}

echo
echo "# autotest-mode ready after \$(( MAX - I )) (out of max \$MAX) seconds"
echo "# RC:\$RC | PATTERN:\$PATTERN"
echo "# logile \${LOGINFO}written to:"
echo "# \$LOG"

FILENAME_OFFER='log_${GIT_USERNAME}_${GIT_REPONAME}_${GIT_BRANCH}_${GIT_SHORTHASH}_${DSTARCH}_kernel${KERNEL_VERSION}.txt'
echo "# proposed name: $( test "$GIT_SHORTHASH" && echo "upload: scp '\$LOG' \$FILENAME_OFFER" || echo 'none' )"

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
echo "# exit with RC:$RC"
echo "# see: $LINUX_BUILD/run.sh"
echo "#"
echo "# thanks for using:"
echo "# https://github.com/bittorf/kritis-linux"
echo

test $RC -eq 0
