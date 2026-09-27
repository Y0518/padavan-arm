#!/bin/sh

mount -t proc proc /proc
mount -t sysfs sysfs /sys
[ -d /proc/bus/usb ] && mount -t usbfs usbfs /proc/bus/usb

#size_tmp="24M"
size_tmp="48M"
size_var="4M"
size_etc="6M"

if [ "$1" == "-l" ] ; then
	size_tmp="8M"
	size_var="1M"
fi

mount -t tmpfs tmpfs /dev   -o size=8K
mount -t tmpfs tmpfs /etc   -o size=$size_etc,noatime
mount -t tmpfs tmpfs /home  -o size=1M
mount -t tmpfs tmpfs /media -o size=8K
mount -t tmpfs tmpfs /mnt   -o size=8K
mount -t tmpfs tmpfs /tmp   -o size=$size_tmp
mount -t tmpfs tmpfs /var   -o size=$size_var

mkdir /dev/pts
mount -t devpts devpts /dev/pts

mount -t debugfs debugfs /sys/kernel/debug

ln -sf /etc_ro/mdev.conf /etc/mdev.conf
mdev -s

# create dirs
mkdir -p -m 777 /var/lock
mkdir -p -m 777 /var/locks
mkdir -p -m 777 /var/private
mkdir -p -m 700 /var/empty
mkdir -p -m 777 /var/lib
mkdir -p -m 777 /var/log
mkdir -p -m 777 /var/run
mkdir -p -m 777 /var/tmp
mkdir -p -m 777 /var/spool
mkdir -p -m 777 /var/lib/misc
mkdir -p -m 777 /var/state
mkdir -p -m 777 /var/state/parport
mkdir -p -m 777 /var/state/parport/svr_statue
mkdir -p -m 777 /tmp/var
mkdir -p -m 777 /tmp/hashes
mkdir -p -m 777 /tmp/modem
mkdir -p -m 777 /tmp/rc_notification
mkdir -p -m 777 /tmp/rc_action_incomplete
mkdir -p -m 700 /home/root
mkdir -p -m 700 /home/root/.ssh
mkdir -p -m 755 /etc/storage
mkdir -p -m 755 /etc/ssl
mkdir -p -m 755 /etc/Wireless
mkdir -p -m 750 /etc/Wireless/RT2860
mkdir -p -m 750 /etc/Wireless/iNIC

# extract storage files
# mtd_storage.sh load
storage_main.sh load

touch /etc/resolv.conf

if [ -f /etc_ro/openssl.cnf ]; then
	cp -f /etc_ro/openssl.cnf /etc/ssl
fi

# create symlinks
ln -sf /home/root /home/admin
ln -sf /proc/mounts /etc/mtab
ln -sf /etc_ro/ethertypes /etc/ethertypes
ln -sf /etc_ro/protocols /etc/protocols
ln -sf /etc_ro/services /etc/services
ln -sf /etc_ro/shells /etc/shells
ln -sf /etc_ro/profile /etc/profile

# MTK closed-source wifi (mt_wifi) reads its profile from /etc/wireless.
# /etc is a tmpfs, so the files have to be copied out of /etc_ro.
if [ -d /etc_ro/wireless ]; then
	mkdir -p /etc/wireless
	cp -a /etc_ro/wireless/. /etc/wireless/
fi
ln -sf /etc_ro/e2fsck.conf /etc/e2fsck.conf
ln -sf /etc_ro/ipkg.conf /etc/ipkg.conf

ln -sf /etc_ro/hostapd.conf /etc/hostapd.conf
ln -sf /etc_ro/hostapd_wlan1.conf /etc/hostapd_wlan1.conf

echo "/lib/firmware/" > /sys/module/firmware_class/parameters/path

# MTK closed-source wifi (mt_wifi) fetches its EEPROM through request_firmware()
# from /lib/firmware/e2p: the name comes from l1profile.dat INDEX0_EEPROM_name and
# the path is hard-coded in chips/mt7981.c.  Without that file every interface-up
# blocks 60 s in the firmware-class sysfs fallback, then the driver declares the
# calibration invalid, randomises the MAC tail and falls back to default power
# tables (rtmp_ee_flash_init -> validFlashEepromID -> rtmp_ee_flash_reset).
# /lib/firmware lives on the read-only squashfs, so overlay a tmpfs and dump the
# Factory partition into it -- this is what OpenWrt does with its caldata helper.
if [ -f /lib/modules/*/kernel/drivers/net/wireless/mt_wifi_ap/mt_wifi.ko ]; then
	_factory="$(grep -m1 '"Factory"' /proc/mtd 2>/dev/null | cut -d: -f1)"
	if [ -n "$_factory" ]; then
		rm -rf /tmp/fwsave
		mkdir -p /tmp/fwsave
		cp -a /lib/firmware/. /tmp/fwsave/ 2>/dev/null
		mount -t tmpfs tmpfs /lib/firmware -o size=6M
		cp -a /tmp/fwsave/. /lib/firmware/ 2>/dev/null
		rm -rf /tmp/fwsave
		dd if=/dev/"$_factory" of=/lib/firmware/e2p bs=64k 2>/dev/null
		echo "wifi: dumped /dev/$_factory -> /lib/firmware/e2p ($(wc -c < /lib/firmware/e2p) bytes)"
	fi
fi

# tune linux kernel
echo 65536        > /proc/sys/fs/file-max
echo "1024 65535" > /proc/sys/net/ipv4/ip_local_port_range

# fill storage
mtd_storage.sh fill

# prepare ssh authorized_keys
if [ -f /etc/storage/authorized_keys ] ; then
	cp -f /etc/storage/authorized_keys /home/root/.ssh
	chmod 600 /home/root/.ssh/authorized_keys
fi

# setup htop default color
if [ -f /usr/bin/htop ]; then
	mkdir -p /home/root/.config/htop
	echo "color_scheme=6" > /home/root/.config/htop/htoprc
fi

# perform start script
if [ -x /etc/storage/start_script.sh ] ; then
	/etc/storage/start_script.sh
fi

