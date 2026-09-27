__Run on ZX7981PG (MT7981B / 256 MB RAM / 128 MiB SPI-NAND)__

This branch ports the Padavan ARM build to the **ZX7981PG**. It is derived from the
upstream RAX3000M port by Lan Bing; the ZX7981PG board support (DTS, board config),
the U-Boot/ATF bring-up and the MTK closed-source wifi stack (`mt_wifi`) are added here.

All device specific binaries live in ZX7981PG_flash_bins folder:

```
ZX7981PG_flash_bins/
  mt7981-zx7981pg-bl2.bin         ATF v2.7 BL2       - only for uartboot recovery, normally keep the factory one
  mt7981-zx7981pg-fip.bin         U-Boot 2025.07 + ATF v2.7 FIP (patched, see notes)
  zx7981pg_boot_log               captured boot log  - BL2 -> U-Boot -> kernel -> userspace
  sysupgrade_zx7981pg_..._zx24-...bin   ready to flash firmware image
```

1. Flash the FIP

**Only the FIP has to be flashed.** The factory BL2 already on this device is ATF v2.7,
the same version the FIP is built against, so the new FIP boots under the untouched BL2.
Do **not** flash the BL2 unless the device is already bricked - a bad BL2 can only be
recovered with an SPI-NAND programmer.

The easiest path is the U-Boot web failsafe (no uartboot, no BL2 risk):

```
serial console (ttyS0, 115200n1):
  press a key inside the 1 s "Hit any key to stop autoboot" window to enter the menu.
  The menu is arrow-key driven - use REAL keys. A scripted "ESC [ B" is interpreted
  as "ESC to quit" and drops you out of the menu.

  *** U-Boot Boot Menu ***
  1. Startup system (Default)      6. Upgrade bootloader only
  2. Upgrade firmware              7. Upgrade single image
  3. Upgrade ATF BL2               8. Load image
  4. Upgrade ATF FIP               9. Start Web failsafe
  5. Upgrade ATF BL31 only         a. Change boot configuration

  menu item 9:  Start Web failsafe

  FIP      ->  http://192.168.1.1/uboot.html    (form field: fip)
  firmware ->  http://192.168.1.1/              (form field: firmware)
```

2. Flash the sysupgrade image

Through the padavan WebUI (System -> Firmware Upgrade), or through the U-Boot web
failsafe page above. Use the WebUI for day to day upgrades: it does an **A/B upgrade
inside the single `ubi` partition**. The handler writes the spare pair `kernel_b` /
`rootfs_b`, atomically swaps the volume names with `ubirename` and reboots. Nothing of
the running firmware is touched before the rename succeeds, so a failure just means
"not flashed, the old firmware still boots".

Note that upgrading through the **U-Boot** web failsafe page is not an A/B upgrade - it
removes `kernel` / `rootfs` / `rootfs_data` and recreates them, which also wipes the
overlay. Prefer the padavan WebUI.

__Partition layout with the ZX7981PG (single 114 MiB ubi)__

The layout follows the `mtdparts` of the new U-Boot - a single 114 MiB `ubi`, not the
7 partition factory layout:

```
CONFIG_MTDPARTS_DEFAULT="nmbm0:1024k(bl2),512k(u-boot-env),2048k(factory),2048k(fip),114M(ubi)"
```

```
[    0.859151] 5 fixed-partitions partitions found on MTD device spi0.0
[    0.865788] Creating 5 MTD partitions on "spi0.0":
[    0.870593] 0x000000000000-0x000000100000 : "BL2"
[    0.876400] 0x000000100000-0x000000180000 : "u-boot-env"
[    0.882478] 0x000000180000-0x000000380000 : "Factory"
[    0.889643] 0x000000380000-0x000000580000 : "FIP"
[    0.896205] 0x000000580000-0x000007780000 : "ubi"
```

