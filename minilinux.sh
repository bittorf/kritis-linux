#!/bin/bash
# script runs on any POSIX shell, but has issues with 'dash 0.5.10.2-7' on ubuntu during 'init' concatenation

KERNEL="$1"		# e.g. 'latest' or 'stable' or '5.4.89' or '4.19.x' or URL-to-tarball
ARG2="$2"		# only used...
ARG3="$3"		# ...for smoketest
while shift; do
	export OPTIONS="$OPTIONS $1"	# see has_arg(), spaces are not working
done

BASEDIR="$PWD/minilinux${BUILID:+_}${BUILDID}"		# autoclean removes it later
UNIX0="$( date +%s )"

URL_TOYBOX='http://landley.net/toybox/downloads/toybox-0.8.4.tar.gz'
URL_BUSYBOX='https://busybox.net/downloads/busybox-1.33.0.tar.bz2'
URL_DASH='https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-0.5.11.3.tar.gz'
URL_WIREGUARD='https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-1.0.20200827.zip'
URL_BASH='http://git.savannah.gnu.org/cgit/bash.git/snapshot/bash-5.1.tar.gz'
URL_DROPBEAR='https://github.com/mkj/dropbear/archive/DROPBEAR_2020.81.tar.gz'
URL_SLIRP='https://github.com/bittorf/slirp-uml-and-compiler-friendly.git'
URL_IODINE='https://github.com/frekky/iodine/archive/master.zip'	# fork has 'configure' + crosscompile support
URL_ZLIB='https://github.com/madler/zlib/archive/v1.2.11.tar.gz'
URL_ICMPTUNNEL='https://github.com/DhavalKapil/icmptunnel/archive/master.zip'

log() { >&2 printf '%s\n' "$1"; }

export STRIP=strip
export LC_ALL=C
export STORAGE="/tmp/storage"
mkdir -p "$STORAGE" && log "[OK] cache/storage is here: '$STORAGE'"

# change from comma to space delimited list
OPTIONS="$OPTIONS $( echo "$FEATURES" | tr ',' ' ' )"

# needed for parallel build:
CPU="$( nproc || sysctl -n hw.ncpu || lsconf | grep -c 'proc[0-9]' )"
[ "${CPU:-0}" -lt 1 ] && CPU=1

has_arg()
{
	case " ${2:-$OPTIONS} " in *" $1 "*) true ;; *) false ;; esac
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

is_uml() { false; }
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
		# https://elinux.org/Flameman/mac68k
		export ARCH='ARCH=m68k' CROSSCOMPILE='CROSS_COMPILE=m68k-linux-gnu-'
		export BOARD='q800' DEFCONFIG='tinyconfig'
		export QEMU='qemu-system-m68k'
		install_dep 'gcc-m68k-linux-gnu'
		CROSS_DL='https://musl.cc/m68k-linux-musl-cross.tgz'
	;;
	ppc)	# 32bit
	;;
	ppc64)	# big endian
		# https://issues.guix.gnu.org/41669
	;;
	ppc64le)# IBM Power8/9 = "PowerISA 3.1" = powerpc64le
		:
	;;
	um*)	# http://uml.devloop.org.uk/kernels.html
		# https://unix.stackexchange.com/questions/90078/which-one-is-lighter-security-and-cpu-wise-lxc-versus-uml
		[ "$DSTARCH" = 'uml32' ] && OPTIONS="$OPTIONS 32bit"
		is_uml() { true; }

		export ARCH='ARCH=um'
		export DEFCONFIG='tinyconfig'
		export DSTARCH='uml'

		if has_arg '32bit'; then
			test "$(arch)" != i686 && \
#			export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-' && \
#			install_dep 'gcc-i686-linux-gnu'
			CROSS_DL="https://musl.cc/i686-linux-musl-cross.tgz"
			export CROSSCOMPILE='CROSS_COMPILE=i686-linux-musl-'
		else
			CROSS_DL="https://musl.cc/x86_64-linux-musl-cross.tgz"
			export CROSSCOMPILE='CROSS_COMPILE=x86_64-linux-musl-'
		fi
	;;
	i386|i486|i586|i686|x86|x86_32)
		DSTARCH='i686'		# 32bit
		OPTIONS="$OPTIONS 32bit"
		export DEFCONFIG='tinyconfig'
		export ARCH='ARCH=i386'
		export QEMU='qemu-system-i386'

		CROSS_DL="https://musl.cc/i686-linux-musl-cross.tgz"
		export CROSSCOMPILE='CROSS_COMPILE=i686-linux-musl-'

#		export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-'
#		install_dep 'gcc-i686-linux-gnu'
	;;
	x86_64|*)
		DSTARCH='x86_64'
		export DEFCONFIG='tinyconfig'
		export QEMU='qemu-system-x86_64'

		CROSS_DL="https://musl.cc/x86_64-linux-musl-cross.tgz"
		export CROSSCOMPILE='CROSS_COMPILE=x86_64-linux-musl-'
	;;
esac

has_arg 'tinyconfig'	&& DEFCONFIG='tinyconfig'	# supported since kernel 3.17-rc1
has_arg 'allnoconfig'	&& DEFCONFIG='allnoconfig'
has_arg 'defconfig'	&& DEFCONFIG='defconfig'
has_arg 'config'	&& DEFCONFIG='config'		# e.g. kernel 2.4.x

case "$DSTARCH" in
	uml*)
	;;
	or1k|m68k)
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
	# apt, bc, curl, dpkg, ent, logger, vimdiff, xz, zstd

	for cmd in $list; do {
		command -v "$cmd" >/dev/null || {
			printf '%s\n' "[ERROR] missing command: '$cmd' - please install"
			return 1
		}
	} done

	install_dep 'coreutils'
	install_dep 'build-essential'
	install_dep 'flex'
	install_dep 'bison'
	install_dep 'automake'
	install_dep 'ncurses-dev'	# for menuconfig

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
		latest|stable) wget -qO - https://www.kernel.org | grep -A1 "latest_link" | tail -n1 | cut -d'"' -f2 ;;
		 *) false ;;
	esac
}

download()
{
	local url="$1"
	local cache

	cache="$STORAGE/$( basename "$url" )"

	case "$url" in
		*master*)
			cache="$STORAGE/$( echo "$url" | sha256sum | cut -d' ' -f1 )-$( basename "$url" )"
		;;
	esac

	# e.g. during massively parallel run / release
	while [ -f "$cache-in_progress" ]; do {
		log "wait for disappear of '$cache-in_progress'"
		sleep 30
	} done

	if [ -s "$cache" ]; then
		log "[OK] download, using cache: '$cache' url: '$url'"
		cp "$cache" .
	else
		touch "$cache-in_progress"
		wget -O "$cache" "$url" || rm -f "$cache"
		rm "$cache-in_progress"
		cp "$cache" .
	fi
}

