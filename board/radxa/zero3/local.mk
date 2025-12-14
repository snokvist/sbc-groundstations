LINUX_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/linux
LINUX_CFLAGS = "-Wno-enum-int-mismatch"
UBOOT_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/u-boot
UBOOT_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/u-boot
ROCKCHIP_RKBIN_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/rkbin

LINUX_DEPENDENCIES += wireless-regdb

# Force wireless regdb options after Buildroot's olddefconfig, since the symbols
# are hidden and otherwise revert to defaults.

define LINUX_INSTALL_INTERNAL_DB_TXT
	@echo "Installing net/wireless/db.txt for INTERNAL_REGDB"
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/db.txt \
		$(@D)/net/wireless/db.txt
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211_INTERNAL_REGDB)
	$(call KCONFIG_DISABLE_OPT,CONFIG_CFG80211_REQUIRE_SIGNED_REGDB)
endef
LINUX_POST_PATCH_HOOKS += LINUX_INSTALL_INTERNAL_DB_TXT

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
