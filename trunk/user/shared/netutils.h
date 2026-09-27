/*
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */

#ifndef _netutils_h_
#define _netutils_h_

#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include <ralink_boards.h>

#if ((__UCLIBC_MAJOR__ == 0) && (__UCLIBC_MINOR__ < 9 || (__UCLIBC_MINOR__ == 9 && __UCLIBC_SUBLEVEL__ < 30)))
#undef HAVE_GETIFADDRS
#else
#define HAVE_GETIFADDRS 1
#endif

//#define IFUP				(IFF_UP | IFF_RUNNING | IFF_BROADCAST | IFF_MULTICAST)
#define IFUP				(IFF_UP | IFF_RUNNING)
#define IFDOWN				(0)
#define sin_addr(s)			(((struct sockaddr_in *)(s))->sin_addr)

#define IFNAME_BR			"br0"

#define IFNAME_MAC			"eth0"
#define IFNAME_MAC2			"eth1"

#if defined (USE_SINGLE_MAC)
#define IFNAME_LAN			"eth1.1"
#define IFNAME_WAN			"eth1.2"
#elif defined (BOARD_ZX7981PG)
/*
 * MT7981 + MT7531 走 DSA：switch 的每个 port 是独立的 netdev，名字由 DTS 的
 * label 决定（lan2 / lan3 / wan），不是 eth0 / eth1。padavan 的默认 IFNAME_WAN
 * 是 "eth1"，于是 rc.c 每次开机把 wan0_ifname 写成 eth1、接口从未被 up，
 * WebUI 也就永远显示 WAN 未连接（switch_none.c 去读 /sys/class/net/eth1/speed）。
 *
 * 注意只改 WAN：net_lan.c 给 br0 加成员用的是 IFNAME_LAN1..LAN4 和 IFNAME_MAC2，
 * 若把 IFNAME_MAC2 一起改成 "wan"，WAN 口会被误加进 LAN 桥。
 */
#define IFNAME_LAN			IFNAME_MAC
#define IFNAME_WAN			"wan"
#else
#define IFNAME_LAN			IFNAME_MAC
#define IFNAME_WAN			IFNAME_MAC2
#endif

/*
 * IFNAME_WAN_PORT —— 「WAN 物理口」的 netdev 名（WAN CPU 口）。
 *
 * 非单 MAC 机型历史上就用 IFNAME_MAC2(eth1) 当 WAN CPU 口；ZX7981PG 走 DSA，
 * WAN 口 netdev 由 DTS 的 label 决定、叫 "wan"（没有 eth1）。
 *
 * net_wan.c / web_ex.c 里凡「WAN 物理口」语义（做 VLAN 子接口、设 MAC/MTU/up、
 * 写 wan0_ifname、取 WAN 网速统计）都必须用它。否则 boot 时 wan0_ifname 会被写成
 * eth1（不存在的口）⇒ WAN 从未 up；且 net_wan.c 的 wan_down 会因为
 * man_ifname(eth1) != IFNAME_WAN(wan) 主动把 wan 口 down 掉。
 *
 * 注意：net_lan.c 里给 br0 加成员的 IFNAME_MAC2 是 LAN 语义，不要改。
 */
#if defined (USE_SINGLE_MAC)
#define IFNAME_WAN_PORT			IFNAME_MAC
#elif defined (BOARD_ZX7981PG)
#define IFNAME_WAN_PORT			"wan"
#else
#define IFNAME_WAN_PORT			IFNAME_MAC2
#endif

//#if defined(BOARD_RAX3000M)||defined(MT7981)

#define IFNAME_LAN1                      "lan1"
#define IFNAME_LAN2                      "lan2"
#define IFNAME_LAN3                      "lan3"
#define IFNAME_LAN4                      "lan4"
//#endif


#define BOARD_2G_AS_WSOC		(BOARD_2G_IN_SOC || !BOARD_5G_IN_SOC)

#if BOARD_2G_AS_WSOC
#if defined (BOARD_MT7615_DBDC) || defined (BOARD_MT7915_DBDC)
#define IFNAME_2G_MAIN			"rax0"
#define IFNAME_2G_GUEST			"rax1"
#define IFNAME_2G_APCLI			"apclix0"
#else
#define IFNAME_2G_MAIN			"ra0"
#define IFNAME_2G_GUEST			"ra1"
#define IFNAME_2G_APCLI			"apcli0"
#endif


