################################################################################
# RTL88X2CU package (external kernel)
################################################################################

RTL88X2CU_VERSION = e8b5f9568f137e34ce7e76994a65565e34257f89
RTL88X2CU_SITE = https://github.com/snokvist/rtl88x2cu-20230728.git
RTL88X2CU_SITE_METHOD = git
RTL88X2CU_LICENSE = unspecified
RTL88X2CU_MODULE_MAKE_OPTS = \
	CONFIG_RTL8822CU=m \
	USER_EXTRA_CFLAGS="-Wno-stringop-overread -Wno-error -Wno-misleading-indentation"

$(eval $(kernel-module))

define RTL88X2CU_POST_INSTALL_INSTALL_UDEV_RULES
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/rtl88x2cu/88x2cu.rules $(TARGET_DIR)/etc/udev/rules.d/88x2cu.rules
endef
RTL88X2CU_POST_INSTALL_TARGET_HOOKS += RTL88X2CU_POST_INSTALL_INSTALL_UDEV_RULES

$(eval $(generic-package))
