# SPDX-License-Identifier: GPL-2.0-only
#
# MediaTek conninfra (connectivity infrastructure) driver.
#
# Ported from immortalwrt-mt798x-6.6 package/mtk/drivers/conninfra/src (MTK SDK).
# It is REQUIRED by the closed source mt_wifi driver on MT7981/MT7986:
#   - hw_ctrl.c: wf_reset_func() powers the WMAC through conninfra_pwr_off() /
#     conninfra_pwr_on() inside #ifdef CONFIG_CONNINFRA_SUPPORT.  Without it the
#     WMAC is never powered on, every register reads 0 and NICLoadRomPatch fails.
#   - chips/mt7981.c: mt7981_parse_emi_phy_addr() gets the firmware EMI base from
#     conninfra_get_emi_phy_addr().
# mt_wifi gets -DCONFIG_CONNINFRA_SUPPORT when CONFIG_CONNINFRA_APSOC=y, and the
# three conninfra_* helpers resolve against this object when it is built-in.
#
# Deviations from the vendor Makefile: no -Werror and no
# KBUILD_MODPOST_FAIL_ON_WARNINGS (this is a 6.6 SDK driver, 5.15 warns), and
# $(SUBDIRS) -> $(src) so it can be built in-tree.

obj-$(CONFIG_CONNINFRA_APSOC) += conninfra.o

ccflags-y += -I$(src)/include \
	     -I$(src)/base/include \
	     -I$(src)/core/include \
	     -I$(src)/platform/include

conninfra-objs := base/ring.o \
		  base/osal.o \
		  base/msg_thread.o \
		  core/conninfra_core.o \
		  src/conninfra_dev.o \
		  src/conninfra.o \
		  platform/consys_hw.o \
		  platform/consys_hw_plat_data.o \
		  platform/pmic_mng.o \
		  platform/emi_mng.o \
		  platform/consys_reg_mng.o

ifeq ($(CONFIG_CONNINFRA_APSOC_MT7986),y)
ccflags-y += -I$(src)/platform/mt7986/include -DCONNINFRA_APSOC_MT7986
conninfra-objs += platform/mt7986/mt7986.o \
		  platform/mt7986/mt7986_pmic.o \
		  platform/mt7986/mt7986_consys_reg.o \
		  platform/mt7986/mt7986_pos.o \
		  platform/mt7986/mt7986_emi.o
endif

ifeq ($(CONFIG_CONNINFRA_APSOC_MT7981),y)
ccflags-y += -I$(src)/platform/mt7981/include -DCONNINFRA_APSOC_MT7981
conninfra-objs += platform/mt7981/mt7981.o \
		  platform/mt7981/mt7981_pmic.o \
		  platform/mt7981/mt7981_consys_reg.o \
		  platform/mt7981/mt7981_pos.o \
		  platform/mt7981/mt7981_emi.o
endif
