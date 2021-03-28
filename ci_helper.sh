#!/bin/sh

while [ -n "$1" ]; do {
	case "$1" in
		--features) export FEATURES="$2" ;;	# e.g. busybox,toybox,net,xyz,foo
		--pattern) WAIT_PATTERN="$2" ;;		# e.g. '# unittest ok'
		--maxwait) WAIT_SECONDS="$2" ;;		# e.g. 600 (default is 120)
		--logtime) export LOGTIME="$2" ;;	# e.g. false (default is true)
		--ramsize) export MEM="$2" ;;		# e.g. 512
		--qemucpu) export QEMUCPU="$2" ;;	# e.g. 486 or host
		--diradd) export INITRD_DIR_ADD="$2" ;;	# e.g. '/path/to/my/files' or e.g. simply "$(pwd)"
		--initrd) export OWN_INITRD="$2" ;;	# e.g. '/path/to/myinit.tgz'
		--kernel) LINUX_VERSION="$2" ;;		# e.g. 'latest' (=default) or '5.4.89' or an URL to .tgz/.xz
		--fakeid) export FAKEID="$2" ;;		# e.g. 'foo@bar.baz'
		--ttypass) export TTYPASS="$2" ;;	# e.g. 'golf2'
		--sshpass) export SSHPASS="$2" ;;	# e.g. 'golf3'
		--onefile) export ONEFILE='true' ;;
		--cmdline) export EMBED_CMDLINE="$2" ;;	# e.g. 'mem=48M initrd=/path/to/file'
		--kconfig) export OWN_KCONFIG="$2" ;;	# e.g. '/path/to/.config'
		--myinit) export MYINIT="$2" ;;		# e.g. 'my_file.sh' (relative to diradd-path)
		--nokvm) export NOKVM='true' ;;
		--debug) export DEBUG="$2" ;;		# e.g. true
		--keep) export KEEP_LIST="$2" ;;	# e.g. '/bin/busybox /bin/sh /bin/cat' 
		--arch) export DSTARCH="$2" ;;		# e.g. one of i386,x86_64,armel,armhf,arm64,mips,m68k,or1k (default is x86_64)
		--log) export LOG="$2" ;;		# e.g. '/path/to/file.txt'
	esac && shift
} done

# support relative and absolute paths:
[ -d "$(pwd)/$INITRD_DIR_ADD" ] && INITRD_DIR_ADD="$(pwd)/$INITRD_DIR_ADD"
[ -f "$(pwd)/$OWN_INITRD" ] && OWN_INITRD="$(pwd)/$OWN_INITRD"
[ -f "$(pwd)/$OWN_CONFIG" ] && OWN_CONFIG="$(pwd)/$OWN_CONFIG"
[ -f "$(pwd)/$MYINIT" ] && MYINIT="$(pwd)/$MYINIT"

[ -d "${GITDIR:=.git}" ] && {
	[ "$GIT_REPONAME"  ] || GIT_REPONAME="$( basename "$( cd "$GITDIR" && git rev-parse --show-toplevel )" )"
	[ "$GIT_USERNAME"  ] || GIT_USERNAME="$( basename "$( cd "$GITDIR" && dirname "$( git config --get remote.origin.url )" )" )"
	[ "$GIT_SHORTHASH" ] || GIT_SHORTHASH="$( cd "$GITDIR" && git rev-parse --short HEAD )"
	[ "$GIT_BRANCH"    ] || GIT_BRANCH="$( cd "$GITDIR" && git rev-parse --abbrev-ref HEAD )"
	export GIT_REPONAME GIT_USERNAME GIT_SHORTHASH GIT_BRANCH
}

cd "$( dirname "$0" )" || exit
TMP="$( mktemp )" || exit

echo "[OK] executing ./minilinux.sh '${LINUX_VERSION:=latest}' | see log: '$TMP'"
if ./minilinux.sh "$LINUX_VERSION" >"$TMP" 2>&1; then
	[ -n "$DEBUG" ] && cat "$TMP"
else
	RC="$?" && { cat "$TMP"; echo; echo "ERROR:$RC"; exit "$RC"; }
fi

grep ^'#' minilinux/builds/linux/run.sh && echo
echo "[OK] generated 'minilinux/builds/linux/run.sh', and run it in autotest-mode,"
echo "     waiting max. ${WAIT_SECONDS:-<unlimited>} sec for pattern '${WAIT_PATTERN:-<no pattern set>}'"

minilinux/builds/linux/run.sh autotest "$WAIT_PATTERN" "$WAIT_SECONDS"
