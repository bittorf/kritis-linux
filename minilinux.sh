#!/bin/sh

KERNEL="$1"		# e.g. 'latest' or 'stable' or '5.4.89' or '4.19.x' or URL-to-tarball
ARG2="$2"		# only used...
ARG3="$3"		# ...for smoketest

for TAG in "$@"; do
	case "$TAG" in
		verbose) set -x ;;
		*) export OPTIONS="$OPTIONS $TAG" ;;	# see has_arg(), spaces are not working
	esac
done

BASEDIR="$PWD/minilinux${BUILID:+_}${BUILDID}"		# autoclean removes it later
WGETOPTS='--no-check-certificate'			# TODO: use hashes instead?
UNIX0="$( date +%s )"

URL_TOYBOX='http://landley.net/toybox/downloads/toybox-0.8.4.tar.gz'
URL_BUSYBOX='https://busybox.net/downloads/busybox-1.32.0.tar.bz2'
URL_BUSYBOX='https://busybox.net/downloads/busybox-snapshot.tar.bz2'
URL_DASH='https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-0.5.11.3.tar.gz'
URL_WIREGUARD='https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-1.0.20200827.zip'
URL_BASH='http://git.savannah.gnu.org/cgit/bash.git/snapshot/bash-5.1.tar.gz'
URL_DROPBEAR='https://github.com/mkj/dropbear/archive/DROPBEAR_2020.81.tar.gz'
URL_SLIRP='https://github.com/bittorf/slirp-uml-and-compiler-friendly.git'
URL_IODINE='https://github.com/frekky/iodine/archive/master.zip'	# fork has 'configure' + crosscompile support
URL_ZLIB='https://github.com/madler/zlib/archive/v1.2.11.tar.gz'
URL_ICMPTUNNEL='https://github.com/DhavalKapil/icmptunnel/archive/master.zip'

log() { >&2 printf '%s\n' "$1"; }

export LC_ALL=C
export STORAGE="/tmp/storage"
mkdir -p "$STORAGE" && log "[OK] cache/storage is here: '$STORAGE'"

# needed for parallel build:
NPROC="$( nproc || sysctl -n hw.ncpu || lsconf | grep -c 'proc[0-9]' )"
[ -z "$CPU" ] && CPU="$NPROC"
[ "${CPU:-0}" -lt 1 ] && CPU=1
[ "$CPU" = 1 ] && DEBUG=true
log "[OK] parallel build with -j$CPU"

# change from comma to space delimited list
OPTIONS="$OPTIONS $( echo "$FEATURES" | tr ',' ' ' ) $( test -n "$DEBUG" && echo 'debug' )"

has_arg()
{
	local wish="$1"			# e.g. 'printk' or 'iodine:credentials'
	local string="${2:-$OPTIONS}"
	local sub

	case " $string " in
		*" $wish "*) true ;;
		*" ${wish%:*}:${wish#*:}:"*)	# e.g. 'iodine:credentials:'
			for sub in $string; do
				case "$sub" in
					"$wish"*)
						# shellcheck disable=SC2046
						set -- $( echo "$sub" | tr ':' ' ' )

						# iodine:credentials:foo:bar:baz
						export PARAM1="$3"	# foo
						export PARAM2="$4"	# bar
						export PARAM3="$5"	# baz
						return 0
					;;
				esac
			done

			false
		;;
		*)
			# e.g. has_arg '*defconfig' and given 'foo_defconfig'
			# shellcheck disable=SC2254
			for sub in $string; do
				case "$sub" in
					$wish)
						export THIS_ARG="$sub"
						return 0
					;;
				esac
			done

			false
		;;
	esac
}

emit_doc()
{
	local message="$1"	# e.g. <any> or 'all' or 'apply_order'
	local context file="${LINUX_BUILD:-.}/doc.txt"

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

install_dep()
{
	local package="$1"	# e.g. gcc-i686-linux-gnu
	local option="$2"	# e.g. <empty> or 'weak'
	local rc

	dpkg -L "$package" >/dev/null || {
		echo "[OK] need to install package '$package'"

		[ -n "$APT_UPDATE" ] || {
			if sudo apt-get update; then
				APT_UPDATE='true'
			else
				log "rc:$? sudo apt-get update | but trying to go further"
			fi
		}

		# Need to get 235 kB of archives.
		# After this operation, 563 kB of additional disk space will be used.
		# WARNING: The following packages cannot be authenticated!
		#   libfl-dev flex
		# E: There are problems and -y was used without --force-yes

		sudo apt-get install --force-yes -y "$package" || {
			rc=$?

			if [ "$option" = 'weak' ]; then
				log "rc:$rc sudo apt-get install --force-yes -y $package"
				false
			else
				msg_and_die "$rc" "sudo apt-get install --force-yes -y $package"
			fi
		}
	}
}

is_uml() { false; }
DSTARCH_CMDLINE="$DSTARCH"

for MARCH in armel armhf arm64 or1k m68k uml uml32 x86 x86_64; do has_arg "$MARCH" && DSTARCH="$MARCH"; done

case "$DSTARCH" in
	armel)	# FIXME! on arm / qemu-system-arm / we should switch to qemu -M virt without DTB and smaller config
		# see: https://github.com/landley/aboriginal/blob/master/sources/targets/armv5l
		# old ARM, 32bit - from aboriginal linux target armv5l:
		#
		# "ARM v5, little endian, EABI with vector floating point (vfp).
		#  ARMv5 is the Pentium of the ARM world.  Most modern arm hardware should be
		#  able to run this, and hardware that supports the v5 instruction set should run
		#  this about 25% faster than code compiled for v4."
		#
		export ARCH='ARCH=arm' QEMU='qemu-system-arm'
		export BOARD='versatilepb' DTB='versatile-pb.dtb' DEFCONFIG='versatile_defconfig'
		# install_dep 'gcc-arm-linux-gnueabi' && export CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabi-'
		CROSS_DL='https://musl.cc/armel-linux-musleabi-cross.tgz'
		# https://github.com/zerotier/ZeroTierOne/blob/master/make-linux.mk#L278
		export CF_ADD='-marm -march=armv5te -mfloat-abi=soft -msoft-float -mno-unaligned-access'
	;;
	armhf)	# https://superuser.com/questions/1009540/difference-between-arm64-armel-and-armhf
		# https://wiki.musl-libc.org/getting-started.html#Notes-on-ARM-Float-Mode
		# https://landley.net/notes-2017.html#04-05-2017
		# arm7 / 32bit with power / EABI hard float
		export ARCH='ARCH=arm' QEMU='qemu-system-arm'	# https://github.com/oreboot/oreboot
		# FIXME! qemu-system-arm -machine virt -bios target/arm-none-eabihf/release//oreboot.bin -nographic -m 1024M
		export BOARD='vexpress-a9' DTB='vexpress-v2p-ca9.dtb' DEFCONFIG='vexpress_defconfig'
		# install_dep 'gcc-arm-linux-gnueabihf' && export CROSSCOMPILE='CROSS_COMPILE=arm-linux-gnueabihf-'
		CROSS_DL='https://musl.cc/armv7l-linux-musleabihf-cross.tgz'
		# https://wiki.alpinelinux.org/wiki/Custom_Kernel
		export CF_ADD="-marm -march=armv7-a -mfpu=vfp"
	;;
	arm64)	# new ARM, 64bit
		# https://github.com/ssrg-vt/hermitux/wiki/Aarch64-support
		export ARCH='ARCH=arm64' QEMU='qemu-system-aarch64'
		export BOARD='virt' DEFCONFIG='tinyconfig'
		# install_dep 'gcc-aarch64-linux-gnu' && export CROSSCOMPILE='CROSS_COMPILE=aarch64-linux-gnu-'
		CROSS_DL='https://musl.cc/aarch64-linux-musl-cross.tgz'
	;;
	or1k)	# OpenRISC, 32bit
		# https://wiki.qemu.org/Documentation/Platforms/OpenRISC
		export ARCH='ARCH=openrisc' QEMU='qemu-system-or1k'
		export BOARD='or1k-sim' DEFCONFIG='tinyconfig'
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
		export ARCH='ARCH=m68k' QEMU='qemu-system-m68k'
		export BOARD='q800' DEFCONFIG='tinyconfig'
		# install_dep 'gcc-m68k-linux-gnu' && export CROSSCOMPILE='CROSS_COMPILE=m68k-linux-gnu-'
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

		if has_arg '32bit'; then
			export DSTARCH='uml32'
			# install_dep 'gcc-i686-linux-gnu' && export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-'
			CROSS_DL="https://musl.cc/i686-linux-musl-cross.tgz"	# test "$(arch)" != i686 ???
		else
			export DSTARCH='uml'
			CROSS_DL="https://musl.cc/x86_64-linux-musl-cross.tgz"
		fi
	;;
	i386|i486|i586|i686|x86|x86_32)
		DSTARCH='i686'		# 32bit
		OPTIONS="$OPTIONS 32bit"
		export DEFCONFIG='tinyconfig' QEMU='qemu-system-i386'
		export ARCH='ARCH=i386'

		if [ "$QEMUCPU" = 486 ]; then
			CROSS_DL="https://musl.cc/i486-linux-musl-cross.tgz"
		else
			# install_dep 'gcc-i686-linux-gnu' && export CROSSCOMPILE='CROSS_COMPILE=i686-linux-gnu-'
			CROSS_DL="https://musl.cc/i686-linux-musl-cross.tgz"
		fi
	;;
	x86_64|*)
		DSTARCH='x86_64'
		# export ARCH='ARCH=x86_64'		# TODO: keep native arch?
		export DEFCONFIG='tinyconfig'
		export QEMU='qemu-system-x86_64'
		CROSS_DL="https://musl.cc/x86_64-linux-musl-cross.tgz"

		has_arg 'zig' && CROSS_DL='https://ziglang.org/builds/zig-linux-x86_64-0.8.0-dev.1548+0d96a284e.tar.xz'
	;;