```
> cat /proc/mtd
dev:    size   erasesize  name
mtd0: 00100000 00020000 "BL2"
mtd1: 00080000 00020000 "u-boot-env"
mtd2: 00200000 00020000 "Factory"
mtd3: 00200000 00020000 "FIP"
mtd4: 07200000 00020000 "ubi"
```

```
[    2.761475] ubi0: attached mtd4 (name "ubi", size 114 MiB)
[    2.787608] ubi0: good PEBs: 912, bad PEBs: 0, corrupted PEBs: 0
[    2.809160] ubi0: available PEBs: 601, total reserved PEBs: 311, PEBs reserved for bad PEB handling: 20
[    2.821461] block ubiblock0_1: created from ubi0:1(rootfs)
[    2.830043] ubiblock: device ubiblock0_1 (rootfs) set to be root filesystem
```

Boot args come from `chosen/bootargs` in the DTS (this U-Boot passes no arguments of
its own), and the root is picked by volume name, so nothing has to be passed in:

```
[    0.000000] Kernel command line: console=ttyS0,115200n1 loglevel=8 ubi.mtd=ubi rootfstype=squashfs rootwait
```

__Board notes (things that cost time to figure out)__

- **The `ubi` size must be a multiple of the erase block (128 KiB).** The correct value
  is `0x7200000` (119537664 = 912 erase blocks). `0x71F0000` is *not* divisible and the
  kernel then prints `partition "ubi" doesn't end on an erase/write block -- force
  read-only`, clears `MTD_WRITEABLE`, and `drivers/mtd/ubi/build.c` turns the **whole UBI
  read-only** - every write, including the WebUI upgrade, then fails with EROFS.
- **`rootfs_data` is created with a fixed 16 MiB** by the patched
  `board/mediatek/common/mtd_helper.c`. The stock behaviour (size 0 + auto_resize) hands
  the whole remainder of the UBI to `rootfs_data`, leaving 0 available erase blocks: no
  reserve for bad block handling, and the A/B upgrade has to delete the overlay before
  every flash. With the fix there are 601 free EB and `/etc/storage` survives.
- **`u-boot-env` is left alone on purpose.** The partition is occupied by the padavan
  nvram, so U-Boot reports `bad CRC, using default environment` and keeps its own env in
  the ubi volumes `ubootenv` / `ubootenv2`. That way no nvram setting is lost. U-Boot is
  therefore driven by its built-in default environment + the boot menu.
- **`CONFIG_MTK_DUAL_BOOT` is disabled** in this U-Boot. The boot decision is purely name
  based: `boot_from_ubi()` reads the volume called `kernel`, and the kernel picks its root
  by the volume name `rootfs` (`ubiblock_create_auto_rootfs()`). That is exactly what the
  padavan `ubirename` based A/B upgrade relies on, so the two stay compatible. The one
  thing to keep in mind is that with dual_boot off there is **no automatic rollback** - the
  previous firmware stays intact in `kernel_b` / `rootfs_b`, so swap the names back
  manually if the new one does not boot.
- **The WAN port has to be named `wan`.** MT7981 + MT7531 uses DSA, every physical port is
  its own netdev (`lan2` / `lan3` / `wan`) and there is no `eth1`, so `IFNAME_WAN` alone is
  not enough - see the `padavan-arm-board-port` skill notes.
- The wifi stack is the MTK closed-source driver (`mt_wifi`, built as a module because its
  initcalls run before the rootfs is mounted); the DTS / clock / firmware details are in the
  `padavan-mtwifi-port` skill notes.
- IPv6 on the LAN side needs DHCPv6-PD from the upstream. This port has the stock padavan
  behaviour: no PD, no LAN IPv6 (the router itself still gets a global address via SLAAC).

__Disabled Path__

- mips-toolchain
- trunk/libc/uclib
- trunk/linux-4.4.198

__Introduced Path__

- aarch64-gcc-musl
- trunk/linux-5.15.167


*Disclaimer: This is an experimental porting version by Lan Bing.
The ZX7981PG board support and the MTK closed-source wifi port are experimental as well.
Use at your own risk.*
