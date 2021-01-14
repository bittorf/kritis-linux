#!/bin/sh

KEEP_FILES="$2"			# e.g. '/bin/busybox /bin/sh /bin/cat' or .
ADD_DIR="$4"			# e.g. "$PWD"
WAIT_PATTERN="$6"		# e.g. 'READY_BOOT_MARKER'
WAIT_SECONDS="${8:-120}"
LINUX_VERSION="${10:-latest}"	# e.g. 'https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.17.tar.xz'
# INIT="${12:-init.user}"	# TODO
# CORE=... busybox/toybox	# TODO

cd "$( dirname "$0" )" || exit

TMP1="$( mktemp )" || exit
TMP2="$( mktemp )" || exit

echo "[OK] INITRD_DIR_ADD='$ADD_DIR' KEEP_LIST='$KEEP_FILES' ./minilinux.sh '$LINUX_VERSION'"

INITRD_DIR_ADD="$ADD_DIR" KEEP_LIST="$KEEP_FILES" ./minilinux.sh "$LINUX_VERSION" >"$TMP1" 2>"$TMP2" || {
	RC="$?"
	cat "$TMP1" "$TMP2"	# TODO: add --debugbuild
	exit "$RC"
}

echo
echo "kernel.bin: $( ls -l minilinux/builds/linux/arch/x86/boot/bzImage	)"
echo "initrd.xz:  $( ls -l minilinux/builds/initramfs.cpio.xz.xz )"
echo
head -n5 minilinux/builds/linux/.config
echo
echo "[OK] now running 'minilinux/builds/linux/run.sh' in autotest-mode waiting $WAIT_SECONDS sec for pattern '$WAIT_PATTERN'"

minilinux/builds/linux/run.sh autotest "$WAIT_PATTERN" "$WAIT_SECONDS"
