################################################################################
#
# rocknix-joypad - ROCKNIX singleadc joypad driver
#
################################################################################

ROCKNIX_JOYPAD_VERSION = 1.0
ROCKNIX_JOYPAD_SITE = $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/rocknix-joypad/src
ROCKNIX_JOYPAD_SITE_METHOD = local
ROCKNIX_JOYPAD_LICENSE = GPL-2.0-or-later
ROCKNIX_JOYPAD_MODULE_SUBDIRS = .

$(eval $(kernel-module))
$(eval $(generic-package))
