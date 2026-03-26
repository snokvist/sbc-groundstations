################################################################################
# RTL8821CS WiFi — lwfinger/rtw88 backport with SDIO support
#
# Builds all rtw88 modules (core, sdio, usb, pci, per-chip).
# RTL8821CS needs: rtw_core, rtw_sdio, rtw_8821c, rtw_8821cs
# Firmware: /lib/firmware/rtw88/ (from linux-firmware)
################################################################################

RTL8821CS_VERSION = d2258b4de21aeabf7ef85ec0cada1f3cff9bcbe0
RTL8821CS_SITE = $(call github,lwfinger,rtw88,$(RTL8821CS_VERSION))
RTL8821CS_LICENSE = GPL-2.0

# The lwfinger Makefile builds all obj-m modules, no CONFIG_ needed
$(eval $(kernel-module))
$(eval $(generic-package))