untar()		# and delete
{
	case "$1" in
		*.zip) unzip "$1" && rm "$1" ;;
		*.xz)  tar xJf "$1" && rm "$1" ;;
		*.bz2) tar xjf "$1" && rm "$1" ;;
		*.gz|*.tgz)  tar xzf "$1" && rm "$1" ;;
		*) false ;;
	esac
}

msg_and_die()
{
	local rc="$1"
	local txt="$2"
	local message="[ERROR] rc:$rc | pwd: $PWD | $txt"
	local log="${LOG:-/dev/null}"

	{
		emit_doc "$message"
		emit_doc 'all'
	} | tee "$log"

	echo >&2 "$message"

	exit "$rc"
}

autoclean_do()
{
	cd "$BASEDIR" && cd .. && rm -fR "$BASEDIR"
}

case "$KERNEL" in
	'smoketest'*)
		LIST_ARCH='armel  armhf  arm64  or1k  m68k  uml  uml32  x86  x86_64'
		LIST_KERNEL='3.18  3.18.140  3.19.8  4.0.9  4.1.52  4.2.8  4.3.6  4.4.258  4.9.258  4.14.222  4.19.177  5.4.101  5.10.19  5.11.2'

		FULL='printk procfs sysfs busybox bash dash net wireguard iodine icmptunnel dropbear speedup'
		TINY='printk'

		[ -n "$ARG2" ] && LIST_ARCH="$ARG2"
		[ -n "$ARG3" ] && LIST_KERNEL="$ARG3"
	;;
esac

case "$KERNEL" in
	'smoketest_for_release')
		avoid_overload() { sleep 30; while test "$(cut -d'.' -f1 /proc/loadavg)" -ge "$CPU"; do sleep 30; done; }
		UNIX0="$( date +%s )"

		for ARCH in $LIST_ARCH; do
		  for KERNEL in $LIST_KERNEL; do
		    I="${I}#"
		    ID="${KERNEL}_${ARCH}"
		    LOG="$PWD/log-$ID"
                    export FAKEID='kritis-release@github.com'
                    export NOKVM='true'

		    LOG="$LOG-tiny" BUILDID="$ID-tiny" DSTARCH="$ARCH" "$0" "$KERNEL" "$TINY" autoclean &
		    avoid_overload
		    LOG="$LOG-full" BUILDID="$ID-full" DSTARCH="$ARCH" "$0" "$KERNEL" "$FULL" autoclean &
		    avoid_overload
		  done
		done

		while [ "$( find . -type f -name 'log-*' | wc -l )" -lt $I ]; do sleep 5; done

		UNIX1="$( date +%s )"
		echo "needed $(( UNIX1 - UNIX0 )) sec"
		T0=$UNIX0 T1=$UNIX1 $0 'smoketest_report_html'
		exit
	;;
	'smoketest_report_html')
		build_matrix_html() {
			add_star() { STAR="${STAR}&lowast;"; }	# 8 chars long
			add_hint() { HINT="${HINT}$1
";}

			stars2color() {				# https://werner-zenk.de/tools/farbverlauf.php
				case "$(( ${#STAR} / 8 ))" in
					1) echo '#FFFFFF' ;;	# white
					2) echo '#D9FFD9' ;;
					3) echo '#AEFFAE' ;;
					4) echo '#84FF84' ;;
					5) echo '#59FF59' ;;
					6) echo '#00FF00' ;;	# lime = green
					*) echo 'crimson' ;;	# red
				esac
			}

			echo "<!DOCTYPE html>"
			echo "<html lang='en' dir='ltr'><head>"
			echo "<meta http-equiv='content-type' content='text/html; charset=UTF-8'>"
			echo "<title>MATRIX</title></head><body>"
			echo "<table cellspacing=1 cellpadding=1 border=1>"

			printf '%s' '<tr><th>&nbsp;</th>'
			for ARCH in $LIST_ARCH; do printf '%s' "<th>$ARCH</th>"; done
			printf '%s\n' "</tr><!-- end headline arch -->"

			for KERNEL in $LIST_KERNEL; do
			  RELEASE_DATE="$( download "http://intercity-vpn.de/kernel_history/$KERNEL" && read -r UNIX <"$KERNEL" && rm "$KERNEL" && LC_ALL=C date -d @$UNIX )"
			  printf '%s' "<tr><td title='release_date: ${RELEASE_DATE:-???}'>$KERNEL</td>"

			  for ARCH in $LIST_ARCH; do
			    I=$(( I + 1 ))
			    ID="${KERNEL}_${ARCH}"
			    L1="$PWD/log-$ID-tiny"	# e.g. log-5.4.100_x86_64-tiny
			    L2="$PWD/log-$ID-full"

			    HINT=
			    STAR=
			    grep -qs "BUILDTIME:" "$L1"			&& add_star && add_hint "tiny compiles: $L1"
			    grep -qs "Linux version $KERNEL" "$L1"	&& add_star && add_hint "tiny kernel boots"
			    grep -qs "BOOTTIME_SECONDS" "$L1"		&& add_star && add_hint "tiny initrd starts"
			    grep -qs "BUILDTIME:" "$L2"			&& add_star && add_hint "full compiles: $L2"
			    grep -qs "Linux version $KERNEL" "$L2"	&& add_star && add_hint "full kernel boots"
			    grep -qs "BOOTTIME_SECONDS" "$L2"		&& add_star && add_hint "full initrd starts"

			    printf '%s' "<td bgcolor='$( stars2color )' title='${HINT:-does_not_compile}'>${STAR:-&mdash;}</td>"
			  done
			  printf '%s\n' "</tr><!-- end line kernel $KERNEL -->"
			done

			echo "</table><pre>"
			echo "feature-set 'tiny' => $TINY"
			echo "feature-set 'full' => $FULL"
			echo
			echo '# we mark each progress step reached with an "asterisk"'
			echo '# step1: it compiles  (tiny featureset)'
			echo '# step2: kernel boots (tiny)'
			echo '# step3: initrd runs  (tiny)'
			echo '# step4: it compiles  (full featureset)'
			echo '# step5: kernel boots (full)'
			echo '# step6: initrd runs  (full)'
			echo
			echo "debug: build $(( I * 2 )) images in $(( T1 - T0 )) seconds = $(( (T1-T0) / (I*2) )) sec/image @ $( LC_ALL=C date )"
			echo "</pre></html>"
		}

		build_matrix_html >'matrix.html' && echo "see: '$PWD/matrix.html'"
		exit
	;;
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
	[0-9]|[0-9][0-9]|latest|stable)
		# e.g. 1 or 22 or 'latest' or 'stable'
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
	has_arg 'autoclean' && trap "autoclean_do" HUP INT QUIT TERM EXIT
}

export OPT="$PWD/opt"
mkdir -p "$OPT"

export BUILDS="$PWD/builds"
mkdir -p "$BUILDS"


export LINUX="$OPT/linux"
mkdir -p "$LINUX"

export LINUX_BUILD="$BUILDS/linux"
mkdir -p "$LINUX_BUILD"