esac

has_arg 'tinyconfig'	&& DEFCONFIG='tinyconfig'	# supported since kernel 3.17-rc1
has_arg 'allnoconfig'	&& DEFCONFIG='allnoconfig'
has_arg 'defconfig'	&& DEFCONFIG='defconfig'
has_arg 'config'	&& DEFCONFIG='config'		# e.g. kernel 2.4.x
has_arg '*defconfig'	&& DEFCONFIG="$THIS_ARG"	# e.g. mvme16x_defconfig

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

if has_arg 'debug'; then
	SILENT_MAKE='V=s'
else
	SILENT_MAKE='-s'
	SILENT_CONF='--enable-silent-rules'
fi

STRIP="$( command -v 'strip' || echo 'false' )"

log "[OK] building kernel '$KERNEL' on arch '$DSTARCH' and options '$OPTIONS'"

deps_check()
{
	local cmd list

	install_dep 'coreutils'		# e.g. stdbuf
	install_dep 'build-essential'
	install_dep 'flex'
	install_dep 'bison'
	install_dep 'automake'
	install_dep 'whois'

	# FIXME! 'program_name' not always 'package_name',
	# e.g. 'mkpasswd' is in package 'whois'

	# essential:
	list='arch base64 basename cat chmod cp file find grep gzip head make mkdir rm sed'
	list="$list strip tar tee test touch tr wget mkpasswd"

	# these commands are used, but are not essential:
	# apt, bc, curl, dpkg, ent, hexdump, hunspell, sstrip, upx, vimdiff, xz, zstd, xxd

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
		23) echo 'https://mirrors.edge.kernel.org/pub/linux/kernel/v2.4/linux-2.4.26.tar.xz' ;;
		latest|stable) wget $WGETOPTS -qO - https://www.kernel.org | grep -A1 "latest_link" | tail -n1 | cut -d'"' -f2 ;;
		 *) false ;;
	esac
}

string_hash()
{
	echo "$1" | sha256sum | cut -d' ' -f1
}

download()
{
	local url="$1"
	local dest="${2:-.}"
	local cache

	cache="$STORAGE/$( string_hash "$url" )-$( basename "$url" )"

	# e.g. during massively parallel run / release
	while [ -f "$cache-in_progress" ]; do {
		log "wait for disappear of '$cache-in_progress'"
		sleep 30
	} done

	if [ -s "$cache" ]; then
		log "[OK] download, using cache: '$cache' url: '$url'"
		cp "$cache" $dest
	else
		touch "$cache-in_progress"
		wget $WGETOPTS -O "$cache" "$url" || rm -f "$cache"
		rm "$cache-in_progress"
		cp "$cache" $dest
	fi
}

untar()		# and delete
{
	local file="$1"
	local mime

	mime="$( file --brief --mime "$file" )"

	case "$mime" in
		application/zip*)       unzip "$1" && rm "$1" ;;
		application/x-lzma*)  tar xJf "$1" && rm "$1" ;;
		application/x-xz*)    tar xJf "$1" && rm "$1" ;;
		application/x-bzip2*) tar xjf "$1" && rm "$1" ;;
		application/gzip*)    tar xzf "$1" && rm "$1" ;;
		application/x-gzip*)  tar xzf "$1" && rm "$1" ;;
		*)
			log "untar() file '$file' unknown mime-type: $mime"
			false
		;;
	esac
}

autoclean_do()
{
	cd "$BASEDIR" && cd .. && rm -fR "$BASEDIR"

	{
		printf '\n%s\n' "[OK] autoclean done, build ready after $(( $(date +%s) - UNIX0 )) sec"
		printf '%s\n%s\n' "repeat with:" "CPU=$CPU DEBUG=true $0 smoketest_for_release $DSTARCH_CMDLINE $KERNEL"
	} >>"${LOG:-/dev/null}"
}

makedir_gointo_and_cleanup()
{
	local dir="$1"

	mkdir -p "$dir"	|| exit 1
	cd "$dir"	|| exit 1
	rm -fR ./*	|| exit 1	# always cleanup
}

humanreadable_lines()
{
	local file="$1"
	local minlength="${2:-3}"

	local line word lang lang_list=
	local file_dict2 file_dict3 url_dict2

	# maybe use: /usr/share/dict/words
	file_dict2="$( mktemp )"
	file_dict3="$( mktemp )"
	url_dict2="https://users.cs.duke.edu/~ola/ap/linuxwords"
	download "$url_dict2" "$file_dict2"

	sed 's/[^a-zA-Z]/ /g' "$file" | while read -r line; do {
		for word in $line; do {
			case "${#word}" in
				1|2) ;;
				*) printf '%s\n' "$word" ;;
			esac
		} done
	} done >"$file_dict3"

	install_dep 'hunspell'

	for lang in $( find /usr/share/hunspell/ -type f -iname '*.dic' | sed -n 's|^.*/\(.*\).dic|\1|p' | sort ); do {
		case "$lang" in
			en*|de*|es*|ro*)
				lang_list="${lang_list}${lang_list:+,}$lang"
			;;
		esac
	} done

	log "[OK] lang_list: $lang_list"

	words() {
		# apt-get install myspell-fr myspell-es hunspell-en-* hunspell-de-at hunspell-de-ch hunspell-de-de hunspell-de-med
		hunspell -G -d $lang_list -l "$file_dict3" | sed -r "/^.{,$minlength}$/d" | while read -r word; do {
			printf '%s ' "$word"
		} done
	}
	log "[OK] words: $( words )"

	count() {
		hunspell -G -d $lang_list -l "$file_dict3" | sed -r "/^.{,$minlength}$/d" | wc -l
	}

	log "[OK] word count: $( count )"

	# strip spaces/tabs and non-printable (ascii-subset) and show only lines >6 chars
#	tr -cd '\11\12\15\40-\176' <"$file" | sed "s/[[:space:]]\+//g" | sed -r "/^.{,$minlength}$/d" | wc -l
#	sed 's/[^a-zA-Z0-9 ]//g' "$file" | grep --text -F -f "$file_dict1" | sed 's/[^a-zA-Z0-9 ]//g' | sed -r "/^.{,$minlength}$/d" | wc -l

	rm "$file_dict2" "$file_dict3"
}

case "$KERNEL" in
	'humanreadable_lines'|'hl')
		humanreadable_lines "$ARG2" "$ARG3"
		exit $?
	;;
	'smoketest'*)
		LIST_ARCH='armel  armhf  arm64  or1k  m68k  uml  uml32  x86  x86_64'
		LIST_KERNEL='3.18 3.18.140 3.19.8 4.0.9 4.1.52 4.2.8 4.3.6 4.4.261 4.9.261 4.14.225 4.19.180 5.4.105 5.10.23 5.11.6'

		FULL='printk procfs sysfs busybox bash dash net wireguard iodine icmptunnel dropbear speedup'
		TINY='printk busybox'

		[ -n "$ARG2" ] && LIST_ARCH="$ARG2"		# enforce building a subset
		[ -n "$ARG3" ] && LIST_KERNEL="$ARG3"
	;;
esac

