################################################################################
# RTL8821CS package (external kernel module — SDIO WiFi)
################################################################################

RTL8821CS_VERSION = 1569a382e9af28a5e2160f8c96b2fd1b3523e008
RTL8821CS_SITE = https://github.com/lwfinger/rtl8821cs/archive
RTL8821CS_SOURCE = $(RTL8821CS_VERSION).tar.gz
RTL8821CS_LICENSE = GPL-2.0
RTL8821CS_MODULE_MAKE_OPTS = \
	CONFIG_RTL8821CS=m \
	USER_EXTRA_CFLAGS="-Wno-error"

$(eval $(kernel-module))
$(eval $(generic-package))