# FAKEID: e.g. user@host.domain
mkdir -p "$OPT/fakeid"
printf  >"$OPT/fakeid/whoami"   '%s\n%s\n' '#!/bin/sh' "echo ${FAKEID%@*}"
printf  >"$OPT/fakeid/hostname" '%s\n%s\n' '#!/bin/sh' "echo ${FAKEID#*@}"
printf  >"$OPT/fakeid/uname"	'%s\n%s\n' '#!/bin/sh' "case \$1 in -n) echo \"${FAKEID#*@}\" ;; *) $( command -v uname ) \$1 ;; esac"
chmod +x "$OPT/fakeid/"*
[ -n "$FAKEID" ] && {
	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/scripts/mkcompile_h
	export HOSTNAME="${FAKEID#*@}" PATH="$OPT/fakeid:$PATH"
	export KBUILD_BUILD_USER="${FAKEID%@*}"
	export KBUILD_BUILD_HOST="${FAKEID#*@}"
	SCRIPTDIR="$( dirname "$( realpath "$0" )" )"
	KBUILD_BUILD_TIMESTAMP="$( cd "$SCRIPTDIR" && git rev-parse --short HEAD )"
	KBUILD_BUILD_VERSION="$(   cd "$SCRIPTDIR" && git show -s --format=%ci )"
	export SCRIPTDIR KBUILD_BUILD_TIMESTAMP KBUILD_BUILD_VERSION
}

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
	local option="$2"	# e.g. <empty> or 'info'
	local line word parse=
	local threshold=9

	# of this 952040 byte file by 0 percent.
	line="$( ent "$file" | grep "percent."$ )"

	for word in $line; do {
		case "$parse" in
			true) break ;;
			*) test "$word" = "by" && parse='true' ;;
		esac
	} done

	[ "$option" = 'info' ] && {
		if ! command -v 'ent' >/dev/null; then
			echo '? '
		elif test "${word:-99}" -lt $threshold; then
			echo 'really '
		else
			echo 'NOT '
		fi
	}

	# e.g. kernel 4.14.x bzImage: of this 724896 byte file by 8 percent.
	test "${word:-99}" -lt $threshold
}

checksum()			# e.g. checksum 'file' plain
{				#      checksum 'file' after plain || echo 'hash has changed'
	local file="$1"
	local name1="$2"	# e.g. 'plain' (aka 'untouched') OR 'after'
	local name2="$3"	# e.g. 'plain'
	local filehash

	if [ -f "$file" ]; then
		filehash="$( sha256sum "$file" | cut -d' ' -f1 )"
	else
		export STATE1=
		return 1
	fi

	if   [ -n "$name2" ]; then
		# compare two hashes
		test "$filehash" = "$STATE1"
	elif [ -n "$name1" ]; then
		# store state1 for later usage
		export STATE1="$filehash"
	fi
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
					uml*|arm64) ;;
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

		case "$DSTARCH" in
			uml*)
				echo 'CONFIG_UML_NET=y'
				echo 'CONFIG_UML_NET_SLIRP=y'
			;;
			m68k)
				echo 'CONFIG_ADB=y'
				echo 'CONFIG_ADB_MACII=y'
				echo 'CONFIG_MACSONIC=y'
			;;
			*)
				echo 'CONFIG_PCI=y'
				# echo 'CONFIG_E1000=y'		# lspci -nk will show attached driver
				echo 'CONFIG_8139CP=y'		# needs: -net nic,model=rtl8139 (but kernel is ~32k smaller)
			;;
		esac
	}

	has_arg 'iodine' && {
		echo 'CONFIG_TUN=y'
	}

	has_arg 'icmptunnel' && {
		echo 'CONFIG_TUN=y'
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
		uml*)
			# CONFIG_COMPAT_BRK=y	// disable head randomization ~500 bytes smaller
			# CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
			# CONFIG_BUILD_SALT="FOOX12345"

			has_arg 'hostfs' && echo 'CONFIG_HOSTFS=y'

			echo 'CONFIG_STATIC_LINK=y'
			echo 'CONFIG_LD_SCRIPT_STATIC=y'	# ???
		;;
		m68k)
			echo 'CONFIG_MAC=y'
			echo 'CONFIG_MMU=y'
			echo 'CONFIG_MMU_MOTOROLA=y'
			echo 'CONFIG_M68KCLASSIC=y'
			echo 'CONFIG_M68040=y'
			echo 'CONFIG_FPU=y'
			echo 'CONFIG_SERIAL_PMACZILOG=y'
			echo 'CONFIG_SERIAL_PMACZILOG_TTYS=y'
			echo 'CONFIG_SERIAL_PMACZILOG_CONSOLE=y'
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
		echo '# CONFIG_EARLY_PRINTK is not set'		# n/a on arm64
	fi

	has_arg 'procfs' && echo 'CONFIG_PROC_FS=y'
	has_arg 'sysfs'  && echo 'CONFIG_SYSFS=y'

	has_arg 'debug' || {
		echo '# CONFIG_INPUT_MOUSE is not set'
		echo '# CONFIG_INPUT_MOUSEDEV is not set'
		echo '# CONFIG_INPUT_KEYBOARD is not set'
		echo '# CONFIG_HID is not set'
	}

	has_arg 'speedup' && {
		echo 'CONFIG_BASE_FULL=y'
		echo 'CONFIG_COMPAT_BRK=y'	# disable head randomization ~500 bytes smaller
		echo 'CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y'
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
	local message="$1"	# e.g. <any> or 'all' or 'apply_order'
	local context file="$LINUX_BUILD/doc.txt"

	case "$message" in
		all)
			cat "$file"
			echo "see: '$file'"
			echo "     '$LINUX_BUILD/.config'"
		;;
		apply_order)
			# grep '| applied:' run.sh | grep '| linux' | cut -d: -f2 | grep -v '# CONFIG'
			grep 'applied' "$file"
			echo "# see: '$file'"
		;;
		*)
			context="$( basename "$( pwd )" )"	# e.g. busybox or linux

			echo >>"$file" "# doc | $context | $message"
		;;
	esac
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
			# e.g. '# CONFIG_INPUT_MOUSE is not set'
			# shellcheck disable=SC2086
			set -- $symbol

			emit_doc "DISABLE: $2 => $symbol"

			if   grep -q ^"$2=y"$ .config; then
				sed -i "/^$2=y/d" '.config' || msg_and_die "$?" "sed"
				echo "$symbol" >>.config
				emit_doc "delete symbol: $2=y | write symbol: $symbol"

				yes "" | make $SILENT_MAKE $ARCH oldconfig || emit_doc "failed: make $ARCH oldconfig"
			elif grep -q ^"$symbol"$ .config; then
				emit_doc "already set, no need to apply: $symbol"
				return 0
			else
				emit_doc "write unfound symbol: $symbol"
				echo "$symbol" >>'.config'
				yes "" | make $SILENT_MAKE $ARCH oldconfig || emit_doc "failed: make $ARCH oldconfig"
			fi

			if grep -q ^"$symbol"$ .config; then
				emit_doc "applied: $symbol"
			else
				emit_doc "symbol after make notfound: $symbol"
			fi

			return 0
		;;
	esac

	grep -q ^"$symbol"$ .config && {
		emit_doc "already set, no need to apply: $symbol"
		return 0
	}

	# TODO: work without -i
	if grep -q ^"$word=" .config; then
		emit_doc "symbol_inA: $word="
		sed -i "/^$word=.*/d" '.config'  || msg_and_die "$?" "sed"	# delete line e.g. 'CONFIG_PRINTK=y'
	else
		emit_doc "symbol_notinA: $word="
	fi

	if grep -q "$word " .config; then
		emit_doc "symbol_inB: ... $word ..."
		sed -i "/.*$word .*/d" '.config' || msg_and_die "$?" "sed"	# delete line e.g. '# CONFIG_PRINTK is not active'
	else
		emit_doc "symbol_notinB: ... $word ..."
	fi

	echo "$symbol" >>'.config'			# write line e.g.  'CONFIG_PRINTK=y'
	emit_doc "write symbol: $symbol"

	# see: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/scripts/config
	yes "" | make $SILENT_MAKE $ARCH oldconfig || {
		emit_doc "failed: make $ARCH oldconfig"
	}

	if grep -q ^"$symbol"$ .config; then
		emit_doc "applied: $symbol"
	else
		echo "#"
		echo "[ERROR] added symbol '$symbol' not found in file '.config' pwd '$PWD'"
		echo "#"

		emit_doc "symbol after make notfound: $symbol"
		false
	fi

	true	# FIXME!
}

