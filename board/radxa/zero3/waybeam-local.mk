# Waybeam-specific local.mk
# Extends upstream build with custom regdb and kernel patches

# ---- CI cleanup (same as board/common/local.mk) ----
ifeq ($(CI),true)
define CI_CLEANUP_HOOK
	@echo "CI: Cleaning build directory to save space"
	$(RM) -r $(@D)/*
endef
LINUX_FIRMWARE_POST_INSTALL_IMAGES_HOOKS += CI_CLEANUP_HOOK
SAMBA4_POST_INSTALL_TARGET_HOOKS += CI_CLEANUP_HOOK

define CI_CLEANUP_SRC_HOOK
	@echo "CI: Cleaning src directory to save space"
	$(RM) -r $(SRCDIR)
endef
LINUX_POST_RSYNC_HOOKS += CI_CLEANUP_SRC_HOOK
endif

# ---- Busybox custom patches ----
define BUSYBOX_APPLY_CUSTOM_PATCHES
	$(APPLY_PATCHES) $(@D) $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/busybox *.patch
endef
BUSYBOX_POST_PATCH_HOOKS += BUSYBOX_APPLY_CUSTOM_PATCHES

# ---- Custom wireless-regdb: replace db.txt with waybeam's full regulatory database ----
LINUX_DEPENDENCIES += wireless-regdb

REGDB_CUSTOM_TXT := $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/db.txt

define WIRELESS_REGDB_USE_CUSTOM_DB_AND_REGEN_DB
	@echo "wireless-regdb: using waybeam custom db.txt and regenerating regulatory.db (unsigned)"
	$(INSTALL) -m 0644 $(REGDB_CUSTOM_TXT) $(@D)/db.txt
	$(MAKE) -C $(@D) regulatory.db
	ls -l $(@D)/regulatory.db
endef
WIRELESS_REGDB_POST_PATCH_HOOKS += WIRELESS_REGDB_USE_CUSTOM_DB_AND_REGEN_DB

# ---- Apply kernel patches after source rsync ----
define LINUX_RK_PATCHES_AFTER_RSYNC
	@echo "Post-rsync: apply kernel patches"
	$(APPLY_PATCHES) $(@D) \
		$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/linux-patches \
		*.patch
endef
LINUX_POST_RSYNC_HOOKS += LINUX_RK_PATCHES_AFTER_RSYNC

# ---- Copy regulatory.db into kernel build tree for built-in firmware ----
define LINUX_REGDB_COPY_FOR_BUILTIN_FW
	@echo "Copy regulatory.db into kernel objtree for built-in firmware"
	@obj="$(@D)"; \
	if [ -f "$(@D)/build/include/config/auto.conf" ]; then obj="$(@D)/build"; fi; \
	echo "Using objtree: $$obj"; \
	mkdir -p "$$obj/firmware"; \
	$(INSTALL) -m 0644 \
		$(BUILD_DIR)/wireless-regdb-$(WIRELESS_REGDB_VERSION)/regulatory.db \
		"$$obj/firmware/regulatory.db"; \
	test -f "$$obj/firmware/regulatory.db"
endef
LINUX_POST_CONFIGURE_HOOKS += LINUX_REGDB_COPY_FOR_BUILTIN_FW

# ---- Force regulatory.db as built-in firmware in kernel config ----
define LINUX_REGDB_FORCE_BUILTIN_FW_CONFIG
	@echo "Force built-in firmware for regulatory.db"
	$(SED) '/^\(# \)\?CONFIG_EXTRA_FIRMWARE\>/d' $(@D)/.config
	echo 'CONFIG_EXTRA_FIRMWARE="regulatory.db"' >> $(@D)/.config
	$(SED) '/^\(# \)\?CONFIG_EXTRA_FIRMWARE_DIR\>/d' $(@D)/.config
	echo 'CONFIG_EXTRA_FIRMWARE_DIR="firmware"' >> $(@D)/.config
endef
LINUX_POST_CONFIGURE_HOOKS += LINUX_REGDB_FORCE_BUILTIN_FW_CONFIG
