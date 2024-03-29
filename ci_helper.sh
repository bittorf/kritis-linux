#!/bin/sh

while [ -n "$1" ]; do {
	case "$1" in
		--verbose) set -x ;;
		--feature*) export FEATURES="$2" ;;	# e.g. busybox,toybox,net,xyz,foo
		--pattern) WAIT_PATTERN="$2" ;;		# e.g. '# unittest ok'
		--maxwait) WAIT_SECONDS="$2" ;;		# e.g. 600 (default is 120)
		--logtime) export LOGTIME="$2" ;;	# e.g. false (default is true)
		--ramsize) export MEM="$2" ;;		# e.g. 512
		--qemucpu) export QEMUCPU="$2" ;;	# e.g. 486 or host
		--parallel) export CPU="$2" ;;		# e.g. 1
		--diradd) export INITRD_DIR_ADD="$2" ;;	# e.g. '/path/to/my/files' or e.g. simply "$(pwd)"
		--initrd) export OWN_INITRD="$2" ;;	# e.g. '/path/to/myinit.tgz'
		--kernel) LINUX_VERSION="$2" ;;		# e.g. 'latest' (=default) or '5.4.89' or an URL to .tgz/.xz
		--private) export PRIVATE='true' ;;	# makes copy of kernel/initrd, useful in combination with 'MULTI'
		--fakeid) export FAKEID="$2" ;;		# e.g. 'foo@bar.baz'
		--ttypass) export TTYPASS="$2" ;;	# e.g. 'golf2'
		--sshpass) export SSHPASS="$2" ;;	# e.g. 'golf3'
		--onefile) export ONEFILE='true' ;;
		--cmdline) export EMBED_CMDLINE="$2" ;;	# e.g. 'mem=48M initrd=/path/to/file'
		--kconfig) export OWN_KCONFIG="$2" ;;	# e.g. '/path/to/.config'
		--myinit) export MYINIT="$2" ;;		# e.g. 'my_file.sh' (relative to diradd-path)
		--nokvm) export NOKVM='true' ;;
		--repeat) export REPEAT="$2" ;;		# e.g. 6 (how often MULTI runs)
		--multi) export MULTI="$2" ;;		# e.g. 32 (parallel invocations of some kernel/initrd)
		--debug) export DEBUG="$2" ;;		# e.g. true
		--keep) export KEEP_LIST="$2" ;;	# e.g. '/bin/busybox /bin/sh /bin/cat' 
		--arch) export DSTARCH="$2" ;;		# e.g. one of i386,x86_64,armel,armhf,arm64,mips,m68k,or1k (default is x86_64)
		--log|--logfile) export LOG="$2" ;;	# e.g. '/path/to/file.txt'
		*) echo "invalid keyword: $1" && exit ;;
	esac
	case "$1" in --private|--onefile|--nokvm|--verbose) shift ;; *) shift 2 ;; esac
} done

# support relative and absolute paths:
[ -d "$PWD/$INITRD_DIR_ADD" ] && INITRD_DIR_ADD="$PWD/$INITRD_DIR_ADD"
[ -f "$PWD/$OWN_INITRD" ] && OWN_INITRD="$PWD/$OWN_INITRD"
[ -f "$PWD/$OWN_CONFIG" ] && OWN_CONFIG="$PWD/$OWN_CONFIG"
[ -f "$PWD/$MYINIT" ] && MYINIT="$PWD/$MYINIT"

[ -d "${GITDIR:=.git}" ] && {
	[ "$GIT_REPONAME"  ] || GIT_REPONAME="$( basename "$( cd "$GITDIR/".. && git rev-parse --show-toplevel )" )"
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
echo "     repeat: ${REPEAT:=1} multi: ${MULTI:--}"

R="$REPEAT"
M="$MULTI"
K=0
UNIX0="$( date +%s )"

while [ $REPEAT -gt 0 ]; do {
	REPEAT=$(( REPEAT - 1 ))

	if [ -n "$MULTI" ]; then
		UNIX1="$( date +%s )"
		MULTI_LOG="${LOG:=$( mktemp )}"
		LOGDIR="$( dirname "$LOG" )"
		count() { find "$LOGDIR" -type f -name '*-multilog-*.running' -printf '.' 2>/dev/null | wc -c; }

		while [ "$MULTI" -gt 0 ]; do
			(
				export LOG="${MULTI_LOG}-multilog-${MULTI}-$UNIX1"
				touch "$LOG.running"

				MAX_BOOTFAILS=10
				while [ $MAX_BOOTFAILS -gt 0 ]; do {
					MAX_BOOTFAILS=$(( MAX_BOOTFAILS - 1 ))

					minilinux/builds/linux/run.sh autotest "$WAIT_PATTERN" "$WAIT_SECONDS" >/dev/null 2>&1
					grep 'autotest-mode ready after 0 ' "$LOG" || break
					sleep 1
				} done

				rm "$LOG.running"
				echo "[OK] job ready: $LOG"
			) &
			MULTI=$(( MULTI - 1 ))
			K=$(( K + 1 ))
		done

		echo "[OK] still $C/$M jobs running, repeat $REPEAT/$R, overall runs: $K | $( date )"
		while C="$( count )"; test "$C" -ne 0; do {
			sleep 15
		} done

		MULTI="$M"
		UNIX2="$( date +%s )"
		echo "[OK] lasts $(( UNIX2 - UNIX1 )) seconds, repeat: $REPEAT overall runs: $K, overall $(( UNIX2 - UNIX0 )) sec"
	else
		minilinux/builds/linux/run.sh autotest "$WAIT_PATTERN" "$WAIT_SECONDS"
	fi
} done
