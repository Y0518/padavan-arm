#!/bin/sh

###############################################################################
# Sysupgrade Handler for Padavan on Arm (eMMC / UBI / NAND)
#
# Purpose: Verify and flash sysupgrade tar files to eMMC partitions,
#          UBI volumes, or raw NAND MTD partitions.
# Implementation based on OpenWrt's emmc_upgrade_tar / nand_upgrade_tar.
# Usage: sysupgrade-handler.sh <board_name> <sysupgrade_file> [kernel_device] [rootfs_device]
#
# Sysupgrade file format (tar-based):
#   sysupgrade-<board>/CONTROL  (Board info)
#   sysupgrade-<board>/kernel   (Kernel binary, FIT image)
#   sysupgrade-<board>/root     (Rootfs, squashfs)
#
# Storage type is auto-detected (reference: storage_main.sh):
#   EMMC     -> dd block write to /dev/mmcblk0p5 / p6
#   UBI      -> ubi tools: attach, rm/mk volumes, ubiupdatevol
#   NAND_MTD -> mtd_write to raw kernel / rootfs MTD partitions
###############################################################################

set -e

FW_UPGRADE_REBOOT="1"
# Configuration
BOARD_NAME="$1"
SYSUPGRADE_HEADER="sysupgrade-${BOARD_NAME}"
KERNEL_PART_DEFAULT="/dev/mmcblk0p5"  # eMMC Part 5: kernel
ROOTFS_PART_DEFAULT="/dev/mmcblk0p6"  # eMMC Part 6: rootfs
WORK_DIR="/tmp/sysupgrade_work"
LOG_FILE="/tmp/sysupgrade.log"
MIN_FILE_SIZE=$((2 * 1024 * 1024))  # 2 MB minimum

# UBI / NAND configuration
#
# zx-upgrade: UBI_MTD_PART must be the UBI we actually booted from.  ZX7981PG
# has TWO UBI slots -- "ubi"  (mtd5, factory OpenWrt) and "ubi2" (mtd6, us) --
# and attaching/flashing the wrong one silently clobbers the factory slot while
# the running system stays untouched.  Leave it EMPTY: flash_ubi() then takes
# the partition from /proc/cmdline's ubi.mtd= and refuses to write anything
# else.
UBI_MTD_PART=""              # empty = auto-detect from /proc/cmdline
UBI_MTD_FALLBACK="ubi2 ubi"  # tried in order when cmdline has no ubi.mtd=
UBI_KERN_VOL="kernel"        # UBI volume for kernel (FIT image)
UBI_ROOT_VOL="rootfs"        # UBI volume for rootfs (squashfs)
UBI_DATA_VOL="rootfs_data"   # UBI volume for overlay (auto-resize)
NAND_KERN_PART="kernel"      # raw NAND kernel MTD partition
NAND_ROOT_PART="rootfs"      # raw NAND rootfs MTD partition

# Status codes
SUCCESS=0
ERR_INVALID_FILE=1
ERR_VALIDATION_FAILED=2
ERR_FLASH_FAILED=3

STORAGE_TYPE=""

###############################################################################
# Utility Functions
###############################################################################

log_info() {
	local msg="$1"
	echo "[INFO] $msg" | tee -a "$LOG_FILE"
}

log_error() {
	local msg="$1"
	echo "[ERROR] $msg" | tee -a "$LOG_FILE" >&2
}

log_warn() {
	local msg="$1"
	echo "[WARN] $msg" | tee -a "$LOG_FILE"
}

log_success() {
	local msg="$1"
	echo "[SUCCESS] $msg" | tee -a "$LOG_FILE"
}

