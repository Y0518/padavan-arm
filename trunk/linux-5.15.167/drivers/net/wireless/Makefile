# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the Linux Wireless network device drivers.
#

obj-$(CONFIG_WLAN_VENDOR_ADMTEK) += admtek/
obj-$(CONFIG_WLAN_VENDOR_ATH) += ath/
obj-$(CONFIG_WLAN_VENDOR_ATMEL) += atmel/
obj-$(CONFIG_WLAN_VENDOR_BROADCOM) += broadcom/
obj-$(CONFIG_WLAN_VENDOR_CISCO) += cisco/
obj-$(CONFIG_WLAN_VENDOR_INTEL) += intel/
obj-$(CONFIG_WLAN_VENDOR_INTERSIL) += intersil/
obj-$(CONFIG_WLAN_VENDOR_MARVELL) += marvell/
obj-$(CONFIG_WLAN_VENDOR_MEDIATEK) += mediatek/
obj-$(CONFIG_WLAN_VENDOR_MICROCHIP) += microchip/
obj-$(CONFIG_WLAN_VENDOR_RALINK) += ralink/
obj-$(CONFIG_WLAN_VENDOR_REALTEK) += realtek/
obj-$(CONFIG_WLAN_VENDOR_RSI) += rsi/
obj-$(CONFIG_WLAN_VENDOR_ST) += st/
obj-$(CONFIG_WLAN_VENDOR_TI) += ti/
obj-$(CONFIG_WLAN_VENDOR_ZYDAS) += zydas/
obj-$(CONFIG_WLAN_VENDOR_QUANTENNA) += quantenna/

# 16-bit wireless PCMCIA client drivers
obj-$(CONFIG_PCMCIA_RAYCS)	+= ray_cs.o
obj-$(CONFIG_PCMCIA_WL3501)	+= wl3501_cs.o

obj-$(CONFIG_USB_NET_RNDIS_WLAN)	+= rndis_wlan.o

obj-$(CONFIG_MAC80211_HWSIM)	+= mac80211_hwsim.o

obj-$(CONFIG_VIRT_WIFI)	+= virt_wifi.o

# MediaTek closed source WiFi driver (mt_wifi)
#
# mt_wifi_ap/ becomes mt_wifi.ko when CONFIG_MT_AP_SUPPORT=m.  padavan's
# rc insmods it (load_wireless_modules() in user/rc/rc.c) once the rootfs
# is mounted, which is required because the driver reads
# /etc/wireless/l1profile.dat at probe time; a built-in driver is probed
# ~0.8 s before the rootfs exists and then never creates an interface.
#
# wifi_utility/ (mt_wifi_mtd.o + pci_mediatek_rbus.o) is deliberately kept
# in vmlinux even then:
#   * mt_wifi_mtd.c has no MODULE_LICENSE() and no module_init, so modpost
#     rejects it as a module;
#   * rbus_init() in pci_mediatek_rbus.c returns -ENODEV on MT7981 (no
#     OF_RBUS node), so as a module its insmod would fail -- and mt_wifi.ko
#     references dev_second_irq/multi_intr_* (rbus_prop_dev.c), so modprobe
#     would then refuse to load mt_wifi at all.  Built in, the -ENODEV is
#     just an ignored initcall, as it always was.
ifneq ($(CONFIG_MT_AP_SUPPORT),)
obj-y += wifi_utility/
obj-$(CONFIG_MT_AP_SUPPORT) += mt_wifi_ap/
obj-$(CONFIG_CONNINFRA_APSOC) += conninfra/
endif
