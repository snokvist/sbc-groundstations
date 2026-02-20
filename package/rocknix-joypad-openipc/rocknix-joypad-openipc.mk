################################################################################
#
# rocknix-joypad-openipc
#
################################################################################

ROCKNIX_JOYPAD_OPENIPC_SITE_METHOD = local
ROCKNIX_JOYPAD_OPENIPC_SITE = $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/rocknix-rgb20pro-bundle/drivers/rocknix-joypad
ROCKNIX_JOYPAD_OPENIPC_LICENSE = GPL-2.0

ROCKNIX_JOYPAD_OPENIPC_MODULE_MAKE_OPTS = \
	DEVICE=RK3566 \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
