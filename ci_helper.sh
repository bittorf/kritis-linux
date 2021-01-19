#!/bin/sh

while [ -n "$1" ]; do {
	case "$1" in
		--features) export FEATURES="$2" ;;	# e.g. busybox,toybox,net,xyz,foo
		--pattern) WAIT_PATTERN="$2" ;;		# e.g. '# unittest ok'
		--maxwait) WAIT_SECONDS="$2" ;;		# e.g. 600 (default is 120)
		--ramsize) export MEM="$2" ;;		# e.g. 512
		--diradd) export INITRD_DIR_ADD="$2" ;;	# e.g. '/path/to/my/files' or e.g. simply "$(pwd)"
		--initrd) export OWN_INITRD="$2" ;;	# e.g. '/path/to/myinit.tgz'
		--kernel) LINUX_VERSION="$2" ;;		# e.g. 'latest' (=default) or '5.4.89' or an URL to .tgz/.xz
		--kconfig) export OWN_CONFIG="$2" ;;	# e.g. '/path/to/.config'
		--myinit) export MYINIT="$2" ;;		# e.g. 'my_file.sh' (relative to diradd-path)
		--debug) DEBUG="$2" ;;			# e.g. true
		--keep) export KEEP_LIST="$2" ;;	# e.g. '/bin/busybox /bin/sh /bin/cat' 
		--arch) export DSTARCH="$2" ;;		# e.g. one of i386,x86_64,armel,armhf,arm64,mips,m68k (default is x86_64)
		--log) export LOG="$2" ;;		# e.g. '/path/to/file.txt'
	esac && shift
} done

# support relative and absolute paths:
[ -d "$(pwd)/$INITRD_DIR_ADD" ] && INITRD_DIR_ADD="$(pwd)/$INITRD_DIR_ADD"
[ -f "$(pwd)/$OWN_INITRD" ] && OWN_INITRD="$(pwd)/$OWN_INITRD"
[ -f "$(pwd)/$OWN_CONFIG" ] && OWN_CONFIG="$(pwd)/$OWN_CONFIG"
[ -f "$(pwd)/$MYINIT" ] && MYINIT="$(pwd)/$MYINIT"

cd "$( dirname "$0" )" || exit
TMP1="$( mktemp )" || exit
TMP2="$( mktemp )" || exit

echo "[OK] executing ./minilinux.sh '${LINUX_VERSION:=latest}'"
if ./minilinux.sh "$LINUX_VERSION" >"$TMP1" 2>"$TMP2"; then
	[ -n "$DEBUG" ] && cat "$TMP1" "$TMP2"
else
	RC="$?" && { cat "$TMP1" "$TMP2"; exit "$RC"; }
fi

grep ^'#' minilinux/builds/linux/run.sh && echo
echo "[OK] starting 'minilinux/builds/linux/run.sh' in autotest-mode,"
echo "     waiting max. ${WAIT_SECONDS:=120} sec for pattern '$WAIT_PATTERN'"

minilinux/builds/linux/run.sh autotest "$WAIT_PATTERN" "$WAIT_SECONDS"

