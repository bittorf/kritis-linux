### KRITIS Linux

* see [KRITIS](https://de.wikipedia.org/w/index.php?title=KRITIS)
* still alpha
* supports musl, glibc and busybox/toybox

### Syntax

* get help with, e.g. `./minilinux.sh`
* make a linux with e.g. `./minilinux.sh latest`

### CI: build and run QEMU instance

For continuous integration of your code, use scripts like these, for deploy a minimal Linux-VM.

#### CI: example one

```
# https://github.com/bittorf/kritis-linux
git clone --depth 1 https://github.com/bittorf/kritis-linux.git

kritis-linux/ci_helper.sh \
	--kernel 4.4.215 \
	--features busybox,procfs,sysfs \
	--diradd /path/to/myfiles
```

* above command builds 64bit `Linux v4.4.215` and adds `Busybox`
* also adds support for the kernels `procfs` and `sysfs`
* and adds your own files, eventually with a `init.user`,
* which is executed directly after our minimal init

#### CI: example two

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

* above command builds `latest` 64bit `Linux` and adds `Busybox`
* removes all files/symlinks, except those in `--keep`
* adds directory in `--diradd` to initial ramdisk
* uses `script.xy` as `/sbin/init`
* starts qemu with `384mb` RAM and waits till `--pattern` shows up
* aborts the run, when over `550 seconds`

### more switches and options

* `--initrd` /path/to/initial-ramdisk.tgz
* `--kconfig` /path/to/.kernel-config
* `--arch x86_64` or `i386`,`uml`,`armel`,`armhf`,`arm64` (more planned)
* `--clib glibc` or `musl`,`dietlibc`
* `--features` `is,a,comma,separated,list`
  * e.g. `busybox` or `toybox`,`net`,`dash`,`bash`,
  * e.g. `printk`,`sysfs`,`procfs`,`menuconfig`,
  * e.g. `tinyconfig` or `allnoconfig` or `defconfig`
* `--log` /path/to/filename
* `--debug true`

