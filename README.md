### KRITIS Linux

* see [https://de.wikipedia.org/w/index.php?title=KRITIS]
* still alpha
* supports musl, glibc and busybox/toybox

# Syntax

* get help with, e.g. `./minilinux.sh`

# CI-integration / autobuild and run QEMU:

```
git clone --depth 1 https://github.com/bittorf/kritis-linux.git

kritis-linux/ci_helper.sh \
	--keep '/bin/busybox /bin/sh /bin/cat' \
	--diradd "$( pwd )" \
	--pattern "In QEMU-mode you can now explore the system" \
	--maxwait "600" \
	--linux "latest" \
	--myinit "script.xy"
```

* above command builds linux + busybox 
* removes all symlinks, except those in --keep
* adds directory in --diradd to initial ramdisk
* starts qemu and waits till --pattern shows up
* aborts the run, when over 600 seconds
* uses latest mainline linux (default)
* and uses 'script.xy' as /sbin/init
