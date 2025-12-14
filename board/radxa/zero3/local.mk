LINUX_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/linux
LINUX_CFLAGS = "-Wno-enum-int-mismatch"
UBOOT_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/u-boot
UBOOT_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/u-boot
ROCKCHIP_RKBIN_OVERRIDE_SRCDIR=$(BUILD_DIR)/radxa-bsp-main/.src/rkbin

LINUX_DEPENDENCIES += wireless-regdb

# Force wireless regdb options after Buildroot's olddefconfig, since the symbols
# are hidden and otherwise revert to defaults.
# Force cfg80211 regdb options after olddefconfig (hidden symbols may revert otherwise)
define LINUX_INTERNAL_REGDB_CONFIG_FIXUPS
	$(SED) '/^\(# \)\?CONFIG_CFG80211_INTERNAL_REGDB\>/d' $(@D)/.config
	echo 'CONFIG_CFG80211_INTERNAL_REGDB=y' >> $(@D)/.config
	$(SED) '/^\(# \)\?CONFIG_CFG80211_REQUIRE_SIGNED_REGDB\>/d' $(@D)/.config
	echo '# CONFIG_CFG80211_REQUIRE_SIGNED_REGDB is not set' >> $(@D)/.config
	grep -E 'CFG80211_INTERNAL_REGDB|CFG80211_REQUIRE_SIGNED_REGDB' $(@D)/.config || true
endef

# IMPORTANT: expand the contents, don’t add the name as a literal token
PACKAGES_LINUX_CONFIG_FIXUPS += $(LINUX_INTERNAL_REGDB_CONFIG_FIXUPS)$(sep)



define LINUX_INSTALL_INTERNAL_DB_TXT
	@echo "Installing net/wireless/db.txt for INTERNAL_REGDB"
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/db.txt \
		$(@D)/net/wireless/db.txt
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