case "$KERNEL" in
	'smoketest_for_release')
		load_integer() { local load rest; read -r load rest </proc/loadavg; printf '%s\n' "${load%.*}"; }
		avoid_overload() { sleep 10; while test "$(load_integer)" -gt "$NPROC"; do sleep 10; done; }

		touch 'SMOKE'
		test -z "$ARG2" && \
		(while [ -f SMOKE ];do J=;L=$(load_integer);for _ in $(seq "$L");do J="#$J";done;echo $J ${#J};sleep 10;done >load.txt;) &

		for ARCH in $LIST_ARCH; do
		  for KERNEL in $LIST_KERNEL; do
		    I=$(( I + 2 ))
		    ID="${KERNEL}_${ARCH}"
		    L1="$PWD/log-$ID-tiny.txt" && rm -f "$L1"
		    L2="$PWD/log-$ID-full.txt" && rm -f "$L2"
		    B1="$L1.build.txt"
		    B2="$L2.build.txt"
                    export FAKEID='kritis-release@github.com'
                    export NOKVM='true' ONEFILE='true'
		    export CPU

		    if [ -n "$ARG2" ]; then
		      LOG="$L1" BUILDID="$ID-tiny" DSTARCH="$ARCH" "$0" "$KERNEL" "$TINY" autoclean >"$B1" 2>&1
		      LOG="$L2" BUILDID="$ID-full" DSTARCH="$ARCH" "$0" "$KERNEL" "$FULL" autoclean >"$B2" 2>&1
		    else
		      LOG="$L1" BUILDID="$ID-tiny" DSTARCH="$ARCH" "$0" "$KERNEL" "$TINY" autoclean >"$B1" 2>&1 &
		      avoid_overload
		      LOG="$L2" BUILDID="$ID-full" DSTARCH="$ARCH" "$0" "$KERNEL" "$FULL" autoclean >"$B2" 2>&1 &
		      avoid_overload
		    fi
		  done
		done

		count_logfiles() { find . -maxdepth 1 -type f -name 'log-[1-9]\.*' -size +0 -exec grep 'autoclean done' {} \; | wc -l; }
		while C=$( count_logfiles ); test $C -lt $I; do {
			test -f 'SMOKE' || break
			log "waiting for $C/$I logfiles or '$PWD/SMOKE' disappear"
			sleep 10
		} done

		rm 'SMOKE'
		$0 'smoketest_report_html'
		log "see '$PWD/load.txt"
		exit
	;;
	'smoketest_report_html')
		build_matrix_html() {
			I=0
			add_star() { STAR="${STAR}&lowast;"; }	# 8 chars long
			add_hint() { HINT="${HINT}$1
";}

			stars2color() {				# https://werner-zenk.de/tools/farbverlauf.php
				test -n "$1" && echo 'lightblue' && return	# panic

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

			COMMIT="$( git rev-parse --short HEAD )"
			LINK="https://github.com/bittorf/kritis-linux/commit/$COMMIT"
			printf '%s' "<tr><th><a href='$LINK'>github</a></th>"

			for ARCH in $LIST_ARCH; do printf '%s' "<th>$ARCH</th>"; done
			printf '%s\n' "</tr><!-- end headline arch -->"

			for KERNEL in $LIST_KERNEL; do
			  RELEASE_DATE="$( download "http://intercity-vpn.de/kernel_history/$KERNEL" && read -r UNIX <"$KERNEL" && rm "$KERNEL" && LC_ALL=C date -d "@$UNIX" )"
			  printf '%s' "<tr><td title='release_date: ${RELEASE_DATE:-???}'>$KERNEL</td>"

			  for ARCH in $LIST_ARCH; do
			    I=$(( I + 2 ))
			    ID="${KERNEL}_${ARCH}"
			    L1="$PWD/log-$ID-tiny.txt"	# e.g. log-5.4.100_x86_64-tiny.txt
			    L2="$PWD/log-$ID-full.txt"
			    B1="$L1.build.txt"
			    B2="$L2.build.txt"

			    HINT=
			    PANIC=
			    STAR=
			    grep -qs "BUILDTIME:" "$L1"			&& add_star && add_hint "tiny compiles: $L1"
			    grep -qs "Linux version $KERNEL" "$L1"	&& add_star && add_hint "tiny kernel boots"
			    grep -qs "BOOTTIME_SECONDS" "$L1"		&& add_star && add_hint "tiny initrd starts"
			    grep -qs "Attempted to kill init" "$L1"	&& PANIC=1  && add_hint "tiny kernel panics"

			    LINK1="<a href='$( basename "$L1" )'>$STAR</a>"
			    [ -z "$STAR" ] && LINK1="<a href='$( basename "$B1" )'>&mdash;</a>&nbsp;&nbsp;"
			    STAR_OLD="$STAR"

			    STAR=
			    grep -qs "BUILDTIME:" "$L2"			&& add_star && add_hint "full compiles: $L2"
			    grep -qs "Linux version $KERNEL" "$L2"	&& add_star && add_hint "full kernel boots"
			    grep -qs "BOOTTIME_SECONDS" "$L2"		&& add_star && add_hint "full initrd starts"
			    grep -qs "Attempted to kill init" "$L2"	&& PANIC=2  && add_hint "full kernel panics"

			    LINK2="<a href='$( basename "$L2" )'>$STAR</a>"
			    [ -z "$STAR" ] && LINK2="<a href='$( basename "$B2" )'>&mdash;</a>&nbsp;&nbsp;"

			    STAR="${STAR_OLD}${STAR}"
			    printf '%s' "<td bgcolor='$( stars2color "$PANIC" )' title='${HINT:-does_not_compile}'>${LINK1}&nbsp;$LINK2</td>"
			  done
			  printf '%s\n' "</tr><!-- end line kernel $KERNEL -->"
			done

			echo "</table>"

			[ "$1" = 'only_table' ] && echo '</html>' && return

			echo "<pre>"
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

			# 10 seconds for each line:
			T="$( wc -l <load.txt || echo 0 )" && T=$(( T * 10 ))

			echo "debug: build $I images in $T seconds = $(( T / I )) sec/image @ $( LC_ALL=C date )"
			echo "uname: $( uname -a )"

			# shellcheck disable=SC2046,SC2048
			echo "nproc/cpu: $NPROC @ $( set -- $( grep ^"model name" /proc/cpuinfo | head -n1 ); shift 3; echo "$*" )"
			echo "$( test -f load.txt && printf '\n%s' 'load-1min during build each 10 sec:' && cat load.txt )</pre>"
			echo "<br><pre># generated with: $0 smoketest_report_html</pre></html>"
		}

		DEST="user@server.de:/var/www/kritis-linux/"
		build_matrix_html >'table.html' only_table
		build_matrix_html >'index.html' && log "see: '$PWD/index.html', scp ./*.html log-* $DEST"

		read -r USER_DEST <'autoupload.txt'
		[ -n "$USER_DEST" ] && scp ./*.html "$USER_DEST"
		[ -z "$NOUPLOAD" ] && [ -n "$USER_DEST" ] && scp log-* "$USER_DEST"
		[ -z "$NO_IMAGE" ] && [ -n "$USER_DEST" ] && {
			makedir_gointo_and_cleanup 'browsershots'

			download "https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-2.1.1-linux-x86_64.tar.bz2" || exit
			untar ./* || exit
			cd ./* || exit

			HARDCODED_URL="http://intercity-vpn.de/kritis-linux/table.html"		# ugly!

			{
				echo "var page = require('webpage').create();"
				echo "page.open('$HARDCODED_URL', function() {"
				echo " setTimeout(function() {"
				echo "  page.render('preview.png');"
				echo "  phantom.exit();"
				echo " }, 200);"
				echo "});"
			} >script.js

			bin/phantomjs script.js && scp preview.png "$USER_DEST"
		}

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
				KERNEL="$( wget $WGETOPTS -qO - https://www.kernel.org | sed -n "s/.*<strong>\(${KERNEL}[0-9]*\)<.*/\1/p" )"
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

makedir_gointo_and_cleanup "$BASEDIR"
has_arg 'autoclean' && trap "autoclean_do" HUP INT QUIT TERM EXIT

if [ -d "$BUILD_DIR" ]; then
	export OPT="$BUILD_DIR/opt"
	export BUILDS="$BUILD_DIR/builds"
else
	export OPT="$PWD/opt"
	export BUILDS="$PWD/builds"
fi

makedir_gointo_and_cleanup "$OPT"
makedir_gointo_and_cleanup "$BUILDS"

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

	# used compression via:
	# grep -i CONFIG_HAVE_KERNEL_ + CONFIG_KERNEL_ .config

	# FIXME! try to really detect compression:
	# https://gist.githubusercontent.com/skitt/288c0c52b51b5863947a5d6c1180c9f3/raw/25f571a2361305cbcff71f56f57d546e9ff68172/check-vmlinux
	# https://github.com/bittorf/kalua/blob/master/openwrt-addons/etc/kalua/filetype

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
			if   [ "$DSTARCH" = 'i686' ]; then
				[ "$QEMUCPU" = 486 ] && echo 'CONFIG_M486=y'
				echo '# CONFIG_64BIT is not set'
			elif has_arg '32bit'; then
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
		# https://unix.stackexchange.com/questions/171874/no-network-interface-in-qemu
		# grep 8139cp /proc/ioports
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
				has_arg '*defconfig' || {
					echo 'CONFIG_ADB=y'
					echo 'CONFIG_ADB_MACII=y'
					echo 'CONFIG_MACSONIC=y'
				}
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
		echo 'CONFIG_POSIX_TIMERS=y'
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

	if [ -e "$INITRD_OBJECT_PLAIN" ]; then
		# https://landley.net/writing/rootfs-howto.html
		# can be a 'cpio' or 'cpio.gz'-file or a 'directory':
		echo "CONFIG_INITRAMFS_SOURCE=\"$INITRD_OBJECT_PLAIN ${INITRD_OBJECT_PLAIN}$( test -d "$INITRD_OBJECT_PLAIN" && echo '/' )essential.txt\""
		echo 'CONFIG_INITRAMFS_COMPRESSION_NONE=y'
#		echo 'CONFIG_INITRAMFS_ROOT_UID=squash'		# FIXME!
#		echo 'CONFIG_INITRAMFS_ROOT_GID=squash'		# FIXME!

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
					# e.g. 3.5G or 500M
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
			# CONFIG_BUILD_SALT="FOOX12345"
			echo 'CONFIG_UNIX98_PTYS=y'
			echo 'CONFIG_PTY_CHAN=y'
			echo 'CONFIG_TTY_CHAN=y'
			echo 'CONFIG_MULTIUSER=y' 	# for dropbear?

			has_arg 'hostfs' && echo 'CONFIG_HOSTFS=y'

			echo 'CONFIG_STATIC_LINK=y'
			echo 'CONFIG_LD_SCRIPT_STATIC=y'	# builds with 'uml.lds.S', see 'arch/um/kernel/vmlinux.lds.S'
		;;
		m68k)
			has_arg '*defconfig' || {
				echo 'CONFIG_MAC=y'
				echo 'CONFIG_MMU=y'
				echo 'CONFIG_MMU_MOTOROLA=y'
				echo 'CONFIG_M68KCLASSIC=y'
				echo 'CONFIG_M68040=y'
				echo 'CONFIG_FPU=y'
				echo 'CONFIG_SERIAL_PMACZILOG=y'
				echo 'CONFIG_SERIAL_PMACZILOG_TTYS=y'
				echo 'CONFIG_SERIAL_PMACZILOG_CONSOLE=y'
			}
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
		echo 'CONFIG_FUTEX=y'
	}

	has_arg 'kexec' && echo 'CONFIG_KEXEC=y'	# +20k uncompressed on x84_64

	# enforce kernel compression mode?:
	# CONFIG_HAVE_KERNEL_XZ=y
	# CONFIG_KERNEL_XZ=y

	# FIXME! spaces are not working
	# we can overload CONFIG_SYMBOLS via ARGS
	for _ in $OPTIONS; do {
		case "$_" in
			CONFIG_*) echo "$_" ;;
		esac
	} done

	true
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

