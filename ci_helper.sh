#!/bin/sh

KEEP_FILES="$1"			# e.g. '/bin/busybox /bin/sh /bin/cat' or .
ADD_DIR="$2"			# e.g. "$PWD"
WAIT_PATTERN="$3"
WAIT_SECONDS="${4:-120}"
LINUX_VERSION="${5:-latest}"	# e.g. 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.17.tar.xz'

cd "$( dirname "$0" )" || exit

TMP1="$( mktemp )" || exit
TMP2="$( mktemp )" || exit

echo "[OK] INITRD_DIR_ADD='$ADD_DIR' KEEP_LIST='$KEEP_FILES' ./minilinux.sh '$LINUX_VERSION'"

cd "$( dirname "$0" )" || exit
INITRD_DIR_ADD="$ADD_DIR" KEEP_LIST="$KEEP_FILES" ./minilinux.sh "$LINUX_VERSION" >"$TMP1" 2>"$TMP2" || {
	RC="$?"
	cat "$TMP1" "$TMP2"
	exit "$RC"
}

echo
echo "kernel.bin: $( ls -l minilinux/builds/linux/arch/x86/boot/bzImage	)"
echo "initrd.xz:  $( ls -l minilinux/builds/initramfs.cpio.xz.xz )"
echo
echo "[OK] now running 'minilinux/builds/linux/run.sh' in autotest-mode"
minilinux/builds/linux/run.sh autotest "$WAIT_PATTERN" "$WAIT_SECONDS"

