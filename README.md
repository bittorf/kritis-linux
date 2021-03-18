### KRITIS Linux

* is a buildsystem for dynamic rebuilding of your systems
* throw away easy reproducible virtual machine images
* see [KRITIS](https://de.wikipedia.org/w/index.php?title=KRITIS)
* and [κριτής](https://en.wiktionary.org/wiki/%CE%BA%CF%81%CE%B9%CF%84%CE%AE%CF%82)
* still a work-in-progress
* supports musl, glibc, dietlibc and busybox/toybox/dash/bash

[![preview_buildmatrix_smoketest](http://intercity-vpn.de/kritis-linux/preview.png)](http://intercity-vpn.de/kritis-linux/)

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
git clone --depth 1 --branch v0.6 https://github.com/bittorf/kritis-linux.git

kritis-linux/ci_helper.sh \
	--arch x86_64 \
	--ramsize 384M \
	--kernel latest \
	--features busybox \
	--keep "/bin/busybox /bin/sh /bin/cat /usr/bin/setsid /bin/cttyhack" \
	--diradd /path/to/myfiles \
	--myinit script.xy \
	--maxwait 550 \
	--pattern "unittest_ready"
```

* above command checks out stable tag `v0.6` and
* builds `latest` stable 64bit `Linux` and adds `Busybox`
* removes all files/symlinks, except those in `--keep`
* adds directory in `--diradd` to initial ramdisk
* uses `script.xy` as `/sbin/init`
* starts qemu with `384mb` RAM and waits till `--pattern` shows up
* aborts the run, when over `550 seconds`

### more switches and options

* `--initrd` /path/to/initial-ramdisk.tgz
* `--kconfig` /path/to/.kernel-config
* `--arch x86_64` or `i386`,`uml`,`uml32`,`armel`,`armhf`,`arm64`,`m68k`,`or1k` (more planned)
* `--clib glibc` or `musl`,`dietlibc`
* `--features` `is,a,comma,separated,list`
  * e.g. `busybox`,`toybox`,`dash`,`bash`
  * e.g. `printk`,`sysfs`,`procfs`,`hostfs`
  * e.g. `menuconfig`,`kmenuconfig`,`speedup`
  * e.g. `net`,`wireguard`,`dropbear`,`iodine`,`icmptunnel`
  * e.g. `tinyconfig` or `allnoconfig` or `defconfig` or `config`
  * e.g. `CONFIG_SYMBOL_XY=y`
* `--log` /path/to/filename
* `--logtime false` for disabling timestamps
* `--onefile` for including `initrd` into kernel
* `--cmdline` for enforcing arguments to an `uml` kernel
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
needs ~20 seconds to compile kernel 3.18, which is ~423k compressed.  
  
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
		--arch uml32 \
		--ramsize 2G \
		--kernel 4.14.x \
		--initrd initrd.gz \
		--log /tmp/mylog.txt
```

### Advanced methods: hide your VM

Build a speed-optimized static compiled virtual machine,  
including network support and wireguard tools.  
and avoid the need for commandline arguments.  
Start it later as `/sbin/gеtty 38400 tty7` (with cyrillic small 'е')  

```
export EMBED_CMDLINE="quiet mem=64M panic=1 initrd=/tmp/cpio.gz eth0=slirp,FE:FD:01:02:03:04,/tmp/echo"
export DSTARCH=uml FAKEID='user@box.net' TTYPASS='peter80' SSHPASS='petra90'
./minilinux.sh latest printk sysfs procfs hostfs busybox bash net wireguard dropbear speedup upx

```
hint: make sure, you use a small/early PID,  
so a quick `ps aux` or `pstree` is not suspicious.  
```
#!/bin/sh
D=/usr/share/awk
N="$( date -R -r "$D/$( ls -1t $D | head -n1 )" )"
touch -d "$N" $D/cpio.awk
touch -d "$N" $D/echo.awk
cp $D/cpio.awk /tmp/cpio.tgz
cp $D/echo.awk /tmp/echo
read -r MAX </proc/sys/kernel/pid_max
echo 666 >/proc/sys/kernel/pid_max
while :; do $( :; ) &
test $! -gt ${LAST:-0} && LAST=$! || break
done 2>/dev/null; vmlinux &
rm /tmp/echo /tmp/cpio.tgz
echo $MAX >/proc/sys/kernel/pid_max
history -r && exit
```

### Release: smoketest

This test builds and testboots 252 images, which takes approximately 2.5 hours.  
Just extract like `sed -n '/^FULL/,/^done/p' README.md >release.sh && sh release.sh`,  
or use the call `CPU=1 ./minilinux.sh smoketest_for_release`.  

```
#!/bin/sh
FULL='printk procfs sysfs busybox bash dash net wireguard dropbear speedup'
TINY='printk'

for ARCH in armel armhf arm64 or1k m68k uml uml32 x86 x86_64; do
  for KERNEL in 3.18 3.18.140 3.19.8 4.0.9 4.1.52 4.2.8 4.3.6 4.4.261 4.9.261 4.14.225 4.19.180 5.4.105 5.10.23 5.11.6
    ID="${KERNEL}_${ARCH}" LOG="$PWD/log-$ID"
    LOG=$LOG-tiny BUILDID=$ID-tiny DSTARCH=$ARCH ./minilinux.sh $KERNEL "$TINY" autoclean
    LOG=$LOG-full BUILDID=$ID-full DSTARCH=$ARCH ./minilinux.sh $KERNEL "$FULL" autoclean
  done
done
```

### ToDo list
* CI examples: TravisCI, CircleCI
* fix `m68k' net/MACSONIC bringup
* debian-minimal testrun for deps
* builddir = mark_cache = no_backup
* api kernel+busybox+toybox+gcc... download/version
* different recipes?: minimal, net, compiler, net-compiler
* upload/api: good + bad things
* upload bootable images
* support for USB-sticks + hybrid ISO
* safe versions of all deps (cc, ld, libc)
* maybe support https://github.com/jart/cosmopolitan
* https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/bootconfig.rst
* measure sizes: https://events.static.linuxfound.org/sites/events/files/slides/slaballocators.pdf

### interesting CONFIG_SYMBOLS
```
CONFIG_STANDALONE=y
CONFIG_PREVENT_FIRMWARE_BUILD=y
# CONFIG_IDE is not set
CONFIG_SCSI=y
CONFIG_SCSI_MOD=y
CONFIG_DEBUG_KERNEL=y
# CONFIG_GPIOLIB is not set
```

### debug GNU-mes

```
KEEP_LIST='/bin/busybox /usr/bin/setsid /bin/cttyhack /bin/mount /bin/ash /bin/wget' \
INITRD_DIR_ADD=/home/user/live-bootstrap/sysa/tmp \
DSTARCH=i386 ./minilinux.sh latest busybox procfs sysfs printk net
```
