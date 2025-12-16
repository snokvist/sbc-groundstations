LINUX_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/linux
LINUX_CFLAGS = "-Wno-enum-int-mismatch"
UBOOT_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/u-boot
UBOOT_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/u-boot
ROCKCHIP_RKBIN_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/rkbin
LINUX_DEPENDENCIES += wireless-regdb

define BUSYBOX_APPLY_CUSTOM_PATCHES
    $(APPLY_PATCHES) $(@D) $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/busybox \*.patch
endef

BUSYBOX_POST_PATCH_HOOKS += BUSYBOX_APPLY_CUSTOM_PATCHES

# We have tight space constraints on the gitlab runners
ifeq ($(CI),true)

# Remove unused build artifacs after install
define CI_CLEANUP_HOOK
	@echo "CI: Cleaning build directory to save space"
	$(RM) -r $(@D)/*
endef
LINUX_FIRMWARE_POST_INSTALL_IMAGES_HOOKS += CI_CLEANUP_HOOK
SAMBA4_POST_INSTALL_TARGET_HOOKS += CI_CLEANUP_HOOK

# Remove unused src tree
define CI_CLEANUP_SRC_HOOK
	@echo "CI: Cleaning src directory to save space"
	$(RM) -r $(SRCDIR)
endef
LINUX_POST_RSYNC_HOOKS += CI_CLEANUP_SRC_HOOK

endif

define LINUX_RK_REGDB_AFTER_RSYNC
	@echo "Post-rsync: apply patches + install db + force kconfig"

	$(APPLY_PATCHES) $(@D) \
		$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/linux-patches \
		\*.patch

endef
LINUX_POST_RSYNC_HOOKS += LINUX_RK_REGDB_AFTER_RSYNC


define LINUX_REGDB_COPY_FOR_BUILTIN_FW
	@echo "Copy regulatory.db into kernel tree for built-in firmware"
	mkdir -p $(@D)/firmware
	$(INSTALL) -m 0644 \
		$(BUILD_DIR)/wireless-regdb-$(WIRELESS_REGDB_VERSION)/regulatory.db \
		$(@D)/firmware/regulatory.db
	$(INSTALL) -m 0644 \
		$(BUILD_DIR)/wireless-regdb-$(WIRELESS_REGDB_VERSION)/regulatory.db.p7s \
		$(@D)/firmware/regulatory.db.p7s
endef
LINUX_POST_PATCH_HOOKS += LINUX_REGDB_COPY_FOR_BUILTIN_FW


