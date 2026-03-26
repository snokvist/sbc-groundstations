################################################################################
#
# panel-generic-dsi - ROCKNIX generic MIPI DSI panel driver
#
################################################################################

PANEL_GENERIC_DSI_VERSION = 1.0
PANEL_GENERIC_DSI_SITE = $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/panel-generic-dsi/src
PANEL_GENERIC_DSI_SITE_METHOD = local
PANEL_GENERIC_DSI_LICENSE = GPL-2.0
PANEL_GENERIC_DSI_MODULE_SUBDIRS = .

$(eval $(kernel-module))
$(eval $(generic-package))