random_hex()
{
	local start=11			# matching chars below/including 10 = 0xa seems hard, so avoid these
	local end=255
	local seed diff random

	seed="$( hexdump -n 2 -e '/2 "%u"' /dev/urandom )"
	diff=$(( end + 1 - start ))
	test $diff -eq 0 && diff=1
	random=$(( seed % diff ))

	# e.g. 00..ff
	printf '%02x\n' "$(( start + random ))"
}

elfcrunch_file()
{
	local file="$1"

	local hex1 hex2 hex3 string1 string2 new1 new2 size1 size2 pos1 pos2
	local url1="https://github.com/BR903/ELFkickers.git"
	local url2="https://github.com/upx/upx/releases"

	# TODO: --ultra-brute | see: https://github.com/upx/upx/issues/385
	sstrip        "$file"	|| msg_and_die "$?" "failed: sstrip $file | see: $url1"
	upx -v --lzma "$file"	|| msg_and_die "$?" "failed: upx -v --lzma $file | see: $url2"

	# obfuscate strings, e.g. 'UPX!'
	has_arg 'obfus*' || return 0

	size1="$( wc -c <"$file" )"

	hex1="$( random_hex )"
	hex2="$( random_hex )"
	hex3="$( random_hex )"
	sed -i "s/\x55\x50\x58\x21/\x${hex1}\x${hex2}\x${hex3}\x21/g" "$file"
	sed -i "s|failed|_o/\\\o_|" "$file"

	# obfuscate these/similar strings:
	# $Info: This file is packed with the UPX executable packer http://upx.sf.net $
	# $Id: UPX 3.96 Copyright (C) 1996-2020 the UPX Team. All Rights Reserved. $
	string1="$( grep --text ' UPX ' "$file" | head -n1 )"
	string2="$( grep --text ' UPX ' "$file" | tail -n1 )"

	generate_random_string()
	{
		local length="$1"
		local i=0

		while [ $i -lt $length ]; do
			printf '%s' "\x$( random_hex )"
			i=$(( i + 1 ))
		done
	}

	string_to_hex()
	{
		# foobar -> \x66\x6f\x6f\x62\x61\x72
		printf '%s' "$1" | xxd -p -c1 | while read -r HEX; do
			# https://lists.gnu.org/archive/html/bug-sed/2021-03/msg00001.html
			# precede any of $*.[\]^ => 24 2a 2e 5b 5c 5d 5e with \x5c
			case "$HEX" in 24|2a|2e|5b|5c|5d|5e) HEX="5c\\x$HEX" ;; esac

			printf '\\x%s' "$HEX"
		done
	}

	new1="$( generate_random_string ${#string1} )"		# e.g. \x65\x66
	new2="$( generate_random_string ${#string2} )"

	string1="$( string_to_hex "$string1" )"			# e.g. \x67\x68
	string2="$( string_to_hex "$string2" )"

	pos1="$( sed -rn "0,/$string1/ {s/^(.*)$string1.*$/\1/p ;t exit; p; :exit }" "$file" | wc -c )"
	pos2="$( sed -rn "0,/$string2/ {s/^(.*)$string2.*$/\1/p ;t exit; p; :exit }" "$file" | wc -c )"
	log "[OK] byte-position-match1: $pos1"
	log "[OK] byte-position-match2: $pos2"

	sed -i "s/$string1/$new1/g" "$file" || exit
	sed -i "s/$string2/$new2/g" "$file" || exit

	size2="$( wc -c <"$file" )"

	if   [ "$size1" != "$size2" ]; then
		msg_and_die "$?" "obfuscation failed, filesize changed '$file' before/after: $size1/$size2"
	elif grep --text 'UPX!' "$file"; then
		msg_and_die "$?" "obfuscation failed, found string 'UPX!' in '$file'"
	else
		humanreadable_lines "$file"
		true
	fi
}

###
### busybox|tyobox|dash + rootfs/initrd ####
###

install_dep 'build-essential'		# prepare for 'make'
DNS='8.8.4.4'