#define IFNAME_2G_WDS0			"wds0"
#define IFNAME_2G_WDS1			"wds1"
#define IFNAME_2G_WDS2			"wds2"
#define IFNAME_2G_WDS3			"wds3"
#else
#define IFNAME_2G_MAIN			"rai0"
#define IFNAME_2G_GUEST			"rai1"
#define IFNAME_2G_APCLI			"apclii0"
#define IFNAME_2G_WDS0			"wdsi0"
#define IFNAME_2G_WDS1			"wdsi1"
#define IFNAME_2G_WDS2			"wdsi2"
#define IFNAME_2G_WDS3			"wdsi3"
#endif

#if BOARD_HAS_5G_RADIO
#if BOARD_5G_IN_SOC
#define IFNAME_5G_MAIN			"ra0"
#define IFNAME_5G_GUEST			"ra1"
#define IFNAME_5G_APCLI			"apcli0"
#define IFNAME_5G_WDS0			"wds0"
#define IFNAME_5G_WDS1			"wds1"
#define IFNAME_5G_WDS2			"wds2"
#define IFNAME_5G_WDS3			"wds3"
#else
#if defined (BOARD_MT7615_DBDC) || defined (BOARD_MT7915_DBDC)
#define IFNAME_5G_MAIN			"ra0"
#define IFNAME_5G_GUEST			"ra1"
#define IFNAME_5G_APCLI			"apcli0"
#else
#define IFNAME_5G_MAIN			"rai0"
#define IFNAME_5G_GUEST			"rai1"
#define IFNAME_5G_APCLI			"apclii0"
#endif
#define IFNAME_5G_WDS0			"wdsi0"
#define IFNAME_5G_WDS1			"wdsi1"
#define IFNAME_5G_WDS2			"wdsi2"
#define IFNAME_5G_WDS3			"wdsi3"
#endif
#endif


#if defined(USE_MT7915_AP)
/*
 * MTK closed-source stack (mt_wifi).  The driver creates the interfaces itself,
 * named by l1profile.dat:
 *     main_ifname=ra0;rax0   apcli_ifname=apcli;apclix   ext_ifname=ra;rax
 * so band0 (= 2.4G) -> ra0 / ra1(guest) / apcli0 and band1 (= 5G) ->
 * rax0 / rax1 / apclix0.  Verified on hardware.
 *
 * Note the driver IGNORES the band1 half of an "a;b" value unless
 * CONFIG_MULTI_PROFILE_SUPPORT is enabled (rt_profile.c l1set_ifname()), so the
 * profile cannot be used to rename the interfaces -- padavan has to follow the
 * names the driver really creates.
 *
 * The DBDC branch above maps IFNAME_*_APCLI the other way round, so undo that too.
 */
#undef IFNAME_2G_MAIN
#undef IFNAME_2G_GUEST
#undef IFNAME_2G_APCLI
#undef IFNAME_5G_MAIN
#undef IFNAME_5G_GUEST
#undef IFNAME_5G_APCLI

#define IFNAME_2G_MAIN			"ra0"
#define IFNAME_2G_GUEST			"ra1"
#define IFNAME_2G_APCLI			"apcli0"
#define IFNAME_5G_MAIN			"rax0"
#define IFNAME_5G_GUEST			"rax1"
#define IFNAME_5G_APCLI			"apclix0"
#else
#undef IFNAME_2G_MAIN
#undef IFNAME_2G_GUEST
#undef IFNAME_5G_MAIN
#undef IFNAME_5G_GUEST

#define IFNAME_2G_MAIN			"wlan0"
#define IFNAME_2G_GUEST			"wlan0-1"
#define IFNAME_5G_MAIN			"wlan1"
#define IFNAME_5G_GUEST			"wlan1-1"
#endif

#if defined(USE_RT3352_MII)
#define IFNAME_INIC_MAIN		IFNAME_2G_MAIN
#define IFNAME_INIC_GUEST		IFNAME_2G_GUEST
#define IFNAME_INIC_GUEST_VLAN		"eth2.3"
#define INIC_GUEST_VLAN_VID		3
#define MIN_EXT_VLAN_VID		4
#else
#define MIN_EXT_VLAN_VID		2
#endif

#define IFNAME_SIT			"sit1"

#define WAN_PPP_UNIT			0
#define WAN_PPP_UNIT_MAX		1
#define IFNAME_PPP			"ppp0"

#define RAS_PPP_UNIT			2
#define IFNAME_RAS			"ppp2"

#define VPNC_PPP_UNIT			5
#define IFNAME_CLIENT_PPP		"ppp5"

#define IFNAME_SERVER_TAP		"tap1"
#define IFNAME_CLIENT_TAP		"tap0"