cleanup() {
	log_info "Cleaning up temporary files..."
	[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}

trap cleanup EXIT

###############################################################################
# Device detection
###############################################################################

detect_storage_type() {
	# CASE 1: eMMC (block device present)
	if [ -b "/dev/mmcblk0" ]; then
		STORAGE_TYPE="EMMC"
		return 0
	fi

	# CASE 2: UBI (kernel UBI subsystem active)
	if [ -d "/sys/class/ubi/ubi0" ] || grep -q "ubi" /proc/devices 2>/dev/null; then
		STORAGE_TYPE="UBI"
		return 0
	fi

	# CASE 3: raw NAND MTD partitions
	if grep -q "\"$NAND_KERN_PART\"" /proc/mtd 2>/dev/null && \
	   grep -q "\"$NAND_ROOT_PART\"" /proc/mtd 2>/dev/null; then
		STORAGE_TYPE="NAND_MTD"
		return 0
	fi

	STORAGE_TYPE="UNKNOWN"
	log_error "Cannot detect storage type (eMMC/UBI/NAND)"
	return 1
}

# Find MTD partition number by name (e.g. "ubi" -> 4)
find_mtd_index() {
	local part_name="$1"
	grep -i "\"$part_name\"" /proc/mtd 2>/dev/null | head -n1 | cut -d: -f1 | sed 's/mtd//'
}

# Find UBI device (e.g. ubi0) attached to a given MTD partition number
find_ubi_dev_by_mtd() {
	local mtdnum="$1"
	local ubidevdir cmtdnum
	for ubidevdir in /sys/class/ubi/ubi*; do
		[ -e "$ubidevdir/mtd_num" ] || continue
		cmtdnum="$(cat "$ubidevdir/mtd_num" 2>/dev/null)"
		[ "$mtdnum" = "$cmtdnum" ] || continue
		echo "$(basename "$ubidevdir")"
		return 0
	done
	return 1
}

# Find UBI volume device node (e.g. /dev/ubi0_0) by volume name
find_ubi_vol_dev() {
	local ubidev="$1"
	local volname="$2"
	local ubivoldir
	for ubivoldir in /sys/class/ubi/${ubidev}_*/; do
		[ -d "$ubivoldir" ] || continue
		if [ "$(cat "$ubivoldir/name" 2>/dev/null)" = "$volname" ]; then
			echo "/dev/$(basename "$ubivoldir")"
			return 0
		fi
	done
	return 1
}

# Find the sysfs dir of a UBI volume (e.g. /sys/class/ubi/ubi0_1).
find_ubi_vol_sysdir() {
	local ubidev="$1"
	local volname="$2"
	local d
	for d in /sys/class/ubi/${ubidev}_*/; do
		[ -d "$d" ] || continue
		if [ "$(cat "$d/name" 2>/dev/null)" = "$volname" ]; then
			echo "${d%/}"
			return 0
		fi
	done
	return 1
}

# zx-upgrade: which MTD partition did the kernel attach UBI from?
# /proc/cmdline carries e.g. "ubi.mtd=ubi2" (or a bare number).
detect_ubi_mtd_part() {
	sed -n 's/.*[ 	]ubi\.mtd=\([^ 	]*\).*/\1/p' /proc/cmdline 2>/dev/null | head -n1
}

# zx-upgrade: name-or-number -> MTD number
mtd_num_of() {
	local p="$1"
	case "$p" in
		'') return 1 ;;
		*[!0-9]*) find_mtd_index "$p" ;;
		*) echo "$p" ;;
	esac
}

# zx-upgrade: the MTD number we are allowed to write.
resolve_ubi_mtd() {
	local mtdnum cand
	if [ -n "$UBI_MTD_PART" ]; then
		mtdnum="$(mtd_num_of "$UBI_MTD_PART")"
		[ -n "$mtdnum" ] && { echo "$mtdnum"; return 0; }
	fi
	mtdnum="$(mtd_num_of "$(detect_ubi_mtd_part)")"
	[ -n "$mtdnum" ] && { echo "$mtdnum"; return 0; }
	for cand in $UBI_MTD_FALLBACK; do
		mtdnum="$(find_mtd_index "$cand")"
		[ -n "$mtdnum" ] && { echo "$mtdnum"; return 0; }
	done
	return 1
}

# zx-upgrade: pre-flight capacity check so an oversized image fails BEFORE the
# first erase (this board's rootfs volume has only ~100 KB of slack).
check_ubi_vol_fits() {
	local ubidev="$1"
	local volname="$2"
	local new_size="$3"
	local dir leb reserved avail need

	dir="$(find_ubi_vol_sysdir "$ubidev" "$volname")"
	if [ -z "$dir" ]; then
		log_warn "  $volname: volume absent, it will be created"
		return 0
	fi
	leb="$(cat /sys/class/ubi/$ubidev/eraseblock_size 2>/dev/null)"
	reserved="$(cat "$dir/reserved_ebs" 2>/dev/null)"
	avail="$(cat /sys/class/ubi/$ubidev/avail_eraseblocks 2>/dev/null)"
	[ -n "$leb" ] && [ -n "$reserved" ] || return 0

	need=$(( (new_size + leb - 1) / leb ))
	if [ "$need" -le "$reserved" ]; then
		log_info "  $volname: $new_size B -> $need EB (volume has $reserved) - OK"
		return 0
	fi
	if [ -n "$avail" ] && [ "$avail" -ge $((need - reserved)) ]; then
		log_warn "  $volname: $new_size B -> $need EB, volume has $reserved but $avail free - UBI must grow it"
		return 0
	fi

	log_error "  $volname: $new_size B -> $need EB, volume has $reserved and only $avail EB free"
	log_error "  image does not fit the current UBI layout:"
	log_error "    kernel  =>  $UBI_KERN_VOL"
	log_error "    rootfs  =>  $UBI_ROOT_VOL"
	log_error "  fix: enlarge the volume once from the U-Boot failsafe console"
	log_error "       (its httpd re-creates the volumes to fit the image),"
	log_error "       or shrink the rootfs (e.g. CONFIG_WIFI_FW_BIN_LOAD=y)."
	return 1
}