is_uml && has_arg 'net' && {
	# slirp is special, because it runs on the host, so we
	# must in theory compile it for the host-arch, not for the image-arch
	# FIXME! i has problems with musl, so for now avoid that
	# without ppp it builds/upx to 80K with musl, but does not really work
	# in contrast to GCC, it compiles/upx to 470K on x86_84 (but works)

	SLIRP_DIR="$( mktemp -d )" || msg_and_die "$?" "mktemp -d"
	cd "$SLIRP_DIR" || exit
	git clone --depth 1 "$URL_SLIRP"
	cd ./* || exit

	if has_arg 'quiet' "$EMBED_CMDLINE"; then
		OK="$( MYCC=static ./run.sh 'quiet' | tail -n1 )"
	else
		OK="$( MYCC=static ./run.sh         | tail -n1 )"
	fi

	# e.g. SLIRP_BIN='/tmp/tmp.BGbKLy2cly/slirp-1.0.17/src/slirp'
	echo "$OK" | grep -q ^'SLIRP_BIN=' || exit
	SLIRP_BIN="$( echo "$OK" | cut -d"=" -f2 | cut -d"'" -f2 )"

	if has_arg 'upx'; then
		elfcrunch_file "$SLIRP_BIN" || exit
	else
		$STRIP "$SLIRP_BIN" || exit
	fi

	DNS='10.0.2.3'
}

[ -n "$CROSS_DL" ] && {
	CROSSC="$OPT/cross-${DSTARCH:-native}-$( string_hash "$CROSS_DL" )"
	makedir_gointo_and_cleanup "$CROSSC"
	download "$CROSS_DL" || exit
	untar ./* || exit
	cd ./* || exit

	if [ -f "$PWD/zig" ]; then
		export CC="$PWD/zig cc"
	else
		# FIXME! this hardcodes musl-things:
		# e.g. cross-armhf/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc
		# e.g.       cross-or1k/or1k-linux-musl-cross/bin/or1k-linux-musl-gcc
		 CC="$PWD/$( find bin/ -type f -name '*-linux-musl*-gcc'   )"
		CXX="$PWD/$( find bin/ -type f -name '*-linux-musl*-g++'   )"

		test -f  "$CC" || msg_and_die "$?" "CC  not a file: '$CC'  dir: '$PWD/bin'"
		test -f "$CXX" || msg_and_die "$?" "CXX not a file: '$CXX' dir: '$PWD/bin'"

		# e.g.                      CC=or1k-linux-musl-gcc
		# we need later: CROSS_COMPILE=or1k-linux-musl-'
		#                              ^^^^^^^^^^^^^^^^
		PRE="$( basename "${CC%-*}" )"		# remove trailing 'gcc'
		export CROSSCOMPILE="CROSS_COMPILE=$PRE-"
		export CC CXX PATH="$PWD/bin:$PATH"
	fi
}

if [ -n "$CROSSCOMPILE" ]; then
	# https://www.gnu.org/software/autoconf/manual/autoconf-2.65/html_node/Specifying-Target-Triplets.html
	CONF_HOST="${CROSSCOMPILE#*=}"		# e.g. 'CROSS_COMPILE=i686-linux-gnu-'
	CHOST="${CONF_HOST%?}"			#                  -> i686-linux-gnu
	STRIP="${CHOST}-strip"			#                  -> i686-linux-gnu-strip
	CONF_HOST="--host=${CHOST}"		# TODO: configure: WARNING: if you wanted to set the --build type, don't use --host.
						#       If a cross compiler is detected then cross compile mode will be used

	CC_VERSION="$( "$CHOST-gcc" --version | head -n1 )"
	export STRIP CONF_HOST CHOST
else
	export STRIP='strip'
	CC_VERSION="$( ${CC:-cc} --version | head -n1 )"
fi

log "CROSSCOMPILE: $CROSSCOMPILE | vCC: $CC_VERSION | CC: $CC | CXX: $CXX"

export MUSL="$OPT/musl"
mkdir -p "$MUSL"

export MUSL_BUILD="$BUILDS/musl"
mkdir -p "$MUSL_BUILD"

export CRONTAB="$OPT/crontab.txt"


cronjob_add()
{
	local context="$1"
	local line="$2"

	test -f "$CRONTAB" || printf '%s\n\n' 'PATH="/sbin:/usr/sbin:/bin:/usr/bin"' >"$CRONTAB"
	echo "$line" >>"$CRONTAB"
}

compile()
{
	local package="$1"	# e.g. mytool_xy
	local url="$2"		# e.g. https://domain.tld/path/to/tool.tgz
	local file

	local build="$BUILDS/$package"
	local result="$OPT/$package"

	makedir_gointo_and_cleanup "$result"
	makedir_gointo_and_cleanup "$build"
	download "$url"
	for file in ./*; do break; done
	untar "$file"
	cd ./* || exit

	# generic prepare, used by: dropbear, bash(broken)
	[ -f 'configure.ac' ] && {
		[ -f 'configure' ] || {
			# https://www.gnu.org/software/autoconf/manual/autoconf-2.68/html_node/autoreconf-Invocation.html
			autoreconf --force --install || msg_and_die "$?" "compile() error during 'autoreconf -f -i' for '$package'"
		}
	}

	prepare		|| msg_and_die "$?" "compile() error during prepare()"
	build		|| msg_and_die "$?" "compile() error during build()"
	copy_result	|| msg_and_die "$?" "compile() error during copy_result()"
}

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

has_arg 'dropbear' && {
	prepare() {
		[ -f /usr/include/crypt.h ] || install_dep 'libcrypt-dev'
		install_dep 'libtommath-dev'
		install_dep 'libtomcrypt-dev'
		install_dep 'dropbear-bin' weak	# only for key generation during build: dropbearkey

		CFLAGS="-ffunction-sections -fdata-sections $( test "$DSTARCH" = 'i686' && echo "-DLTC_NO_BSWAP" )" \
		LDFLAGS='-Wl,--gc-sections' ./configure \
			--disable-zlib --enable-bundled-libtom --disable-wtmp --enable-static $CONF_HOST
	}

	build() {
		local all='dropbear dbclient dropbearkey scp dropbearconvert'

		make $SILENT_MAKE $ARCH $CROSSCOMPILE PROGRAMS="$all" MULTI=1 SCPPROGRESS=1
	}

	copy_result() {
		$STRIP 'dropbearmulti'
		cp -v 'dropbearmulti' "$OPT/dropbear/"
	}

	install_dropbear() {
		local key_ecdsa='etc/dropbear/dropbear_ecdsa_host_key'
		local key_rsa='etc/dropbear/dropbear_rsa_host_key'

		mkdir -p usr usr/bin etc etc/dropbear .ssh	|| exit

		cd bin && {
			cp -v "$OPT/dropbear/dropbearmulti" dropbear	|| exit
			ln -s dropbear ssh				|| exit
			ln -s dropbear scp				|| exit
#			ln -s dropbear ../usr/bin/dbclient		|| exit
			ln -s dropbear dropbearkey			|| exit

			cd - || exit
		}

		# only newer versions understand 'ecdsa'
		if dropbearkey -t ecdsa -f "$key_ecdsa"; then
			dropbearkey -t ecdsa -f "$key_ecdsa"	|| exit
			dropbearkey -t rsa   -f "$key_rsa"	|| exit
		else
			printf '%s\n%s\n%s\n' \
				'AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKlmAMA3qxEe8UgUTnuI' \
				'7VTdT15cha1dhpkZhhniLzNsqsn0SRs9UoHSMJ0S7CuKJtGR2uUEcu+R+JsDEgg0DQcAAAAg' \
				'GwwAoC40kwthP+sG4jNVipi8pcVGBuo7xE76lE+CWEg=' | base64 -d >"$key_ecdsa"
		fi

		local hint=" on host '\$( cat /mnt/host/etc/hostname )', see /mnt/host/ and /proc/cpuinfo"
		has_arg 'hostfs' || hint=

		printf	'%s\n\n%s\n%s\n' \
			'#!/bin/sh' \
			'export PATH="/sbin:/usr/sbin:/bin:/usr/bin"' \
			"echo \"welcome on $DSTARCH-vm$hint\"" \
			>'etc/profile'
		chmod +x 'etc/profile'
	}

	init_dropbear()
	{
		# -R = Create hostkeys as required
		# -p = port
		# debug:
		# -B = Allow blank password logins
		# -E = Log to stderr rather than syslog
		# -F = Don't fork into background
		echo 'dropbear -R -p 22'
		echo 'mount -t devtmpfs none /dev'
		echo 'mkdir -p /dev/pts && mount -t devpts devpts /dev/pts'
		echo 'mkdir -p /var /var/log && : >/var/log/lastlog'
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
		autoreconf --install				# Autoconf version 2.69 or higher is required

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

		cronjob_add 'iodine' '* * * * * /bin/iodine.check'

		# TODO: serverside: index.php
		# ssh-keygen -f "/home/bastian/.ssh/known_hosts" -R "172.30.0.2"
		# 172.30.0.3 - - [18/Mar/2021:13:44:00 +0000] "GET /iodine/?id=abcde HTTP/1.1" 200 247 "-" "Wget"

		{
		cat <<EOF
#!/bin/sh
# iodine: keep quiet until counter is zero, than try again
# to establish a connection, and if good: ask gateway for
# maybe next downtime (e.g. 1440 = 1 day if silence)

ssh_session_active() {
	case "\$( pidof dropbear )" in
		*' '*) ;;
		*) false ;;
	esac
}

if ssh_session_active; then
	:
elif read -r LEFT 2>/dev/null </tmp/IODINE.sleepmin; then
	# just be quiet:
	if test "\$LEFT" -eq 0; then
		rm /tmp/IODINE.sleepmin
	else
		for PID in \$( pidof iodine ); do kill \$PID; done
		echo \$(( LEFT - 1 )) >/tmp/IODINE.sleepmin
	fi
else
	IFDATA="\$( ip -oneline -f inet address show dev dns0 2>/dev/null )"
	for IP in \$IFDATA; do case "\$IP" in */*) break ;; esac; done

	[ -n "\$IP" ] && {
		# e.g. IP=172.30.0.4/27 -> ipcalc -> GW=172.30.0.1
		GW="\$( ipcalc -n \$IP | cut -d= -f2 | sed 's/.0$//' ).1"
		ID="\$( md5sum /proc/cpuinfo | cut -d' ' -f1 )"
		URL="http://\$GW/iodine/?id=\$ID"
		OUT="\$( wget -T5 -qO - \$URL 2>/dev/null )"
	}

	if test "\$OUT" -gt 0 2>/dev/null; then
		# valid number: wish of quiet/downtime:
		echo "\$OUT" >/tmp/IODINE.sleepmin
	else
		# keep daemon running:
		pidof iodine >/dev/null || {
EOF
			printf '\t\t\t' && init_iodine
			cat <<EOF
		}
	fi
fi

