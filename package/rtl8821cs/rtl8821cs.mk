################################################################################
# RTL8821CS package (external kernel module — SDIO WiFi)
################################################################################

RTL8821CS_VERSION = main
RTL8821CS_SITE = https://github.com/lwfinger/rtl8821cs.git
RTL8821CS_SITE_METHOD = git
RTL8821CS_LICENSE = GPL-2.0
RTL8821CS_MODULE_MAKE_OPTS = \
	CONFIG_RTL8821CS=m \
	USER_EXTRA_CFLAGS="-Wno-error"

$(eval $(kernel-module))
$(eval $(generic-package))
