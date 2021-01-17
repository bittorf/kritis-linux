### KRITIS Linux

* see [KRITIS](https://de.wikipedia.org/w/index.php?title=KRITIS)
* still alpha
* supports musl, glibc and busybox/toybox

### Syntax

* get help with, e.g. `./minilinux.sh`
* make a linux with e.g. `./minilinux.sh latest`

### CI: build and run QEMU instance

For continuous integration of your code, use a script like this, for deploy a minimal Linux-VM.

```
# https://github.com/bittorf/kritis-linux
git clone --depth 1 https://github.com/bittorf/kritis-linux.git

kritis-linux/ci_helper.sh \
	--arch x86_64 \
	--ramsize 384 \
	--kernel latest \
	--features busybox \
	--keep "/bin/busybox /bin/sh /bin/cat" \
	--diradd /path/to/myfiles \
	--myinit script.xy \
	--maxwait 550 \
	--pattern "unittest_ready"
```

* above command builds latest 64bit 'Linux' and adds 'Busybox'
* removes all symlinks, except those in --keep
* adds directory in --diradd to initial ramdisk
* uses 'script.xy' as /sbin/init
* starts qemu with 384mb RAM and waits till --pattern shows up
* aborts the run, when over 550 seconds

### more switches and options

* --initrd /path/to/initial-ramdisk.tgz
* --kconfig /path/to/.kernel-config
* --arch uml|armel|armhf|arm64|i386|x86_64 (more planned)
* --clib glibc|musl|dietlibc
* --features busybox|toybox|net|dash|bash
  * add several with --features a,b,c
* --debug true