true
EOF
		}       >bin/iodine.check
		chmod +x bin/iodine.check
		sh -n    bin/iodine.check || exit
	}

	init_iodine() {
		if has_arg 'iodine:credentials'; then
			local password="$PARAM1"
			local nx_server="$PARAM2"
			local dns_server="${PARAM3:-8.8.8.8}"

			# enforce to background:
			echo "( echo $password | iodine -r $nx_server $dns_server 2>/dev/null & ) >/dev/null 2>&1"
		else
			echo ": # iodine -r -P password nx_server $dns_server"
		fi
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
	install_dep 'ncurses-dev'	# /usr/include/ncurses.h

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
#	make $SILENT_MAKE $ARCH $CROSSCOMPILE "-j1"    || msg_and_die "$?" "make $ARCH $CROSSCOMPILE"
	make $SILENT_MAKE $ARCH $CROSSCOMPILE install  || msg_and_die "$?" "make $ARCH $CROSSCOMPILE install"
fi

cd ..

if [ -f "$OWN_INITRD" ]; then
	:
else
	export INITRAMFS_BUILD="$BUILDS/initramfs"
	makedir_gointo_and_cleanup "$INITRAMFS_BUILD"

	mkdir -p bin sbin etc proc sys usr/bin usr/sbin usr/bin dev tmp root
	has_arg 'hostfs' && mkdir -p mnt mnt/host

	ROOT_PASS="$( test -n "$SSHPASS" && echo "$SSHPASS" | mkpasswd -m SHA-256 -s || echo 'x' )"
	ROOT_HOME="/root"
	ROOT_SHELL="/bin/sh"

	echo "root:$ROOT_PASS:0:0:root:$ROOT_HOME:$ROOT_SHELL" >'etc/passwd'
	echo "root:x:0:" >'etc/group'

	cp -a "$BUSYBOX_BUILD/_install/"* .
fi

[ -n "$KEEP_LIST" ] && {
	find . | while read -r LINE; do {
		# e.g. ./bin/busybox -> dot is removed in check

		case " $KEEP_LIST " in
			*" ${LINE#?} "*) log "KEEP_LIST: keeping '$LINE'" ;;
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

init_shebang()
{
	echo "#!$BOOTSHELL"
	echo "export SHELL=$( basename "$BOOTSHELL" )"
}

init_procfs()
{
	cat <<EOF
mount -t proc none /proc && {
  read -r UP _ </proc/uptime || UP=\$( cut -d' ' -f1 /proc/uptime )
  while read -r LINE; do
    # shellcheck disable=SC2086
    case "\$LINE" in MemAvailable:*) set -- \$LINE; MEMAVAIL_KB=\$2; break ;; esac
  done </proc/meminfo
}

EOF
}

init_sysfs()
{
	echo 'mount -t sysfs none /sys'
}

init_hostfs()
{
	echo 'mount -t hostfs none /mnt/host'
}

init_crond()
{
	CRONDIR='var/spool/cron/crontabs'
	mkdir -p "$CRONDIR"
	cp "$CRONTAB" "$CRONDIR/root"

	# debug with: crond -c /var/spool/cron/crontabs -f -l 0
	cat <<EOF
CRON="\$( command -v crond || echo false )"
chown -R root:root $CRONDIR
\$CRON -c /$CRONDIR -L /dev/null

EOF
}

init_net()
{
	cat <<EOF
# https://github.com/bittorf/slirp-uml-and-compiler-friendly
# https://github.com/lubomyr/bochs/blob/master/misc/slirp.conf
command -v 'ip' >/dev/null && \\
  ip link show dev eth0 >/dev/null && \\
    printf '%s\\n' "nameserver $DNS" >/etc/resolv.conf && \\
      ip address add 10.0.2.15/24 dev eth0 && \\
	ip link set dev eth0 up && \\
	  ip route add default via 10.0.2.2

EOF
}

init_ttypass()
{
	SHA256="$( { printf '%s' "$TTYPASS"; cat "$SALTFILE"; } | sha256sum )"
	printf '\n%s\n%s\n%s\n%s\n' \
		"# tty-pass:" \
		"printf 'file: ' && read -s PASS" \
		"HASH=\"\$( { printf '%s' \"\$PASS\"; cat \"$SALTFILE\"; } | sha256sum )\"" \
		"test \"\${HASH%% *}\" = ${SHA256%% *} || exit"
}

init_debuginfo()
{
	cat <<EOF
UNAME="\$( command -v uname || printf '%s' false )"
printf '%s\n' "# BOOTTIME_SECONDS \${UP:--1 (missing procfs?)}"
printf '%s\n' "# MEMFREE_KILOBYTES \${MEMAVAIL_KB:--1 (missing procfs?)}"
printf '%s\n' "# UNAME \$( \$UNAME -a || printf uname_unavailable )"
printf '%s\n' "# READY - to quit $( is_uml && echo "type 'exit'" || echo "press once CTRL+A and then 'x' or kill qemu" )"

EOF
}

init_meshack()
{
	cat <<EOF
# hack for MES:
test -f init.user && busybox sleep 2 && AUTO=true ./init.user	# wait for dmesg-trash

EOF
}

init_interactive()
{
	# for 'setsid' and 'cttyhack' see:
	# https://stackoverflow.com/a/35245823/5688306

	# for linking /proc/self/fd see:
	# http://www.linuxfromscratch.org/lfs/view/6.1/chapter06/devices.html
	# https://raw.githubusercontent.com/AcmeSystems/acmepatches/master/buildroot-at91-2020.04.patch

	cat <<EOF
if grep -sq devtmpfs /proc/mounts || mount -t devtmpfs none /dev; then
	LN="\$( command -v ln || echo 'false ' )"
	$( has_arg 'procfs' || echo '	LN=false' )
	\$LN -sf /proc/self/fd   /dev/fd
	\$LN -sf /proc/self/fd/0 /dev/stdin
	\$LN -sf /proc/self/fd/1 /dev/stdout
	\$LN -sf /proc/self/fd/2 /dev/stderr

	if command -v setsid; then
		exec setsid cttyhack $BOOTSHELL 2>/dev/null
	else
		exec $BOOTSHELL 2>/dev/null
	fi
else
	exec $BOOTSHELL 2>/dev/null
fi

EOF
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

[ -f init ] || {
	init_shebang					&& echo
	has_arg 'procfs'	&& init_procfs
	has_arg 'sysfs'		&& init_sysfs
	has_arg 'hostfs'	&& init_hostfs
	test -f "$CRONTAB"	&& init_crond
	has_arg 'net'		&& init_net
	has_arg 'dropbear'	&& init_dropbear	&& echo
	has_arg 'iodine'	&& init_iodine		&& echo
	test -n "$TTYPASS"	&& init_ttypass

	# init_wireguard
	init_debuginfo
	init_meshack
	init_interactive
} >'init'

chmod +x 'init'

case "$( file -b 'init' )" in
	ELF*) ;;
	*) sh -n 'init' || msg_and_die "$?" "check '$PWD/init'" ;;
esac

if [ -f "$OWN_INITRD" ]; then
	INITRD_FILE="$OWN_INITRD"
else
	# xz + zstd only for comparison, not productive
	# cpio -o = --create -H = --format -> cpio -o -H newc
	CPIOARGS="--create --null --format=newc --owner=+0:+0"
	find . -print0 | cpio $CPIOARGS | xz -9  --format=lzma    >"$BUILDS/initramfs.cpio.xz"    || true
	find . -print0 | cpio $CPIOARGS | xz -9e --format=lzma    >"$BUILDS/initramfs.cpio.xz.xz" || true
	find . -print0 | cpio $CPIOARGS | zstd -v -T0 --ultra -22 >"$BUILDS/initramfs.cpio.zstd"  || true
	find . -print0 | cpio $CPIOARGS | gzip -9                 >"$BUILDS/initramfs.cpio.gz"

	INITRD_FILE="$(  readlink -e "$BUILDS/initramfs.cpio.gz" )"
	INITRD_FILE2="$( readlink -e "$BUILDS/initramfs.cpio.xz"    || true )"
	INITRD_FILE3="$( readlink -e "$BUILDS/initramfs.cpio.xz.xz" || true )"
	INITRD_FILE4="$( readlink -e "$BUILDS/initramfs.cpio.zstd"  || true )"
fi