###
### busybox|tyobox|dash + rootfs/initrd ####
###

install_dep 'build-essential'		# prepare for 'make'
DNS='8.8.4.4'

case "$DSTARCH" in
	uml*)
		# seems that musl-cc has issues:
		# https://www.openwall.com/lists/musl/2020/03/31/7
#		unset CROSSCOMPILE CC CXX STRIP CONF_HOST

		has_arg 'net' && {
			SLIRP_DIR="$( mktemp -d )" || msg_and_die "$?" "mktemp -d"
			cd "$SLIRP_DIR" || exit
			git clone --depth 1 "$URL_SLIRP"
			cd ./* || exit

			if has_arg 'quiet' "$EMBED_CMDLINE"; then
				OK="$( ./run.sh 'quiet' | tail -n1 )"
			else
				OK="$( ./run.sh         | tail -n1 )"
			fi

			# e.g. SLIRP_BIN='/tmp/tmp.BGbKLy2cly/slirp-1.0.17/src/slirp'
			echo "$OK" | grep -q ^'SLIRP_BIN=' || exit
			SLIRP_BIN="$( echo "$OK" | cut -d"=" -f2 | cut -d"'" -f2 )"
			$STRIP "$SLIRP_BIN" || exit
			DNS='10.0.2.3'
		}
	;;
esac

[ -n "$CROSS_DL" ] && {
	export CROSSC="$OPT/cross-${DSTARCH:-native}"
	mkdir -p "$CROSSC"

	cd "$CROSSC" || exit
	rm -fR ./*			# always cleanup
	download "$CROSS_DL" || exit
	untar ./* || exit
	cd ./* || exit

	 CC="$PWD/$( find bin/ -name '*-linux-musl-gcc'   )"
	CXX="$PWD/$( find bin/ -name '*-linux-musl-g++'   )"

	export CC CXX PATH="$PWD/bin:$PATH"
}

if [ -n "$CROSSCOMPILE" ]; then
	CONF_HOST="${CROSSCOMPILE#*=}"		# e.g. 'CROSS_COMPILE=i686-linux-gnu-'
	CHOST="${CONF_HOST%?}"			#                  -> i686-linux-gnu
	STRIP="${CHOST}-strip"			#                  -> i686-linux-gnu-strip
	CONF_HOST="--host=${CHOST}"

	CC_VERSION="$( $CHOST-gcc --version | head -n1 )"
	export STRIP CONF_HOST CHOST
else
	CC_VERSION="$( ${CC:-cc} --version | head -n1 )"
fi

export MUSL="$OPT/musl"
mkdir -p "$MUSL"

export MUSL_BUILD="$BUILDS/musl"
mkdir -p "$MUSL_BUILD"

has_arg 'dash' && {
	export DASH="$OPT/dash"
	mkdir -p "$DASH"

	export DASH_BUILD="$BUILDS/dash"
	mkdir -p "$DASH_BUILD"

	download "$URL_DASH" || exit
	mv ./*dash* "$DASH_BUILD/" || exit
	cd "$DASH_BUILD" || exit
	untar ./* || exit
	cd ./* || exit		# there is only 1 dir

	# TODO: --enable-glob --with-libedit --enable-fnmatch
	# https://github.com/amuramatsu/dash-static/blob/master/build.sh
	./autogen.sh || exit			# -> ./configure
	./configure $CONF_HOST $SILENT_CONF --enable-static || exit
	make $SILENT_MAKE $ARCH $CROSSCOMPILE "-j$CPU" || exit

	DASH="$PWD/src/dash"
	$STRIP "$DASH" || exit
}

compile()
{
	local package="$1"	# e.g. dropbear
	local url="$2"		# e.g. https://github.com/mkj/dropbear/archive/DROPBEAR_2020.81.tar.gz
	local file

	local build="$BUILDS/$package"
	local result="$OPT/$package"

	mkdir -p "$build" "$result"

	cd "$build" || exit
	rm -fR ./*		# always cleanup
	download "$url"
	for file in ./*; do break; done
	untar "$file"
	cd ./* || exit

	# generic prepare:
	[ -f 'configure.ac' ] && {
		# autoreconf --install ?
		autoconf
		autoheader
	}

	prepare		|| exit
	build		|| exit
	copy_result	|| exit
}

has_arg 'dropbear' && {
	prepare() {
		install_dep 'libtommath-dev'
		install_dep 'libtomcrypt-dev'
		install_dep 'dropbear-bin'	# only for key generation
		./configure --enable-static --disable-zlib $CONF_HOST
	}

	build() {
		local all='dropbear dbclient dropbearkey dropbearconvert scp'
		local ld_flags='-Wl,--gc-sections'
		local c_flags='-ffunction-sections -fdata-sections'

		test "$DSTARCH" = 'i686' && c_flags="$c_flags -DLTC_NO_BSWAP"

		LDFLAGS="$ld_flags" CFLAGS="$c_flags" make $SILENT_MAKE $ARCH $CROSSCOMPILE "-j$CPU" PROGRAMS="$all" MULTI=1 STATIC=1
	}

	copy_result() {
		$STRIP 'dropbearmulti'
		cp -v 'dropbearmulti' "$OPT/dropbear/"
	}

	install_dropbear() {
		cd bin && {
			cp -v "$OPT/dropbear/dropbearmulti" dropbear
			ln -s dropbear ssh
			ln -s dropbear scp
			ln -s dropbear usr/bin/dbclient
			ln -s dropbear dropbearkey

			cd - || exit

			mkdir -p .ssh
			dropbearkey -t rsa -f .ssh/id_dropbear || exit
		}
	}

	init_dropbear()
	{
		echo 'dropbear -B -R -p 22'
	}

	compile 'dropbear' "$URL_DROPBEAR"
}

# TODO: unify download + compile (dash, busybox, wireguard...)
has_arg 'wireguard' && {
	export WIREGUARD="$OPT/wireguard"
	mkdir -p "$WIREGUARD"

	export WIREGUARD_BUILD="$BUILDS/wireguard"
	mkdir -p "$WIREGUARD_BUILD"

	download "$URL_WIREGUARD" || exit
	mv ./*wireguard* "$WIREGUARD_BUILD/" || exit
	cd "$WIREGUARD_BUILD" || exit
	untar ./* || exit
	cd ./* || exit		# there is only 1 dir

	cd src || exit
	make "CC=$CC -static" "CPP=$CXX -static -E" $SILENT_MAKE $ARCH $CROSSCOMPILE "-j$CPU" || exit

	WIREGUARD="$PWD/wg"
	WIREGUARD2="$PWD/wg-quick/linux.bash"
	$STRIP "$WIREGUARD" || exit
}

has_arg 'bash' && {
	prepare() {
		./configure $CONF_HOST --without-bash-malloc
	}

	build() {
		# parallel builds unreliable:
		# https://lists.gnu.org/archive/html/bug-bash/2020-12/msg00001.html
		make $SILENT_MAKE $ARCH $CROSSCOMPILE || exit
	}

	copy_result() {
		$STRIP "$PWD/bash"
		cp -v "$PWD/bash" "$OPT/bash/"
	}

	install_bash() {
		cp -v "$OPT/bash/bash" bin/bash
	}

	compile 'bash' "$URL_BASH"
}

has_arg 'dummy' && {
	prepare() {
		:
	}

	build() {
		"CC=$CC -static" "CPP=$CXX -static -E" make $SILENT_MAKE $ARCH $CROSSCOMPILE "-j$CPU" || exit
	}

	copy_result() {
		$STRIP "$PWD/dummy.bin" || exit
		cp -v "$PWD/dummy.bin" "$OPT/dummy/dummy"
	}

	install_dummy() {
		:
	}

	compile 'dummy' "URL_DUMMY"
}

has_arg 'icmptunnel' && {
	prepare() {
		sed -i '/^CC=/d' Makefile
		sed -i '/^CFLAGS=/d' Makefile
	}

	build() {
		local cflags='-I. -O3 -Wall -ffunction-sections -fdata-sections -static'
		local ldflags='-Wl,--gc-sections'
		CFLAGS="$cflags" LDFLAGS="$ldflags" make 'icmptunnel' $SILENT_MAKE $ARCH $CROSSCOMPILE "-j$CPU" || exit
	}

	copy_result() {
		$STRIP icmptunnel || exit
		cp -v "$PWD/icmptunnel" "$OPT/icmptunnel/"
	}

	install_icmptunnel() {
		cp -v "$OPT/icmptunnel/icmptunnel" bin/icmptunnel
	}

	compile 'icmptunnel' "$URL_ICMPTUNNEL"
}

has_arg 'iodine' && {
	prepare() {
		local zlib_srcdir zlib_bindir file here="$PWD"

		zlib_srcdir="$( mktemp -d )" || exit	# TODO: make own zlib-package
		cd "$zlib_srcdir" || exit
		rm -fR ./*
		download "$URL_ZLIB"
		for file in ./*; do break; done
		untar "$file"
		rm "$file"
		cd ./* || exit
		#
		zlib_bindir="$( mktemp -d )" || exit
		#
		# does not work with $CONF_HOST, but CHOST is set
		./configure --prefix="$zlib_bindir" --static
		CFLAGS="-static" make $SILENT_MAKE $ARCH $CROSSCOMPILE || exit
		make install || exit

		cd "$here" || exit
		sed -i '/^AC_FUNC_MALLOC/d' configure.ac
		sed -i 's|alarm dup2|malloc &|' configure.ac	# work around issue: undefined reference to "rpl_malloc"
		autoreconf --install

		# this defines __GLIBC__ -> true
		CFLAGS="-D__GLIBC__=1 -I$zlib_bindir/include -static -lz" \
		LDFLAGS="-L$zlib_bindir/lib" ./configure $CONF_HOST || exit
	}

	build() {
		make $SILENT_MAKE $ARCH $CROSSCOMPILE all || exit
	}

	copy_result() {
		$STRIP "$PWD/iodine"			# also available: 'iodined'
		cp -v "$PWD/iodine" "$OPT/iodine/"
	}

	install_iodine() {				# FIXME +cleanup?
		cp -v "$OPT/iodine/iodine" bin/iodine
	}

	compile 'iodine' "$URL_IODINE"
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
	# busybox
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
	make $SILENT_MAKE $ARCH $CROSSCOMPILE "-j$CPU" || msg_and_die "$?" "make $ARCH $CROSSCOMPILE"
	make $SILENT_MAKE $ARCH $CROSSCOMPILE install  || msg_and_die "$?" "make $ARCH $CROSSCOMPILE install"
fi

cd ..

if [ -f "$OWN_INITRD" ]; then
	:
else
	export     INITRAMFS_BUILD="$BUILDS/initramfs"
	mkdir -p "$INITRAMFS_BUILD"
	cd       "$INITRAMFS_BUILD" || exit

	mkdir -p bin sbin etc proc sys usr/bin usr/sbin dev tmp
	has_arg 'hostfs' && mkdir -p mnt mnt/host
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

[ -s "$WIREGUARD" ] && {
	cp -v "$WIREGUARD" bin/wg
	cp -v "$WIREGUARD2" bin/wg-quick
}

[ -s "$DASH" ] && {
	rm -f bin/sh		# eventually from busybox
	cp -v "$DASH" bin/dash
	ln -s bin/sh bin/dash
}

has_arg 'dropbear' && install_dropbear

has_arg 'bash' && install_bash

has_arg 'iodine' && install_iodine

has_arg 'icmptunnel' && install_icmptunnel

[ -d "$INITRD_DIR_ADD" ] && {
	# FIXME! we do not include a spedicla directory named 'x'
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

export SALTFILE='bin/busybox'		# must be the path, here and in initrd
export BOOTSHELL='/bin/ash'
export INITSCRIPT="$PWD/init"

[ -f init ] || cat >'init' <<EOF
#!$BOOTSHELL
printf '%s\n' '#'	# init starts...
export SHELL=$( basename "$BOOTSHELL" )
$( has_arg 'procfs' || echo 'false ' )mount -t proc none /proc && {
	read -r UP _ </proc/uptime || UP=\$( cut -d' ' -f1 /proc/uptime )
	while read -r LINE; do
		# shellcheck disable=SC2086
		case "\$LINE" in MemAvailable:*) set -- \$LINE; MEMAVAIL_KB=\$2; break ;; esac
	done </proc/meminfo
}

$( has_arg 'sysfs' || echo 'false ' )mount -t sysfs none /sys
$( has_arg 'hostfs' || echo 'false ')mount -t hostfs none /mnt/host

# https://github.com/bittorf/slirp-uml-and-compiler-friendly
# https://github.com/lubomyr/bochs/blob/master/misc/slirp.conf
$( has_arg 'net' || echo 'false ' )command -v 'ip' >/dev/null && \\
  ip link show dev eth0 >/dev/null && \\
    printf '%s\\n' "nameserver $DNS" >/etc/resolv.conf && \\
      ip address add 10.0.2.15/24 dev eth0 && \\
	ip link set dev eth0 up && \\
	  ip route add default via 10.0.2.2

$( has_arg 'dropbear' && init_dropbear )
# wireguard and ssh startup
$(
	test -n "$TTYPASS" && {
		SHA256="$( { printf '%s' "$TTYPASS"; cat "$SALTFILE"; } | sha256sum )"
		printf '\n%s\n%s\n%s\n%s\n' \
			"# tty pass:" \
			"printf 'id: ' && read -s PASS" \
			"HASH=\"\$( { printf '%s' \"\$PASS\"; cat \"$SALTFILE\"; } | sha256sum )\"" \
			"test \"\${HASH%% *}\" = ${SHA256%% *} || exit"
	}
)

UNAME="\$( command -v uname || printf '%s' false )"
printf '%s\n' "# BOOTTIME_SECONDS \${UP:--1 (missing procfs?)}"
printf '%s\n' "# MEMFREE_KILOBYTES \${MEMAVAIL_KB:--1 (missing procfs?)}"
printf '%s\n' "# UNAME \$( \$UNAME -a || printf uname_unavailable )"
printf '%s\n' "# READY - to quit $( is_uml && echo "type 'exit'" || echo "press once CTRL+A and then 'x' or kill qemu" )"

# hack for MES:
test -f init.user && busybox sleep 2 && AUTO=true ./init.user	# wait for dmesg-trash

printf '%s\n' "mount -t devtmpfs none /dev"
if mount -t devtmpfs none /dev; then
	LN="\$( command -v ln || echo 'false ' )"
	$( has_arg 'procfs' || echo '	LN=false' )
	# http://www.linuxfromscratch.org/lfs/view/6.1/chapter06/devices.html
	\$LN -sf /proc/self/fd   /dev/fd
	\$LN -sf /proc/self/fd/0 /dev/stdin
	\$LN -sf /proc/self/fd/1 /dev/stdout
	\$LN -sf /proc/self/fd/2 /dev/stderr

	if command -v setsid; then
		# https://stackoverflow.com/a/35245823/5688306
		printf '%s\n' "job_control: exec setsid cttyhack $BOOTSHELL"
		exec setsid cttyhack $BOOTSHELL
	else
		printf '%s\n' "exec $BOOTSHELL"
		exec $BOOTSHELL 2>/dev/null
	fi
else
	printf '%s\n' "exec $BOOTSHELL"
	exec $BOOTSHELL 2>/dev/null
fi
EOF

chmod +x 'init'
sh -n 'init' || msg_and_die "$?" "check 'init'"

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
rm -fR ./*		# always cleanup
download "$KERNEL_URL" || exit
untar ./* || exit
cd ./* || exit		# there is only 1 dir

# Kernel PATCHES:
emit_doc "applied: kernel-patch | BEGIN"
#
# GCC10 + kernel3.18 workaround:
# https://github.com/Tomoms/android_kernel_oppo_msm8974/commit/11647f99b4de6bc460e106e876f72fc7af3e54a6
F1='scripts/dtc/dtc-lexer.l'		 && checksum "$F1" plain
[ -f "$F1" ] && sed -i 's/^YYLTYPE yylloc;/extern &/' "$F1"; checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1'"
F2='scripts/dtc/dtc-lexer.lex.c_shipped' && checksum "$F2" plain
[ -f "$F2" ] && sed -i 's/^YYLTYPE yylloc;/extern &/' "$F2"; checksum "$F2" after plain || emit_doc "applied: kernel-patch in '$PWD/$F2'"
#
# or1k/openrisc/3.x workaround:
# https://opencores.org/forum/OpenRISC/0/5435
[ "$DSTARCH" = 'or1k' ] && {
	F1='arch/openrisc/kernel/vmlinux.lds.S'  && checksum "$F1" plain
	sed -i 's/elf32-or32/elf32-or1k/g' "$F1" || exit
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$F1'"

	F2='arch/openrisc/boot/dts/or1ksim.dts'  && checksum "$F2" plain
	sed -i "s|\(^.*bootargs = .*\)|\1\n\t\tlinux,initrd-start = <0x82000000>;\n\t\tlinux,initrd-end = <0x82800000>;|" "$F2" || exit
	checksum "$F2" after plain || emit_doc "applied: kernel-patch, builtin DTB: '$F2'"
}
#
[ -n "$EMBED_CMDLINE" ] && is_uml && {
	# e.g. EMBED_CMDLINE="mem=72M initrd=/tmp/cpio.gz"
	F1='arch/um/kernel/um_arch.c'
	F2='arch/x86/um/os-Linux/task_size.c'
	EMBED_CMDLINE_FILE="$PWD/$F1"		# for later doc

	write_args()
	{
		local arg i=1
		local tab='	'

		printf '%s' "// this overrides the kernel commandline:\n"

		for arg in $EMBED_CMDLINE; do {
			printf '%s' "${tab}argv[$i] = \"$arg\";\n"
			i=$(( i + 1 ))
		} done

		printf '%s' "${tab}argc = $i;\n\n${tab}"
	}

	has_arg 'quiet' "$EMBED_CMDLINE" && {
		checksum "$F2" plain
		sed -i 's|^.*[^a-z]printf.*|//&|' "$F2" || exit
		checksum "$F2" after plain || emit_doc "applied: kernel-patch in '$PWD/$F2' | EMBED_CMDLINE: quiet"
	}

	checksum "$F1" plain
	sed -i "s|for (i = 1;|$( write_args )for (i = 1;|" "$F1" || exit
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | EMBED_CMDLINE: $EMBED_CMDLINE"
}
#
[ -n "$FAKEID" ] && {
	F="$( find . -type f -name 'mkcompile_h' )" && [ -f "$F" ] && checksum "$F" plain
	REPLACE="sed -i 's;#define LINUX_COMPILER .*;#define LINUX_COMPILER \"compiler/linker unset\";' .tmpcompile"
	sed -i "s|# Only replace the real|${REPLACE}\n\n# Only replace the real|" "$F" || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | FAKEID"
}
# http://lkml.iu.edu/hypermail/linux/kernel/1806.1/05149.html
F='arch/x86/um/shared/sysdep/ptrace_32.h'
[ -f "$F" ] && is_uml && {
	checksum "$F" plain
	LINE="$( grep -n '#define PTRACE_SYSEMU 31' $F | cut -d':' -f1 )"
	LINE=${LINE:-999999}	# does not harm
	sed -i "$((LINE-1)),$((LINE+1))d" $F || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | delete PTRACE_SYSEMU"

	checksum "$F" plain
	LINE="$( grep -n '#define PTRACE_SYSEMU_SINGLESTEP 32' $F | cut -d':' -f1 )"
	LINE=${LINE:-999999}	# does not harm
	sed -i "$((LINE-1)),$((LINE+1))d" $F || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | delete PTRACE_SYSEMU_SINGLESTEP"
}
# https://lore.kernel.org/patchwork/patch/630468/
F='arch/x86/um/Makefile' && checksum "$F" plain
sed -i "s|obj-\$(CONFIG_BINFMT_ELF) += elfcore.o|obj-\$(CONFIG_ELF_CORE) += elfcore.o|" "$F" || exit
checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | uml32? undefined reference to 'dump_emit'"
#
emit_doc "applied: kernel-patch | READY"

# kernel 2,3,4 but nut 5.x - FIXME!
# sed -i 's|-Wall -Wundef|& -fno-pie|' Makefile

T0="$( date +%s )"

# e.g.: gcc (Debian 10.2.1-6) 10.2.1 20210110
for WORD in $CC_VERSION; do {
	test 2>/dev/null "${WORD%%.*}" -gt 1 || continue
	VERSION="${WORD%%.*}"	# e.g. 10.2.1-6 -> 10
	DEST="include/linux/compiler-gcc${VERSION}.h"

	# /home/bastian/software/minilinux/minilinux/opt/linux/linux-3.19.8/include/linux/compiler-gcc.h:106:1:
	# fatal error: linux/compiler-gcc9.h: file or directory not found
	[ -f "$DEST" ] || {
		[ -f 'include/linux/compiler-gcc5.h' ] && \
			cp -v include/linux/compiler-gcc5.h "$DEST" && \
				emit_doc "applied: kernel-patch: include/linux/compiler-gcc5.h -> $DEST"
	}

	break
} done

# or 'make mrproper' ?
make $SILENT_MAKE $ARCH O="$LINUX_BUILD" distclean || msg_and_die "$?" "make $ARCH O=$LINUX_BUILD distclean"	# needed?

if make $SILENT_MAKE $ARCH O="$LINUX_BUILD" $DEFCONFIG; then
	emit_doc "applied: make $ARCH $DEFCONFIG"
else
	RC=$?
	make $ARCH help
	msg_and_die "$RC" "make $ARCH O=$LINUX_BUILD $DEFCONFIG"
fi

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
	yes "" | make $SILENT_MAKE $ARCH oldconfig || msg_and_die "$?" "oldconfig failed"
	emit_doc "applied: cp '$OWN_KCONFIG' .config && make $SILENT_MAKE $ARCH oldconfig"
else
#	# all-at-once:
#	list_kernel_symbols >>.config
#	yes "" | make $SILENT_MAKE $ARCH oldconfig

	# each symbol:
	list_kernel_symbols | while read -r SYMBOL; do {
		apply "$SYMBOL" || emit_doc "error: $?"
	} done

	# try again missing symbols, maybe it helps:
	list_kernel_symbols | while read -r SYMBOL; do {
		grep -q ^"$SYMBOL"$ .config || apply "$SYMBOL"
	} done

	# check still missing symbols
	emit_doc "not-in-config \\/ maybe only in newer kernels?"
	list_kernel_symbols | while read -r SYMBOL; do {
		grep -q ^"$SYMBOL"$ .config || emit_doc "not applied: $SYMBOL"
	} done
fi

T1="$( date +%s )"
KERNEL_TIME_CONFIG=$(( T1 - T0 ))

has_arg 'kmenuconfig' && {
	while :; do {
		make $SILENT_MAKE $ARCH menuconfig || exit
		vimdiff '.config' '.config.old'
		echo "$PWD" && echo "press enter for menuconfig or type 'ok' (and press enter) to compile" && \
			read -r GO && test "$GO" && break
	} done
}

CONFIG1="$PWD/.config"

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
		*'not stripped'*) $STRIP "$KERNEL_FILE" ;;
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

for WORD in $EMBED_CMDLINE; do {
	case "$WORD" in
		'initrd='*)
			cp -v "$INITRD_FILE" "${WORD#*=}"
		;;
		*'=slirp,'*)
			# eth0=slirp,FE:FD:01:02:03:04,/tmp/slirp.bin
			cp -v "$SLIRP_BIN" "${WORD##*,}" || exit
		;;
	esac
} done

# shellcheck disable=SC2046
set -- $(du -sh "$BASEDIR") && DISKSPACE="$1"


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
# BUILDTIME: $(( $( date +%s ) - UNIX0 )) sec
# DISKSPACE: $DISKSPACE
# ARCHITECTURE: ${DSTARCH:-default} / ${ARCH:-default}
# COMPILER: ${CROSSCOMPILE:-cc} | $CC_VERSION
# CMDLINE_OPTIONS: $OPTIONS
# $( test -n "$EMBED_CMDLINE" && echo "ENFORCED_KERNEL_CMDLINE: $EMBED_CMDLINE" )
# $( test -n "$EMBED_CMDLINE" && echo "FILE: $EMBED_CMDLINE_FILE" )
#
# KERNEL_VERSION: $KERNEL_VERSION
# KERNEL_URL: $KERNEL_URL
# KERNEL_CONFIG: $CONFIG1
$( sed -n '1,5s/^/#                /p' "$CONFIG1" )
# KERNEL_CONFG_TIME: $KERNEL_TIME_CONFIG sec ("make $DEFCONFIG" +more)
# KERNEL_BUILD_TIME: $KERNEL_TIME sec
# KERNEL: $KERNEL_FILE
# KERNEL_ELF: $KERNEL_ELF
# KERNEL_SIZE: $( wc -c <"$KERNEL_FILE" ) bytes [is $( file_iscompressed "$KERNEL_FILE" 'info' )compressed]
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
# init:    $INITSCRIPT  ($( wc -c <"$INITSCRIPT" || echo 0 ) bytes = '$BOOTSHELL' script)
# INITRD:  $B1 bytes $P1 = $INITRD_FILE
# INITRD2: $B2 bytes $P2 = ${INITRD_FILE2:-<nofile>}
# INITRD3: $B3 bytes $P3 = ${INITRD_FILE3:-<nofile>}
# INITRD3: $B4 bytes $P4 = ${INITRD_FILE4:-<nofile>}
#   decompress: gzip -cd $INITRD_FILE | cpio -idm
#
# ---
$( emit_doc 'apply_order' )
# ---

KERNEL_ARGS='console=ttyS0'
[ -z "\$PATTERN" ] && PATTERN="<hopefully_this_pattern_will_never_match>"

grep -q svm /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
grep -q vmx /proc/cpuinfo && KVM_SUPPORT='-enable-kvm -cpu host'
$( test -n "$NOKVM" && echo 'KVM_SUPPORT=' )
[ -n "\$KVM_SUPPORT" ] && test "\$( id -u )" -gt 0 && KVM_PRE="\$( command -v sudo )"

$( has_arg 'net' && echo "QEMU_OPTIONS='-net nic,model=rtl8139 -net user'" )

case "${DSTARCH:-\$( arch || echo native )}" in armel|armhf|arm|arm64)
	DTB='$DTB'
	KVM_SUPPORT="-M $BOARD \${DTB:+-dtb }\$DTB" ; KVM_PRE=; KERNEL_ARGS='console=ttyAMA0'
	[ "$DSTARCH" = arm64 ] && KVM_SUPPORT="\$KVM_SUPPORT -cpu max"
	;;
	m68k)
		KVM_SUPPORT="-M $BOARD"
		KVM_PRE=

		$( has_arg 'net' && echo "QEMU_OPTIONS='-net nic,model=dp83932 -net user'" )
	;;
	or1k)
		KVM_PRE=
		KVM_SUPPORT="-M $BOARD \${DTB:+-dtb }\$DTB -cpu or1200"
	;;
	uml*)
		QEMU="$( basename "$KERNEL_FILE" )"	# for later kill
		KVM_PRE=				# sudo unneeded?
	;;
esac

$( test -f "$BIOS" && echo "BIOS='-bios \"$BIOS\"'" )
$( has_arg 'net' && echo "KERNEL_ARGS=\"\$KERNEL_ARGS ip=dhcp nameserver=8.8.8.8\"" )
QEMU_OPTIONS=
$( test -x "$SLIRP_BIN" && echo "UMLNET='eth0=slirp,FE:FD:01:02:03:04,$SLIRP_BIN'" )

case "\$ACTION" in
	autotest)
	;;
	boot|'')
		set -x

		case "$DSTARCH" in
			uml*)
				echo "INTERACTIVE: will start now UML-linux:"
				echo

				DIR="\$( mktemp -d )" || exit
				export TMPDIR="\$DIR"

				if [ -n "$EMBED_CMDLINE" ]; then
					$KERNEL_FILE
				else
					$KERNEL_FILE mem=\$MEM \$UMLNET \\
						initrd=$INITRD_FILE
				fi

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
		uml*)
			echo "AUTOTEST for \$MAX sec: will start now UML-linux"
			echo

			DIR="\$( mktemp -d )" || exit
			export TMPDIR="\$DIR"

			if [ -n "$EMBED_CMDLINE" ]; then
				$KERNEL_FILE
			else
				$KERNEL_FILE mem=\$MEM \$UMLNET \\
					initrd=$INITRD_FILE >"\$PIPE.out" 2>&1
			fi

			rm -fR "\$DIR"
		;;
		*)
			PIDFILE="\$( mktemp -u )"
			echo "AUTOTEST for \$MAX sec: will start now QEMU: \$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT ..."
			echo

			# code must be duplicated, see below in LOG
			\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\
				-kernel $KERNEL_FILE \\
				-initrd $INITRD_FILE \\
				-nographic \\
				-serial pipe:\$PIPE \\
				-append "\$KERNEL_ARGS" \$QEMU_OPTIONS -pidfile "\$PIDFILE"
		;;
	esac
) &

T0="\$( date +%s )"

if [ -z "\$PIDFILE" ]; then
	PID=\$!
else
	for _ in 1 2 3 4 5; do read -r PID <"\$PIDFILE" && break; sleep 1; done
	test -n "\$PID" || PID="\$( pidof \$QEMU | head -n1 )"		# bad fallback
fi

{
	echo "# images generated using:"
	echo "# https://github.com/bittorf/kritis-linux"
	echo
	grep ^'#' "\$0"
	echo
	echo "# startup:"

	case "$DSTARCH" in
		uml*)
			echo "$KERNEL_FILE mem=\$MEM \$UMLNET \\\\"
			echo "	initrd=$INITRD_FILE"
		;;
		*)
			# code duplication from above real startup:
			echo "\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\\\"
			echo "	-kernel $KERNEL_FILE \\\\"
			echo "	-initrd $INITRD_FILE \\\\"
			echo "	-nographic \\\\"
			echo "	-append \"\$KERNEL_ARGS\" \$QEMU_OPTIONS -pidfile \"\$PIDFILE\""
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

FILENAME_OFFER='log_${GIT_USERNAME}_${GIT_REPONAME}_${GIT_BRANCH}_${GIT_SHORTHASH}_${DSTARCH}_kernel${KERNEL_VERSION}.txt'

[ -s "\$LOG" ] && {
	{
		echo
		echo "# exit with RC:\$RC"
		echo "# autotest-mode ready after \$(( MAX - I )) (out of max \$MAX) seconds"
		echo "# see: $LINUX_BUILD/run.sh"
		echo "#"
		echo "# logfile \${LOGINFO}written to:"
		echo "# \$LOG"
		echo "#"
		echo "# proposed name:"
		echo "# $( test "$GIT_SHORTHASH" && echo "\$FILENAME_OFFER" || echo '(none)' )"
		echo "#"
		echo "# thanks for using:"
		echo "# https://github.com/bittorf/kritis-linux"
	} >>"\$LOG"

	LOG_URL="\$( command -v 'curl' >/dev/null && test \$MAX -gt 5 && curl -F"file=@\$LOG" https://ttm.sh )"
	LOGLINES="\$( wc -l <"\$LOG" )"
	LOGSIZE="\$(  wc -c <"\$LOG" )"
	LOGINFO="(\$LOGLINES lines, \$LOGSIZE bytes) "
}

echo
echo "# autotest-mode ready after \$(( MAX - I )) (out of max \$MAX) seconds"
echo "# RC:\$RC | PATTERN:\$PATTERN"
echo "# logfile \${LOGINFO}written to:"
echo "# \$LOG"
echo "#"
echo "# proposed name:"
echo "# $( test "$GIT_SHORTHASH" && echo "\$FILENAME_OFFER" || echo '(none)' )"
echo "# uploaded to: $( test "\$LOG_URL" && echo "\$LOG_URL" || echo '(none)')"
echo "#"
echo "# you can manually startup again:"
echo "# \$0"
echo "# in dir '\$(pwd)'"
echo

echo "will now stop '\$QEMU' with pid \$PID" && \$KVM_PRE echo
while \$KVM_PRE kill -0 \$PID; do \$KVM_PRE kill \$PID; sleep 1; \$KVM_PRE kill -s KILL \$PID; done
rm -f "\$PIPE" "\$PIPE.in" "\$PIPE.out" "\$PIDFILE"

test \$RC -eq 0
!

ABORT_PATTERN='# READY'
[ -f "$OWN_INITRD" ] && ABORT_PATTERN=

chmod +x "$LINUX_BUILD/run.sh" && \
	 "$LINUX_BUILD/run.sh" 'autotest' "$ABORT_PATTERN" 20
RC=$?

echo
echo "# exit with RC:$RC"
echo "# see: $LINUX_BUILD/run.sh"
echo "#"
echo "# thanks for using:"
echo "# https://github.com/bittorf/kritis-linux"
echo

exit $RC