###############################################################################
# Validation Functions
###############################################################################

verify_header() {
	local file="$1"

	log_info "Verifying sysupgrade file header..."
	
	# Read the first 40 bytes to check for sysupgrade-cmcc_rax3000m-emmc-ubootmod header
	local header=$(head -c 40 "$file" 2>/dev/null)

	if echo "$header" | grep -q "^sysupgrade-"; then
		log_info "Custom sysupgrade header detected"
		
		# Extract header string until null byte or space
		local header_str=$(echo "$header" | cut -d' ' -f1)

		case "$header_str" in
			"$SYSUPGRADE_HEADER"*)
				log_success "Header validation passed: $header_str"
				return 0
				;;
			*)
				log_error "Header mismatch. Expected: $SYSUPGRADE_HEADER, Got: $header_str"
				return 1
				;;
		esac
	else
		# Try to detect if it's a tar file (after stripping header)
		log_info "Checking for tar content..."
		return 0
	fi
}

verify_tar_integrity() {
	local file="$1"

	log_info "Verifying tar file integrity..."
	
	# Check if it's a valid tar (skip custom header if present)
	if tar -tf "$file" > /dev/null 2>&1; then
		log_success "Tar file integrity check passed"
		return 0
	else
		# Try skipping the header bytes if present
		local header_len=${#SYSUPGRADE_HEADER}
		if dd if="$file" bs=1 skip=$((header_len + 1)) 2>/dev/null | \
		   tar -tf - > /dev/null 2>&1; then
			log_success "Tar file integrity check passed (after header skip)"
			return 0
		else
			log_error "Invalid tar file"
			return 1
		fi
	fi
}

verify_control_file() {
	local control_file="$1"

	log_info "Verifying CONTROL file..."

	if [ ! -f "$control_file" ]; then
		log_error "CONTROL file not found"
		return 1
	fi

	if grep -q "^BOARD=" "$control_file"; then
		local board=$(grep "^BOARD=" "$control_file" | cut -d'=' -f2)
		log_success "CONTROL file valid: BOARD=$board"
		return 0
	else
		log_error "Invalid CONTROL file format"
		return 1
	fi
}

verify_kernel_file() {
	local kernel_file="$1"

	log_info "Verifying kernel file..."

	if [ ! -f "$kernel_file" ]; then
		log_error "Kernel file not found"
		return 1
	fi

	local kernel_size=$(stat -c%s "$kernel_file" 2>/dev/null || stat -f%z "$kernel_file" 2>/dev/null)
	local min_size=$((1024 * 1024))  # 1 MB minimum
	local max_size=$((32 * 1024 * 1024))  # 32 MB maximum

	if [ "$kernel_size" -lt "$min_size" ]; then
		log_error "Kernel file too small: $kernel_size bytes (minimum: $min_size bytes)"
		return 1
	fi

	if [ "$kernel_size" -gt "$max_size" ]; then
		log_error "Kernel file too large: $kernel_size bytes (maximum: $max_size bytes)"
		return 1
	fi
	
	# Verify kernel magic (should start with uImage magic or gzip magic)
	local magic=$(od -An -N 4 -tx1 "$kernel_file" | tr -d ' ')
	case "$magic" in
		27051956)  # uImage magic (0x27051956)
			log_success "Kernel file valid (uImage format): $kernel_size bytes"
			return 0
			;;
		1f8b0808|1f8b0808*)  # gzip magic
			log_success "Kernel file valid (gzip compressed): $kernel_size bytes"
			return 0
			;;
        d00dfeed)  # fdt magic
            log_success "Kernel file valid (FDT format): $kernel_size bytes"
            return 0
            ;;
		*)
			log_warn "Unknown kernel format (magic: $magic), proceeding with caution"
			log_success "Kernel file size check passed: $kernel_size bytes"
			return 0
			;;
	esac
}