# TODO: uncompress OWN_INITRD?
[ -n "$ONEFILE" ] && {
	INITRD_OBJECT_PLAIN="$INITRAMFS_BUILD"		# directory

	# https://github.com/torvalds/linux/blob/master/usr/gen_initramfs.sh
	# https://github.com/torvalds/linux/blob/master/usr/gen_init_cpio.c

	{
	# see: 'usr/gen_init_cpio -h'
	echo "dir /dev 0755 0 0"
	echo "nod /dev/console 0600 0 0 c 5 1"
	echo "nod /dev/tty0    0600 0 0 c 4 0"
	} >"$INITRD_OBJECT_PLAIN/essential.txt"
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
[ "$DSTARCH" = 'm68k' ] && {
	F="arch/m68k/mvme16x/config.c"
	URL="https://github.com/torvalds/linux/commit/19999a8b8782d7f887353753c3c7cb5fca2f3784"
	grep -q 'out_8(PCCTOVR1, PCCTOVR1_OVR_CLR);' "$F" && {
		checksum "$F" plain
		sed -i 's/out_8(PCCTOVR1, PCCTOVR1_OVR_CLR);/out_8(PCCTOVR1, in_8(PCCTOVR1) | PCCTOVR1_OVR_CLR);/' "$F" || exit
		checksum "$F" after plain || emit_doc "applied: kernel-patch in '$F' (eth:repair:$URL)"
	}

	F="drivers/net/ethernet/i825xx/82596.c"
	checksum "$F" plain
	PATT=',1000,"initialization timed out"'
	STR1=',8000,"initialization timed out"'
	sed -i "s|$PATT|$STR1|" "$F" || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$F' (eth:raise_timeout)"
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

is_uml && {
	# http://lkml.iu.edu/hypermail/linux/kernel/1806.1/05149.html
	F='arch/x86/um/shared/sysdep/ptrace_32.h'
	checksum "$F" plain
	LINE="$( grep -n '#define PTRACE_SYSEMU 31' $F | cut -d':' -f1 )"
	LINE=${LINE:-999999}	# does not harm
	[ -f "$F" ] && sed -i "$((LINE-1)),$((LINE+1))d" "$F"
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | delete PTRACE_SYSEMU"

	# https://lore.kernel.org/patchwork/patch/630468/
	F='arch/x86/um/Makefile' && checksum "$F" plain
	sed -i "s|obj-\$(CONFIG_BINFMT_ELF) += elfcore.o|obj-\$(CONFIG_ELF_CORE) += elfcore.o|" "$F" || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | uml32? undefined reference to 'dump_emit'"

	checksum "$F" plain
	LINE="$( grep -n '#define PTRACE_SYSEMU_SINGLESTEP 32' $F | cut -d':' -f1 )"
	LINE=${LINE:-999999}	# does not harm
	sed -i "$((LINE-1)),$((LINE+1))d" $F || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | delete PTRACE_SYSEMU_SINGLESTEP"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/um/drivers/net_user.c?id=f9bb3b5947c507d402eecbffabb8fb0864263ad1
	F1='arch/um/drivers/net_user.c'
	checksum "$F1" plain
	grep -q "int stdout;" "$F1" && sed -i 's|stdout|stdout_fd|g' "$F1"
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | macro-fix"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/um/os-Linux/file.c?id=8eeba4e9a76cd126e737d3d303d9c424b66ea90d
	F1='arch/um/os-Linux/file.c' && PATT="#include <sys/types.h>"
	checksum "$F1" plain
	grep -q "$PATT" "$F1" || sed -i "s|#include <sys/un.h>|&\n$PATT|" "$F1"
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/um/os-Linux/file.c?id=530ba6c7cb3c22435a4d26de47037bb6f86a5329
	checksum "$F1" plain && PATT="#include <sys/sysmacros.h>"
	grep -q "$PATT" "$F1" || sed -i "s|#include <sys/un.h>|${PATT}\n&|" "$F1"
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/um/os-Linux/signal.c?id=9a75551aeaa8c79fd6ad713cb20e6bbccc767331
	F1='arch/um/os-Linux/signal.c' && PATT="stack_t stack = ((stack_t)"
	checksum "$F1" plain
	grep -q "$PATT" "$F1" && {
		sed -i '/.ss_sp	= (__ptr_t) sig_stack,/d' "$F1"
		sed -i '/size - sizeof(void \*) });/d' "$F1"
		sed -i "s|$PATT.*|stack_t stack = {\n\t\t.ss_flags = 0,\n\t\t.ss_sp = sig_stack,\n\t\t.ss_size = size - sizeof(void \*)\n\t};|" "$F1"
	}
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/x86/um/ldt.c?id=37e81a016cc847c03ea71570fea29f12ca390bee
	F1='arch/x86/um/ldt.c' && PATT='extern int modify_ldt'
	checksum "$F1" plain
	grep -q "$PATT" "$F1" && {
		sed -i "s|$PATT.*|static inline int modify_ldt (int func, void \*ptr, unsigned long bytecount)\n{\n\treturn syscall(__NR_modify_ldt, func, ptr, bytecount);\n}\n|" "$F1"
	}
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/x86/um/ldt.c?id=da20ab35180780e4a6eadc804544f1fa967f3567
	F1='arch/x86/um/ldt.c' && PATT="#include <linux/syscalls.h>"
	checksum "$F1" plain
	grep -q "$PATT" "$F1" || {
		sed -i 's|return do_modify_ldt_skas(func, ptr, bytecount);|return (unsigned int)do_modify_ldt_skas(func, ptr, bytecount);|' "$F1"
		sed -i 's|int sys_modify_ldt(int.*|SYSCALL_DEFINE3(modify_ldt, int , func , void __user \* , ptr ,\n\t\tunsigned long , bytecount)|' "$F1"
		sed -i "s|#include <linux/slab.h>|&\n$PATT\n#include <linux/uaccess.h>|" "$F1"
	}
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/um/include/shared/init.h?id=cca76c1ad61d08097af5a691195f9a42d72e978f
#	F1='arch/um/include/shared/init.h' && PATT="#define __uml_init_call"
#	checksum "$F1" plain
#	grep -q "$PATT" "$F1" && {
#		sed -i '/extern initcall_t __uml_initcall_start, __uml_initcall_end;/d' "$F1"
#		sed -i "/$PATT.*/d" "$F1"
#		sed -i '/static initcall_t __uml_initcall_.*/d' "$F1"
#		sed -i '/#define __uml_init_call.*/d' "$F1"
#	}
#	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"

	# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/arch/um/include/shared/init.h?id=33def8498fdde180023444b08e12b72a9efed41d
	F1='arch/um/include/shared/init.h' && PATT="__section(.uml.help.init)"
	checksum "$F1" plain
	grep -q "$PATT" "$F1" && sed -i 's/^\(.*__used __section\)(\(.*\))$/\1("\2")/g' "$F1"
	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | add colons"

	# https://github.com/torvalds/linux/commit/30b11ee9ae23d78de66b9ae315880af17a64ba83
#	F1='arch/um/include/shared/init.h' && PATT='#ifdef __UM_HOST__'
#	checksum "$F1" plain
#	grep -q "$PATT" "$F1" && {
#		sed -i '1{s/^.*/#include <stddef.h>\n/}' "$F1"
#		sed -i '1{s/^.*/#include <stddef.h>\n/}' arch/um/include/shared/user.h
#	}
#	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | add stddef.h"

#	# https://github.com/torvalds/linux/commit/298e20ba8c197e8d429a6c8671550c41c7919033
#	F1='arch/um/Makefile' && PATT='patsubst -D__KERNEL__,,'
#	checksum "$F1" plain
#	grep -q "$PATT" "$F1" && {
#		# shellcheck disable=SC2016
#		NEW='USER_CFLAGS = $(patsubst $(KERNEL_DEFINES),,$(patsubst -I%,,$(KBUILD_CFLAGS))) $(ARCH_INCLUDE) $(MODE_INCLUDE) $(filter -I%,$(CFLAGS)) -D_FILE_OFFSET_BITS=64 -idirafter include -D__KERNEL__ -D__UM_HOST__'
#		# shellcheck disable=SC2016
#		sed -i '/$(KBUILD_CFLAGS)))) $(ARCH_INCLUDE) $(MODE_INCLUDE)/d' "$F1"
#		sed -i '/-D_FILE_OFFSET_BITS=64 -idirafter include/d' "$F1"
#		sed -i "s|^.*$PATT.*$|$NEW|" "$F1"
#	}
#	checksum "$F1" after plain || emit_doc "applied: kernel-patch in '$PWD/$F1' | dismiss: $PATT"
}
#
[ -n "$FAKEID" ] && {
	F="$( find . -type f -name 'mkcompile_h' )" && [ -f "$F" ] && checksum "$F" plain
	REPLACE="sed -i 's;#define LINUX_COMPILER .*;#define LINUX_COMPILER \"compiler/linker unset\";' .tmpcompile"
	sed -i "s|# Only replace the real|${REPLACE}\n\n# Only replace the real|" "$F" || exit
	checksum "$F" after plain || emit_doc "applied: kernel-patch in '$PWD/$F' | FAKEID"
}
# e.g.: gcc (Debian 10.2.1-6) 10.2.1 20210110
for WORD in $CC_VERSION; do {
	test 2>/dev/null "${WORD%%.*}" -gt 1 || continue
	VERSION="${WORD%%.*}"	# e.g. 10.2.1-6 -> 10
	DEST="include/linux/compiler-gcc${VERSION}.h"

	# /home/bastian/software/minilinux/minilinux/opt/linux/linux-3.19.8/include/linux/compiler-gcc.h:106:1:
	# fatal error: linux/compiler-gcc9.h: file or directory not found
	[ -f "$DEST" ] || {
		HEADER="$( find include/linux/ -type f -name 'compiler-gcc[0-9].h' | head -n1 )"
		[ -f "$HEADER" ] && \
			cp -v "$HEADER" "$DEST" && \
				emit_doc "applied: kernel-patch: $HEADER -> $DEST"
	}

	break
} done
#
emit_doc "applied: kernel-patch | READY"

# kernel 2,3,4 but nut 5.x - FIXME!
# sed -i 's|-Wall -Wundef|& -fno-pie|' Makefile

T0="$( date +%s )"

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
	install_dep 'ncurses-dev'	# /usr/include/ncurses.h

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
	echo "make        $ARCH $CROSSCOMPILE -j$CPU 'CFLAGS_KERNEL=$CF_ADD'"
	yes "" | make $SILENT_MAKE $ARCH $CROSSCOMPILE -j"$CPU" "CFLAGS_KERNEL=$CF_ADD" || msg_and_die "$?" "make $ARCH $CROSSCOMPILE"
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

if is_uml; then
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
		log "extracting ELF failed"
	fi
else
	log "extractor for ELF not found"
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
	uml*)
		has_arg 'upx' && {
			if   has_arg 'obfuscate'; then
				elfcrunch_file "$KERNEL_FILE" || exit
			elif file_iscompressed "$KERNEL_FILE"; then
				log "no UPX compression, file already compressed: $KERNEL_FILE"
			else
				elfcrunch_file "$KERNEL_FILE" || exit
			fi
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

for WORD in $EMBED_CMDLINE; do {
	case "$WORD" in
		'initrd='*)
			rm -f "${WORD#*=}" 2>/dev/null
			cp -v "$INITRD_FILE" "${WORD#*=}" || log "failed: cp '$INITRD_FILE' '${WORD#*=}' | please do that manually"
		;;
		*'=slirp,'*)
			# eth0=slirp,FE:FD:01:02:03:04,/tmp/slirp.bin
			rm -f "${WORD##*,}" 2>/dev/null
			cp -v "$SLIRP_BIN" "${WORD##*,}" || log "failed: cp '$SLIRP_BIN' '${WORD##*,}' | please do that manually"
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
# CMDLINE_OPTIONS: $( set -- $OPTIONS && echo "$*" )
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
# KERNEL_SIZE: $( wc -c <"$KERNEL_FILE" ) bytes [is $( file_iscompressed "$KERNEL_FILE" 'info' )compressed$( test -n "$ONEFILE" && echo ', initrd is included' )]
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
#        nodes......: not-implemented-yet
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

QEMU_OPTIONS=
KERNEL_ARGS='console=ttyS0'
[ -z "\$PATTERN" ] && PATTERN="<hopefully_this_pattern_will_never_match>"

grep -q svm /proc/cpuinfo && KVM_SUPPORT='-enable-kvm'
grep -q vmx /proc/cpuinfo && KVM_SUPPORT='-enable-kvm'
$( test -n "$NOKVM" && echo 'KVM_SUPPORT=' )
[ -n "\$KVM_SUPPORT" ] && test "\$( id -u )" -gt 0 && KVM_PRE="\$( command -v sudo )"

$( has_arg 'net' && echo "QEMU_OPTIONS='-net nic,model=rtl8139 -net user'" )

case "$DSTARCH" in
	armel|armhf|arm|arm64)
		QEMU_OPTIONS=	# FIXME! add proper: -net nic,model=XXX -net user
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
		$( test -x "$SLIRP_BIN" && echo "		UMLNET='eth0=slirp,FE:FD:01:02:03:04,$SLIRP_BIN'" )
	;;
	i686|x86_64)
		if [ -n "$QEMUCPU" ]; then
			case "$DSTARCH" in
				# microvm: This kernel requires an i586 CPU, but only detected an i486 CPU.
				i686) KVM_SUPPORT="\$KVM_SUPPORT -cpu $QEMUCPU -machine isapc" ;;
				*_64) KVM_SUPPORT="\$KVM_SUPPORT -cpu $QEMUCPU -machine microvm" ;;
			esac
		else
			KVM_SUPPORT="\$KVM_SUPPORT -cpu host"
		fi
	;;
