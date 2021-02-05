### KRITIS Linux

* is a buildsystem for dynamic rebuilding of your systems
* see [KRITIS](https://de.wikipedia.org/w/index.php?title=KRITIS)
* still a work-in-progress
* supports musl, glibc, dietlibc and busybox/toybox

### Syntax

* get help with, e.g. `./minilinux.sh`
* make a linux with e.g. `./minilinux.sh latest`

### CI: build and run QEMU instance

For continuous integration of your code, use scripts like these, for deploy a minimal Linux-VM.

#### CI: example one

```
git clone --depth 1 https://github.com/bittorf/kritis-linux.git

kritis-linux/ci_helper.sh \
	--kernel 4.4.215 \
	--features busybox,procfs,sysfs \
	--diradd /path/to/myfiles
```

* above command builds 64bit `Linux v4.4.215` and adds `Busybox`
* also adds support for the kernels `procfs` and `sysfs` and
* adds your files to the initital ramdisk, eventually with a `init.user`,
* which is executed directly after our minimal init
* note: you can use `--kernel 4.4.x` for latest 4.4-branch

#### CI: example two

```
git clone --depth 1 --branch v0.4 https://github.com/bittorf/kritis-linux.git

kritis-linux/ci_helper.sh \
	--arch x86_64 \
	--ramsize 384M \
	--kernel latest \
	--features busybox \
	--keep "/bin/busybox /bin/sh /bin/cat" \
	--diradd /path/to/myfiles \
	--myinit script.xy \
	--maxwait 550 \
	--pattern "unittest_ready"
```

* above command checks out stable tag `v0.4` and
* builds `latest` stable 64bit `Linux` and adds `Busybox`
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
  * e.g. `wireguard`,
  * e.g. `tinyconfig` or `allnoconfig` or `defconfig` or `config`
* `--log` /path/to/filename
* `--logtime false` for disabling timestamps
* `--onefile` for including `initrd` into kernel
* `--debug true`

### kernel configuration and features

Default is building `make tinyconfig` and change some switches:

* add support for a gzipped initial ramdisk
  * `CONFIG_BLK_DEV_INITRD=y`
    * `CONFIG_RD_GZIP=y`
* add support for ELF binaries and shebang
  * `CONFIG_BINFMT_ELF=y`
  * `CONFIG_BINFMT_SCRIPT=y`
* add support for /dev/null
  * `CONFIG_DEVTMPFS=y`
  * `CONFIG_DEVTMPFS_MOUNT=y`
* add support for a serial console
  * `CONFIG_TTY=y`
  * `CONFIG_SERIAL_8250=y`
  * `CONFIG_SERIAL_8250_CONSOLE=y`
* disable most of kernel debug messages
  * `# CONFIG_PRINTK` is not set`
* disable support for swapping
  * `# CONFIG_SWAP is not set`

Kernels with less features are smaller and compile faster, so it  
needs ~20 seconds to compile kernel 3.18, which is ~450k compressed.  
  
If this does not fit to your needs, you can enable stuff  
using `--features` or just provide your own `--kconfig`  

### CI example for github action

create a file `.github/workflows/action.yml` like this:

```
on: [push, pull_request]
name: bootstrap
jobs:
  simulate_task:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: run
        run: |
          git clone --depth 1 https://github.com/bittorf/kritis-linux.git
          kritis-linux/ci_helper.sh \
		--arch uml \
		--features 32bit \
		--ramsize 2G \
		--kernel 4.14.x \
		--initrd initrd.gz \
		--log /tmp/mylog.txt
```

### ToDo list
* CI examples: TravisCI, CircleCI
* debian-minimal testrun for deps
* builddir = mark_cache = no_backup
* speedcheck: CONFIG_BASE_FULL=y + optimize_for_speed
* net: nameserver?
* api kernel+busybox+toybox+gcc... download/version
* different recipes?: minimal, net, compiler, net-compiler
* which programs where called? hash?
* upload/api: good + bad things
* upload bootable images
* safe versions of all deps (cc, ld, libc)
* filesizes
* needed space
* measure sizes: https://events.static.linuxfound.org/sites/events/files/slides/slaballocators.pdf
* add option for size/performance:
  * `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y`
  * `# CONFIG_CC_OPTIMIZE_FOR_SIZE is not set`
* tinyconfig only available for 3.17-rc1+
* add test and build-matrix: all combinations of
  * kernel/busybox/toybox/dash/libc/32bit/64bit/archs