###############################################################################
# Extraction Functions
###############################################################################

extract_sysupgrade() {
	local file="$1"
	# zx-upgrade: only the small members are unpacked.  "root" is ~15 MB and is
	# streamed straight from the tar while flashing, so unpacking it would only
	# burn /tmp (48 MB tmpfs, and the 19.4 MB upload already sits there).
	local board_dir="$2"

	log_info "Extracting sysupgrade file for verification..."

	mkdir -p "$WORK_DIR"
	rm -rf "$WORK_DIR"/*

	if [ -n "$board_dir" ]; then
		tar -xf "$file" -C "$WORK_DIR" "$board_dir/CONTROL" "$board_dir/kernel" 2>>"$LOG_FILE" || {
			log_error "Failed to extract CONTROL/kernel from archive"
			return 1
		}
	else
		tar -xf "$file" -C "$WORK_DIR"
	fi

	if [ -d "$WORK_DIR" ] && [ "$(ls -A "$WORK_DIR")" ]; then
		log_success "Extraction successful (CONTROL + kernel only)"
		return 0
	else
		log_error "Extraction failed or empty archive"
		return 1
	fi
}

###############################################################################
# Flash Functions
###############################################################################

# --- eMMC: block-based dd write ---
flash_kernel() {
	local sysupgrade_file="$1"
	local kernel_device="$2"
	local board_dir="$3"

	log_info "Flashing kernel to $kernel_device..."
	
	# Verify device exists
	if [ ! -b "$kernel_device" ] && [ ! -c "$kernel_device" ]; then
		log_error "Device $kernel_device not found or not a block device"
		return 1
	fi
	
	# Check if kernel exists in tar
	if ! tar -tf "$sysupgrade_file" "${board_dir}/kernel" > /dev/null 2>&1; then
		log_warn "Kernel file not found in sysupgrade archive"
		return 0
	fi

	log_info "Writing kernel from sysupgrade tar..."
	
	# Extract and flash kernel directly from tar
	# Use bs=512 for standard sector-based flashing
	local kernel_blocks=$(tar -xf "$sysupgrade_file" "${board_dir}/kernel" -O 2>/dev/null | \
	                       dd of="$kernel_device" bs=512 2>&1 | grep "records out" | cut -d' ' -f1)

	if [ -z "$kernel_blocks" ]; then
		log_error "Failed to flash kernel"
		return 1
	fi

	log_success "Kernel flashed successfully ($kernel_blocks blocks)"
	sync
	sleep 1

	return 0
}

flash_rootfs() {
	local sysupgrade_file="$1"
	local rootfs_device="$2"
	local board_dir="$3"
	
	# Check if rootfs exists in tar
	if ! tar -tf "$sysupgrade_file" "${board_dir}/root" > /dev/null 2>&1; then
		log_warn "Rootfs file not found in sysupgrade archive"
		return 0
	fi

	log_info "Flashing rootfs to $rootfs_device..."
	
	# Verify device exists
	if [ ! -b "$rootfs_device" ] && [ ! -c "$rootfs_device" ]; then
		log_error "Device $rootfs_device not found or not a block device"
		return 1
	fi

	log_info "Writing rootfs from sysupgrade tar..."
	
	# Extract and flash rootfs directly from tar
	# Use bs=512 for standard sector-based flashing
	local rootfs_blocks=$(tar -xf "$sysupgrade_file" "${board_dir}/root" -O 2>/dev/null | \
	                       dd of="$rootfs_device" bs=512 2>&1 | grep "records out" | cut -d' ' -f1)

	if [ -z "$rootfs_blocks" ]; then
		log_error "Failed to flash rootfs"
		return 1
	fi

	log_success "Rootfs flashed successfully ($rootfs_blocks blocks)"
	sync
	sleep 1

	return 0
}

flash_emmc() {
	local sysupgrade_file="$1"
	local kernel_device="$2"
	local rootfs_device="$3"
	local board_dir="$4"

	flash_kernel "$sysupgrade_file" "$kernel_device" "$board_dir" || return 1
	flash_rootfs "$sysupgrade_file" "$rootfs_device" "$board_dir" || return 1

	return 0
}

# --- UBI: A/B volume update (zx-upgrade-2) ---
#
# The volume that backs the running / cannot be written: UBI_IOCVOLUP requires
# exclusive access (cdev.c get_exclusive()) and ubiblock holds a read
# reference.  So write the new firmware into the *unused* spare volumes
# kernel_b/rootfs_b and swap the names afterwards -- rename_volumes() uses
# UBI_METAONLY, which readers do not block.
#
# Sizes are in eraseblocks; everything is checked before the first erase.

ubi_vol_eb() {   # <ubidev> <name> -> reserved_ebs, empty if absent
	local d
	d="$(find_ubi_vol_sysdir "$1" "$2")" || return 1
	cat "$d/reserved_ebs" 2>/dev/null
}

ubi_vol_id() {   # <ubidev> <name> -> vol_id (from the ubiX_N dir name)
	local d
	d="$(find_ubi_vol_sysdir "$1" "$2")" || return 1
	echo "${d##*_}"
}

run_ubirmvol() {   # <ubidev> <name>
	local vid
	vid="$(ubi_vol_id "$1" "$2")" || return 0
	log_info "  removing spare volume '$2' (vol_id $vid) to free EBs..."
	ubirmvol "/dev/$1" -n "$vid" 2>>"$LOG_FILE" || {
		log_error "cannot remove volume '$2'"
		return 1
	}
	sync
	return 0
}

# Wait until UBI has reclaimed at least <need> eraseblocks.
wait_ebs() {   # <ubidev> <need> <tries>
	local i a tries="$3"
	i=0
	while [ "$i" -lt "$tries" ]; do
		a="$(cat /sys/class/ubi/$1/avail_eraseblocks 2>/dev/null)"
		[ -n "$a" ] && [ "$a" -ge "$2" ] && return 0
		sync
		sleep 1
		i=$((i + 1))
	done
	return 1
}

# Make room for the spare pair.
#
# The spare rootfs has to live somewhere and UBI has no free eraseblocks: the
# only holder is padavan's overlay volume rootfs_data (271 EB, holding nothing
# but firmware defaults).  It cannot be shrunk while keeping its filesystem
# (UBIFS keeps its LPT at the end of the volume, and UBI cannot shrink a
# volume in place anyway), so it is given up -- once -- and padavan continues
# without persistent /etc/storage.  nvram settings are NOT affected.
free_space_for_spare() {
	local ubidev="$1" want_free="$2"
	local dir dev cur avail

	avail="$(cat /sys/class/ubi/$ubidev/avail_eraseblocks)"
	[ "$avail" -ge "$want_free" ] && return 0

	dir="$(find_ubi_vol_sysdir "$ubidev" "$UBI_DATA_VOL")" || {
		log_error "  need $want_free EB but only $avail are free, and $UBI_DATA_VOL is gone"
		return 1
	}
	dev="/dev/$(basename "$dir")"
	cur="$(cat "$dir/reserved_ebs")"

	log_warn "  Only $avail EB free, the spare pair needs $want_free EB."
	log_warn "  Giving up the padavan overlay volume '$UBI_DATA_VOL' ($cur EB)."
	log_warn "  NOTE: /etc/storage (sample scripts + generated ssh host keys) will"
	log_warn "        not persist any more.  nvram settings are unaffected."
	log_warn "        This is a one-time trade to enable WebUI upgrades."

	if grep -q " /mnt/rwdata " /proc/mounts 2>/dev/null; then
		log_info "  unmounting padavan storage..."
		umount "/mnt/rwdata" 2>>"$LOG_FILE" || umount -l "/mnt/rwdata" 2>>"$LOG_FILE" || true
		sync
		sleep 2
	fi

	ubirmvol "/dev/$ubidev" -n "${dir##*_}" 2>>"$LOG_FILE" || {
		log_error "cannot remove $UBI_DATA_VOL"; return 1; }

	if ! wait_ebs "$ubidev" "$want_free" 60; then
		log_error "UBI did not reclaim $want_free eraseblocks in time"
		return 1
	fi
	log_info "  $UBI_DATA_VOL removed; free EBs now $(cat /sys/class/ubi/$ubidev/avail_eraseblocks)"
	return 0
}

ubi_update_from_tar() {   # <file> <tar member> <vol dev> <bytes>
	log_info "  writing $(basename "$3") from $2 ($4 bytes)..."
	tar -xOf "$1" "$2" | ubiupdatevol "$3" -s "$4" - 2>>"$LOG_FILE" || {
		log_error "write to $3 failed"
		return 1
	}
	return 0
}

flash_ubi() {
	local sysupgrade_file="$1"
	local board_dir="$2"

	# zx-upgrade: pick the UBI we booted from and refuse anything else.
	local mtdnum boot bootnum
	mtdnum="$(resolve_ubi_mtd)"
	if [ -z "$mtdnum" ]; then
		log_error "Cannot find the UBI MTD partition (cmdline ubi.mtd='$(detect_ubi_mtd_part)', tried: $UBI_MTD_PART $UBI_MTD_FALLBACK)"
		return 1
	fi
	boot="$(detect_ubi_mtd_part)"
	bootnum="$(mtd_num_of "$boot")"
	if [ -n "$bootnum" ] && [ "$bootnum" != "$mtdnum" ]; then
		log_error "Refusing to flash /dev/mtd$mtdnum: this system booted from /dev/mtd$bootnum (ubi.mtd=$boot)"
		return 1
	fi
	log_info "Boot UBI partition: ubi.mtd=$boot -> /dev/mtd$mtdnum"

	local ubidev=$(find_ubi_dev_by_mtd "$mtdnum")
	if [ -z "$ubidev" ]; then
		log_info "Attaching UBI to /dev/mtd$mtdnum..."
		ubiattach -m "$mtdnum" 2>/dev/null || true
		ubidev=$(find_ubi_dev_by_mtd "$mtdnum")
		[ -z "$ubidev" ] && { log_error "Cannot attach UBI"; return 1; }
	fi
	log_info "Using UBI device $ubidev"

	local leb=$(cat /sys/class/ubi/$ubidev/eraseblock_size)

	# ---- what are we writing, and how big does the spare have to be? ----
	local kernel_length="" rootfs_length=""
	if tar -tf "$sysupgrade_file" "$board_dir/kernel" > /dev/null 2>&1; then
		kernel_length=$(tar -xOf "$sysupgrade_file" "$board_dir/kernel" 2>/dev/null | wc -c)
	fi
	if tar -tf "$sysupgrade_file" "$board_dir/root" > /dev/null 2>&1; then
		rootfs_length=$(tar -xOf "$sysupgrade_file" "$board_dir/root" 2>/dev/null | wc -c)
	fi
	if [ -z "$kernel_length" ] || [ "$kernel_length" -le 0 ]; then
		log_error "no kernel in archive"; return 1
	fi

	local need_k=$(( (kernel_length + leb - 1) / leb ))
	local need_r=0
	[ -n "$rootfs_length" ] && [ "$rootfs_length" -gt 0 ] && 		need_r=$(( (rootfs_length + leb - 1) / leb ))

	log_info "Pre-flight capacity check (1 EB = $leb bytes):"
	log_info "  kernel: $kernel_length B -> $need_k EB"
	[ "$need_r" -gt 0 ] && log_info "  rootfs: $rootfs_length B -> $need_r EB"

	if [ "${SYSUPGRADE_DRYRUN:-0}" = "1" ]; then
		log_info "DRY RUN: no erases/writes performed."
		log_info "  would write $board_dir/kernel -> $ubidev/$UBI_KERN_VOL (spare ${UBI_KERN_VOL}_b)"
		[ "$need_r" -gt 0 ] && 		log_info "  would write $board_dir/root   -> $ubidev/$UBI_ROOT_VOL (spare ${UBI_ROOT_VOL}_b)"
		log_info "  would then atomically rename the pair and reboot"
		return 0
	fi

	# ---- free the spare pair, shrinking rootfs_data if we must ----
	local KSP="${UBI_KERN_VOL}_b" RSP="${UBI_ROOT_VOL}_b"
	local need_free=$((need_k + need_r)) got

	for v in "$KSP" "$RSP"; do
		if [ -n "$(ubi_vol_eb "$ubidev" "$v")" ]; then
			got=$(ubi_vol_eb "$ubidev" "$v")
			if [ "$v" = "$KSP" ] && [ "$got" -lt "$need_k" ]; then
				run_ubirmvol "$ubidev" "$v" || return 1
			elif [ "$v" = "$RSP" ] && [ "$need_r" -gt 0 ] && [ "$got" -lt "$need_r" ]; then
				run_ubirmvol "$ubidev" "$v" || return 1
			fi
		fi
	done

	local avail=$(cat /sys/class/ubi/$ubidev/avail_eraseblocks)
	if [ "$avail" -lt "$need_free" ]; then
		log_warn "Only $avail EB free, the spare pair needs $need_free EB."
		free_space_for_spare "$ubidev" "$need_free" || return 1
		avail=$(cat /sys/class/ubi/$ubidev/avail_eraseblocks)
	fi
	if [ "$avail" -lt "$need_free" ]; then
		log_error "Still only $avail EB free but $need_free EB are needed."
		log_error "image too big for this UBI layout - shrink the rootfs"
		log_error "(e.g. CONFIG_WIFI_FW_BIN_LOAD=y) and try again."
		return 1
	fi
	log_info "Free EBs: $avail (need $need_free) - OK"

	# ---- create + fill the spare pair (nothing of ours is mounted here) ----
	ubimkvol "/dev/$ubidev" -N "$KSP" -s "$((need_k * leb))" 2>>"$LOG_FILE" || {
		log_error "cannot create $KSP"; return 1; }
	ubi_update_from_tar "$sysupgrade_file" "$board_dir/kernel" \
		"$(find_ubi_vol_dev "$ubidev" "$KSP")" "$kernel_length" || return 1

	if [ "$need_r" -gt 0 ]; then
		ubimkvol "/dev/$ubidev" -N "$RSP" -s "$((need_r * leb))" 2>>"$LOG_FILE" || {
			log_error "cannot create $RSP"; return 1; }
		ubi_update_from_tar "$sysupgrade_file" "$board_dir/root" \
			"$(find_ubi_vol_dev "$ubidev" "$RSP")" "$rootfs_length" || return 1
	fi

	# ---- switch over: swap the names atomically ----
	log_info "Swapping volume names (atomic rename)..."
	local pairs=""
	if [ "$need_r" -gt 0 ]; then
		pairs="$UBI_KERN_VOL $KSP $KSP $UBI_KERN_VOL $UBI_ROOT_VOL $RSP $RSP $UBI_ROOT_VOL"
	else
		pairs="$UBI_KERN_VOL $KSP $KSP $UBI_KERN_VOL"
	fi
	if ! ubirename "/dev/$ubidev" $pairs 2>>"$LOG_FILE"; then
		log_error "ubirename failed - the new firmware is written to $KSP/$RSP"
		log_error "but not active; the running firmware is untouched."
		return 1
	fi
	log_success "Switched to the new volumes; $UBI_ROOT_VOL is now the new rootfs"

	sync
	return 0
}
# --- Raw NAND MTD: mtd_write ---
flash_nand_mtd() {
	local sysupgrade_file="$1"
	local board_dir="$2"

	# Kernel
	if tar -tf "$sysupgrade_file" "$board_dir/kernel" > /dev/null 2>&1; then
		local kernel_mtd=$(find_mtd_index "$NAND_KERN_PART")
		if [ -z "$kernel_mtd" ]; then
			log_error "Cannot find kernel MTD partition '$NAND_KERN_PART'"
			return 1
		fi
		log_info "Writing kernel to mtd$kernel_mtd ($NAND_KERN_PART)..."
		tar -xOf "$sysupgrade_file" "$board_dir/kernel" | mtd_write write - "$NAND_KERN_PART"
	fi

	# Rootfs
	if tar -tf "$sysupgrade_file" "$board_dir/root" > /dev/null 2>&1; then
		local rootfs_mtd=$(find_mtd_index "$NAND_ROOT_PART")
		if [ -z "$rootfs_mtd" ]; then
			log_error "Cannot find rootfs MTD partition '$NAND_ROOT_PART'"
			return 1
		fi
		log_info "Writing rootfs to mtd$rootfs_mtd ($NAND_ROOT_PART)..."
		tar -xOf "$sysupgrade_file" "$board_dir/root" | mtd_write write - "$NAND_ROOT_PART"
	fi

	sync
	return 0
}

###############################################################################
# Main Function
###############################################################################

main() {
	local config_board_comp="$1"
	local sysupgrade_file="$2"
	local kernel_device="${3:-$KERNEL_PART_DEFAULT}"
	local rootfs_device="${4:-$ROOTFS_PART_DEFAULT}"

	# Initialize log
	: > "$LOG_FILE"

	log_info "==================================================================="
	log_info "Padavan on Arm Sysupgrade Handler"
	log_info "==================================================================="
	log_info "Input file: $sysupgrade_file"

	# Validate arguments
	if [ -z "$sysupgrade_file" ]; then
		log_error "Usage: $0 <sysupgrade_file> [kernel_device] [rootfs_device]"
		return 1
	fi

	if [ ! -f "$sysupgrade_file" ]; then
		log_error "Sysupgrade file not found: $sysupgrade_file"
		return 1
	fi

	# Check file size
	local file_size=$(stat -c%s "$sysupgrade_file" 2>/dev/null || stat -f%z "$sysupgrade_file" 2>/dev/null)
	if [ "$file_size" -lt "$MIN_FILE_SIZE" ]; then
		log_error "File size too small: $file_size bytes (minimum: $MIN_FILE_SIZE bytes)"
		return 1
	fi
	log_info "File size: $file_size bytes - OK"

	# Detect storage type
	detect_storage_type || return 1
	log_info "Detected storage type: $STORAGE_TYPE"

	case "$STORAGE_TYPE" in
		EMMC)
			log_info "Kernel device: $kernel_device"
			log_info "Rootfs device: $rootfs_device"
			;;
		UBI)
			log_info "UBI MTD partition: $UBI_MTD_PART"
			log_info "UBI volumes: $UBI_KERN_VOL / $UBI_ROOT_VOL / $UBI_DATA_VOL"
			;;
		NAND_MTD)
			log_info "Kernel MTD partition: $NAND_KERN_PART"
			log_info "Rootfs MTD partition: $NAND_ROOT_PART"
			;;
	esac

	# Run validation checks
	verify_header "$sysupgrade_file" || return 1
	verify_tar_integrity "$sysupgrade_file" || return 1

	# Detect board directory from tar (OpenWrt method)
	# Should be in format: sysupgrade-<board>/
	local board_dir=$(tar -tf "$sysupgrade_file" | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}

	if [ -z "$board_dir" ]; then
		log_error "Cannot find board directory in sysupgrade archive"
		return 1
	fi

	log_info "Board directory detected: $board_dir"

	# Verify CONTROL file exists
	if ! tar -tf "$sysupgrade_file" "${board_dir}/CONTROL" > /dev/null 2>&1; then
		log_error "CONTROL file not found in sysupgrade archive"
		return 1
	fi

	# Extract and verify CONTROL file
	extract_sysupgrade "$sysupgrade_file" "$board_dir" || return 1
	local control_file="$WORK_DIR/$board_dir/CONTROL"
	verify_control_file "$control_file" || return 1


	local kernel_file="$WORK_DIR/$board_dir/kernel"
	verify_kernel_file "$kernel_file" || return 1


	# Flash according to detected storage type
	case "$STORAGE_TYPE" in
		EMMC)
			flash_emmc "$sysupgrade_file" "$kernel_device" "$rootfs_device" "$board_dir" || return 1
			;;
		UBI)
			flash_ubi "$sysupgrade_file" "$board_dir" || return 1
			;;
		NAND_MTD)
			flash_nand_mtd "$sysupgrade_file" "$board_dir" || return 1
			;;
		*)
			log_error "Unsupported storage type: $STORAGE_TYPE"
			return 1
			;;
	esac

	# Post-flash operations
	log_info "Performing post-flash operations..."
	log_info "Syncing filesystem..."
	sync
	sleep 1

	log_info "==================================================================="
	log_success "Sysupgrade completed successfully!"
	log_info "==================================================================="
	log_info "Log file: $LOG_FILE"

	if [ "${SYSUPGRADE_DRYRUN:-0}" = "1" ]; then
		log_warn "DRY RUN: skipping reboot."
		return 0
	fi

	# Optional: Reboot if specified via environment variable
	if [ "$FW_UPGRADE_REBOOT" = "1" ]; then
		log_info "Rebooting now to boot the new firmware..."
		sync
		sleep 1
		# zx-upgrade: bypass padavan's init -- its /sbin/init does not handle
		# SIGTERM-as-reboot reliably, and we want the shortest possible window
		# after replacing the volume that backs the running /.
		reboot -f 2>/dev/null || {
			echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
			echo b > /proc/sysrq-trigger 2>/dev/null
		}
		sleep 5
		# last resort: direct syscall via busybox
		/sbin/reboot -f 2>/dev/null
		sleep 5
		echo b > /proc/sysrq-trigger 2>/dev/null
	else
		log_info "Upgrade complete. Reboot required to apply new firmware."
	fi

	return 0
}

# Execute main function
main "$@"
exit $?