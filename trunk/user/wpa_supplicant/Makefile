# ---------------------------------------------------------------------------
# padavan-arm: neutralize the leaked CONFIG_INTERWORKING
#
# 本包构建时会带上内核 .config 的全部变量（trunk/user/Makefile 里
# `-include $(LINUX_CONFIG)`，且顶层 Makefile 用了 .EXPORT_ALL_VARIABLES）。
# mt_wifi 驱动的 Kconfig 里定义了一个**同名**符号 INTERWORKING（default y），
# 于是这里的 `ifdef CONFIG_INTERWORKING` 会被点亮，把 interworking.o 编进来。
# 但本包的 .config.def 是"有线 802.1X"配置（CONFIG_NO_SCAN_PROCESSING=y、
# CONFIG_NO_WPA=y），interworking.o 依赖的 wpa_supplicant_pick_network()
# 被 CONFIG_NO_SCAN_PROCESSING 编译掉 -> 链接失败。
# 显式清空即可（make 的 ifdef 对空值判为假）。
# ---------------------------------------------------------------------------
CONFIG_INTERWORKING=
export CONFIG_INTERWORKING

SRC_NAME=wpa_supplicant


all:
	cp -f $(SRC_NAME)/.config.def $(SRC_NAME)/.config
ifeq ($(CONFIG_FIRMWARE_INCLUDE_EAP_PEAP),y)
	echo CONFIG_EAP_TTLS=y >> $(SRC_NAME)/.config
	echo CONFIG_EAP_PEAP=y >> $(SRC_NAME)/.config
	echo CONFIG_EAP_MSCHAPV2=y >> $(SRC_NAME)/.config
else ifeq (,$(wildcard $(STAGEDIR)/lib/pkgconfig/openssl.pc))
	echo CONFIG_TLS=internal >> $(SRC_NAME)/.config
	echo CONFIG_CRYPTO=internal >> $(SRC_NAME)/.config
	echo CONFIG_INTERNAL_LIBTOMMATH=y >> $(SRC_NAME)/.config
	echo CONFIG_INTERNAL_RC4=y >> $(SRC_NAME)/.config
endif
	$(MAKE) -C $(SRC_NAME)

clean:
	$(MAKE) -C $(SRC_NAME) clean

romfs:
	$(ROMFSINST) $(SRC_NAME)/wpa_cli /usr/sbin/wpa_cli
	$(ROMFSINST) $(SRC_NAME)/wpa_supplicant /usr/sbin/wpa_supplicant