esac

$( test -f "$BIOS" && echo "BIOS='-bios \"$BIOS\"'" )
$( has_arg 'net' && echo "KERNEL_ARGS=\"\$KERNEL_ARGS ip=dhcp nameserver=8.8.8.8\"" )

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

				if [ -n "$EMBED_CMDLINE" ]; then	# embedded commandline:
					$KERNEL_FILE
				else
					$KERNEL_FILE mem=\$MEM \$UMLNET $( test -n "$ONEFILE" || echo "initrd=$INITRD_FILE" )
				fi

				rm -fR "\$DIR"
			;;
			*)
				echo "INTERACTIVE: will start now QEMU: \$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT ..."
				echo

				\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\
					-kernel $KERNEL_FILE \\
					$( test -n "$ONEFILE" || echo "-initrd $INITRD_FILE" ) \\
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

UMLDIR="\$( mktemp -d )" || exit
PIDFILE="\$( mktemp -u )" || exit
case "$DSTARCH" in uml*) PIDFILE= ;; esac

PIPE="\$( mktemp )" || exit
mkfifo "\$PIPE.in"  || exit
mkfifo "\$PIPE.out" || exit
\$KVM_PRE echo			# cache sudo-pass for (maybe) next interactive run

(
	case "$DSTARCH" in
		uml*)
			echo "AUTOTEST for \$MAX sec: will start now UML-linux"
			echo

			export TMPDIR="\$UMLDIR"

			if [ -n "$EMBED_CMDLINE" ]; then	# test for EMBED_CMDLINE
				$KERNEL_FILE
			else
				$KERNEL_FILE uml_dir="\$UMLDIR" mem=\$MEM \$UMLNET \\
					$( test -n "$ONEFILE" || echo "initrd=$INITRD_FILE" ) >"\$PIPE.out" 2>&1
			fi

			rm -fR "\$UMLDIR"
		;;
		*)
			echo "AUTOTEST for \$MAX sec: will start now QEMU: \$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT ..."
			echo

			# code must be duplicated, see below in LOG
			\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\
				-kernel $KERNEL_FILE \\
				$( test -n "$ONEFILE" || echo "-initrd $INITRD_FILE" ) \\
				-nographic \\
				-serial pipe:\$PIPE \\
				-append "\$KERNEL_ARGS" \$QEMU_OPTIONS -pidfile "\$PIDFILE"
		;;
	esac
) &

T0="\$( date +%s )"

if [ -z "\$PIDFILE" ]; then
	for _ in 1 2 3 4 5; do
		PIDFILE="\$( find "\$UMLDIR" -type f -name 'pid' )"
		PID="\$( test -f "\$PIDFILE" && cat "\$PIDFILE" )"
		[ -n "\$PID" ] && break
		sleep 1

		[ -n "$EMBED_CMDLINE" ] && {
			for PID in \$( pidof vmlinux ); do :; done
			break
		}
	done
else
	for _ in 1 2 3 4 5; do
		read -r PID <"\$PIDFILE" && break
		sleep 1
		\$KVM_PRE chmod 777 "\$PIDFILE"
	done
fi

echo "PIDFILE: '\$PIDFILE' PID: '\$PID' UMLDIR: '\$UMLDIR'"
test -n "\$PID" || echo "# ERROR: no PIDFILE or QEMU/uml-vmlinux already stopped"

{
	echo "# images generated using:"
	echo "# https://github.com/bittorf/kritis-linux"
	echo
	grep ^'#' "\$0"
	echo
	echo "# startup:"

	case "$DSTARCH" in
		uml*)
			echo "$KERNEL_FILE uml_dir=\$UMLDIR mem=\$MEM \$UMLNET $( test -n "$ONEFILE" || echo "initrd=$INITRD_FILE" )"
		;;
		*)
			# code duplication from above real startup:
			echo "\$KVM_PRE \$QEMU -m \$MEM \$KVM_SUPPORT \$BIOS \\\\"
			echo "	-kernel $KERNEL_FILE \\\\"
			echo "	$( test -n "$ONEFILE" || echo "-initrd $INITRD_FILE" ) \\\\"
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

		echo "\$LINE" >>"\$PIPE"
		case "\$LINE" in
			'# BOOTTIME_SECONDS '*|'# UNAME '*)
			;;
			"\$PATTERN"*|*' Attempted to kill init'*|'ABORTING HARD'*|'Bootstrapping completed.'*|\\
			'Aborted (core dumped)'|'Unable to boot - please use a kernel appropriate for your CPU'*)
				echo 'READY' >>"\$PIPE"
				break
			;;
		esac
	} done <"\$PIPE.out" | stdbuf -i0 -o0 -e0 tee -a "\$LOG"
) &

RC=1
[ -z "\$PATTERN" ] && RC=0
[ "\$PATTERN" = '<hopefully_this_pattern_will_never_match>' ] && RC=0

I=\$MAX
while [ \$I -gt 0 ]; do {
	\$KVM_PRE kill -0 \$PID || break
	LINE="\$( tail -n1 "\$PIPE" )"

	case "\$LINE" in
		READY) RC=0 && break ;;		# TODO: more finegraned
		*) sleep 1; I=\$(( I - 1 )) ;;
	esac
} done

export FILENAME_OFFER='log_${GIT_USERNAME}_${GIT_REPONAME}_${GIT_BRANCH}_${GIT_SHORTHASH}_${DSTARCH}_kernel${KERNEL_VERSION}.txt'

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

	LOG_URL="\$( command -v 'curl' >/dev/null && test \$MAX -gt 5 && curl -m 5 -F"file=@\$LOG" https://ttm.sh )"
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

echo "will now stop '\$QEMU' with pid '\$PID'" && \$KVM_PRE echo
while \$KVM_PRE kill -0 \$PID; do \$KVM_PRE kill \$PID; sleep 1; \$KVM_PRE kill -0 \$PID && \$KVM_PRE kill -s KILL \$PID; done
rm -f "\$PIPE" "\$PIPE.in" "\$PIPE.out" "\$PIDFILE"

test \$RC -eq 0
!

ABORT_PATTERN='# READY'
[ -f "$OWN_INITRD" ] && ABORT_PATTERN=

chmod +x "$LINUX_BUILD/run.sh" && \
	 "$LINUX_BUILD/run.sh" 'autotest' "$ABORT_PATTERN" "$( test -z "$EMBED_CMDLINE" && echo '20' || echo '3' )"
RC=$?

echo
echo "# exit with RC:$RC"
echo "# see: $LINUX_BUILD/run.sh"
echo "#"
echo "# thanks for using:"
echo "# https://github.com/bittorf/kritis-linux"
echo

exit $RC
