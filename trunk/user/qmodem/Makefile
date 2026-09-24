#
# QModem skeleton for padavan — USB cellular modem toolkit
# Sources: https://github.com/FUjr/QModem (MPL-2.0 + non-commercial clause)
# Adapted for the padavan build system (user/qmodem).
#

TOP      = $(shell pwd)/..
ROOTDIR  = $(TOP)/..
STAGEDIR ?= $(ROOTDIR)/stage
JSON_DIR = $(ROOTDIR)/libs/libjson-c/json-c-json-c-0.13.1-20180305

CFLAGS  += -O2 -Wall -I$(JSON_DIR) -I$(STAGEDIR)/usr/include -I$(STAGEDIR)/usr/include/json-c
LDFLAGS += -L$(JSON_DIR)/.libs -ljson-c

.PHONY: all romfs clean sms_tool quectel-CM modem_scan

all: sms_tool quectel-CM modem_scan

sms_tool:
	$(MAKE) -C sms_tool CC="$(CC)" CFLAGS="$(CFLAGS)" STRIP="$(STRIP)"

quectel-CM:
	$(MAKE) -C quectel_cm CC="$(CC)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" release

modem_scan:
	$(MAKE) -C modem_scan CC="$(CC)" STRIP="$(STRIP)" \
		CFLAGS="$(CFLAGS) -std=c99 -D_GNU_SOURCE" LDFLAGS="$(LDFLAGS) -lpthread"

romfs: all
	$(ROMFSINST) sms_tool/sms_tool /usr/bin/sms_tool_q
	$(ROMFSINST) quectel_cm/quectel-CM /usr/bin/quectel-CM
	$(ROMFSINST) modem_scan/modem_scand /usr/bin/modem_scand
	$(ROMFSINST) modem_scan/modem_scanc /usr/bin/modem_scanc
	$(ROMFSINST) files/qmodem /usr/sbin/qmodem
	mkdir -p $(INSTALLDIR)/usr/share/qmodem
	$(ROMFSINST) apns.json /usr/share/qmodem/apns.json

clean:
	-$(MAKE) -C sms_tool clean
	-$(MAKE) -C quectel_cm clean
	-$(MAKE) -C modem_scan clean