#define IFNAME_SERVER_TUN		"tun1"
#define IFNAME_CLIENT_TUN		"tun0"

#define IFNAME_USBNET1			"wwan0"
#define IFNAME_USBNET2			"weth0"

#define IFDESC_VPNC			"VPNC"
#define IFDESC_WISP			"WISP"
#define IFDESC_WWAN			"WWAN"
#define IFDESC_WAN			"WAN"
#define IFDESC_LAN			"LAN"
#define IFDESC_WLAN2_MII		"WLAN2_MII"
#define IFDESC_WLAN2_AP0		"WLAN2_AP0"
#define IFDESC_WLAN2_AP1		"WLAN2_AP1"
#define IFDESC_WLAN2_APC		"WLAN2_APC"
#define IFDESC_WLAN2_WDS		"WLAN2_WDS"
#if BOARD_HAS_5G_RADIO
#define IFDESC_WLAN5_AP0		"WLAN5_AP0"
#define IFDESC_WLAN5_AP1		"WLAN5_AP1"
#define IFDESC_WLAN5_APC		"WLAN5_APC"
#define IFDESC_WLAN5_WDS		"WLAN5_WDS"
#define IFDESCS_MAX_NUM			12
#else
#define IFDESCS_MAX_NUM			8
#endif


enum {
	IPV4_WAN_PROTO_IPOE_STATIC = 0,
	IPV4_WAN_PROTO_IPOE_DHCP,
	IPV4_WAN_PROTO_PPPOE,
	IPV4_WAN_PROTO_PPTP,
	IPV4_WAN_PROTO_L2TP
};

enum {
	IPV6_DISABLED = 0,
	IPV6_NATIVE_STATIC,
	IPV6_NATIVE_DHCP6,
	IPV6_6IN4,
	IPV6_6TO4,
	IPV6_6RD
};

extern in_addr_t inet_addr_safe(const char *cp);
extern int       is_valid_ipv4(const char *cp);
extern int       is_valid_hostname(const char *hname);
extern int       is_man_wisp(const char *ifname);
extern int       is_usbnet_interface(const char *ifname);
extern int       get_ap_mode(void);
extern int       get_wan_proto(int unit);
extern char*     get_man_ifname(int unit);
extern int       get_usb_modem_wan(int unit);
extern int       get_usb_modem_dev_wan(int unit, int devnum);
extern void      set_usb_modem_dev_wan(int unit, int devnum);
extern int       get_wan_ether_link_cached(void);
extern int       get_internet_state_cached(void);
extern int       ifconfig(const char *ifname, int flags, const char *addr, const char *mask);
extern int       is_interface_exist(const char *ifname);
extern int       is_interface_up(const char *ifname);
extern int       get_interface_flags(const char *ifname);
extern int       get_interface_index(const char *ifname);
extern int       get_interface_irq(const char *ifname);
extern int       get_interface_mtu(const char *ifname);
extern int       set_interface_mtu(const char *ifname, int mtu);
extern int       get_interface_hwaddr(const char *ifname, unsigned char mac[6]);
extern int       set_interface_hwaddr(const char *ifname, const char *mac_str);
extern in_addr_t get_interface_addr4(const char *ifname);
extern void      set_interface_conf_int(const char *ver, const char *ifname, const char *param, int value);
extern int       get_ipv6_type(void);

extern int       vconfig_add_if(const char *ifname, unsigned int vid);
extern int       vconfig_del_if(const char *vifname);
extern int       vconfig_egress_map(const char *vifname, int skb_prio, int qos_prio);

extern int       br_add_del_bridge(const char *brname, int is_add);
extern int       br_add_del_if(const char *brname, const char *ifname, int is_add);
extern int       br_del_all_ifs(const char *brname, int do_if_down, int do_if_rem);
extern void      br_set_param_int(const char *brname, const char *param, int value);
extern void      br_set_fd(const char *brname, int delay_sec);
extern void      br_set_stp(const char *brname, int stp_state);
extern void      brport_set_param_int(const char *ifname, const char *param, int value);
extern void      brport_set_m2u(const char *ifname, int m2u_on);

extern const char* get_ifname_descriptor(const char* ifname, int ap_mode, int *ifindex, int *wan_no);
extern uint64_t    get_ifstats_bytes_rx(const char* ifname);
extern uint64_t    get_ifstats_bytes_tx(const char* ifname);

#if defined (USE_IPV6)
extern int  is_valid_ipv6(const char *cp);
extern char *get_ifaddr6(const char *ifname, int linklocal, char *p_addr6s);
#endif

#endif
