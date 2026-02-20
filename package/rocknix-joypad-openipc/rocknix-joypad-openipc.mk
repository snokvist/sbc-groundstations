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

define ROCKNIX_JOYPAD_OPENIPC_FORCE_SOURCE_SYNC
	cp -f $(ROCKNIX_JOYPAD_OPENIPC_SITE)/*.c $(@D)/
	cp -f $(ROCKNIX_JOYPAD_OPENIPC_SITE)/*.h $(@D)/
	cp -f $(ROCKNIX_JOYPAD_OPENIPC_SITE)/Makefile $(@D)/
endef
ROCKNIX_JOYPAD_OPENIPC_POST_RSYNC_HOOKS += ROCKNIX_JOYPAD_OPENIPC_FORCE_SOURCE_SYNC

$(eval $(kernel-module))
$(eval $(generic-package))
