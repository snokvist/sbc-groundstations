# Powkiddy RGB20Pro local.mk
# Based on waybeam-local.mk with RGB20Pro-specific adaptations

# ---- waybeam-hub: build from local source ----
WAYBEAM_HUB_OVERRIDE_SRCDIR = $(realpath $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/../waybeam-hub)

# ---- Fix host-LLVM build with GCC 14 / binutils 2.44 ----
HOST_LLVM_CONF_OPTS += -DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON

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

# ---- Custom wireless-regdb: replace db.txt with full regulatory database ----
LINUX_DEPENDENCIES += wireless-regdb

REGDB_CUSTOM_TXT := $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/db.txt

define WIRELESS_REGDB_USE_CUSTOM_DB_AND_REGEN_DB
	@echo "wireless-regdb: using custom db.txt and regenerating regulatory.db (unsigned)"
	$(INSTALL) -m 0644 $(REGDB_CUSTOM_TXT) $(@D)/db.txt
	$(MAKE) -C $(@D) regulatory.db
	ls -l $(@D)/regulatory.db
endef
WIRELESS_REGDB_POST_PATCH_HOOKS += WIRELESS_REGDB_USE_CUSTOM_DB_AND_REGEN_DB

# ---- Apply kernel patches ----
# POST_RSYNC_HOOKS fires for OVERRIDE_SRCDIR, POST_PATCH_HOOKS for tarballs.
# Register both so patches apply regardless of kernel source method.
define LINUX_RK_PATCHES_APPLY
	@echo "Post-patch: apply kernel patches (shared)"
	$(APPLY_PATCHES) $(@D) \
		$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/radxa/zero3/linux-patches \
		*.patch
	@if ls $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/powkiddy/rgb20pro/linux-patches/*.patch 1>/dev/null 2>&1; then \
		echo "Post-patch: apply RGB20Pro-specific kernel patches"; \
		$(APPLY_PATCHES) $(@D) \
			$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/powkiddy/rgb20pro/linux-patches \
			*.patch; \
	fi
endef
LINUX_POST_RSYNC_HOOKS += LINUX_RK_PATCHES_APPLY
LINUX_POST_PATCH_HOOKS += LINUX_RK_PATCHES_APPLY

# NOTE: panel-generic-dsi injection removed — using BSP built-in simple-panel-dsi

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

# ---- Recompile DTB with standalone dtc to fix phandle resolution ----
# The kernel build system produces a DTB with missing cpu-supply and
# display routing nodes due to dtc phandle resolution differences.
# Work around by recompiling with standalone CPP+dtc after kernel build.
define LINUX_RECOMPILE_RGB20PRO_DTB
	@echo "Recompiling RGB20Pro DTB with standalone dtc"
	$(HOST_DIR)/bin/aarch64-none-linux-gnu-cpp -nostdinc \
		-I $(@D)/include -I $(@D)/arch/arm64/boot/dts \
		-I $(@D)/arch/arm64/boot/dts/rockchip \
		-undef -D__DTS__ -x assembler-with-cpp \
		$(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/board/powkiddy/rgb20pro/dts/rockchip/rk3566-powkiddy-rgb20pro.dts \
		-o $(@D)/arch/arm64/boot/dts/rockchip/.rgb20pro_preprocessed.dts
	$(@D)/scripts/dtc/dtc -@ \
		-W no-unique_unit_address -W no-avoid_unnecessary_addr_size \
		-I dts -O dtb \
		-o $(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20pro.dtb \
		$(@D)/arch/arm64/boot/dts/rockchip/.rgb20pro_preprocessed.dts
	@echo "  DTB recompiled: $$(ls -la $(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20pro.dtb | awk '{print $$5}') bytes"
	$(INSTALL) -m 0644 \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20pro.dtb \
		$(TARGET_DIR)/boot/rockchip/rk3566-powkiddy-rgb20pro.dtb
	$(INSTALL) -m 0644 \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20pro.dtb \
		$(BINARIES_DIR)/rockchip/rk3566-powkiddy-rgb20pro.dtb
	@echo "  DTB installed to target and images"
endef
LINUX_POST_INSTALL_IMAGES_HOOKS += LINUX_RECOMPILE_RGB20PRO_DTB
