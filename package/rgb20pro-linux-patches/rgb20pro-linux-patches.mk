################################################################################
#
# rgb20pro-linux-patches
#
################################################################################

RGB20PRO_LINUX_PATCHES_SITE_METHOD = local
RGB20PRO_LINUX_PATCHES_SITE = $(RGB20PRO_LINUX_PATCHES_PKGDIR)
RGB20PRO_LINUX_PATCHES_LICENSE = GPL-2.0

RGB20PRO_LINUX_BUNDLE_DIR = $(BR2_EXTERNAL_OPENIPC_SBC_GS_PATH)/package/rocknix-rgb20pro-bundle
RGB20PRO_LINUX_PATCH_DIR = $(RGB20PRO_LINUX_BUNDLE_DIR)/linux-patches

ifeq ($(BR2_PACKAGE_RGB20PRO_LINUX_PATCHES),y)

define RGB20PRO_LINUX_PATCHES_APPLY
	@echo "rgb20pro-linux-patches: applying compatible Rocknix patches"
	$(APPLY_PATCHES) $(@D) \
		$(RGB20PRO_LINUX_PATCH_DIR) \
		0006-drm-panel-nv3051d-fix-panel-timings-and-display-mode.patch
	$(APPLY_PATCHES) $(@D) \
		$(RGB20PRO_LINUX_PATCH_DIR) \
		0018-arm64-dts-rockchip-add-device-tree-for-powkiddy-rgb2.patch
endef
LINUX_POST_RSYNC_HOOKS += RGB20PRO_LINUX_PATCHES_APPLY

define RGB20PRO_LINUX_PATCHES_INSTALL_FILES
	@echo "rgb20pro-linux-patches: copying panel/dts support files"
	@mkdir -p $(@D)/drivers/gpu/drm/panel
	cp -f $(RGB20PRO_LINUX_BUNDLE_DIR)/drivers/generic-dsi/panel-generic-dsi.c \
		$(@D)/drivers/gpu/drm/panel/
	grep -q 'panel-generic-dsi.o' $(@D)/drivers/gpu/drm/panel/Makefile || \
		echo 'obj-y += panel-generic-dsi.o' >> $(@D)/drivers/gpu/drm/panel/Makefile
	@mkdir -p $(@D)/arch/arm64/boot/dts/rockchip
	cp -f $(RGB20PRO_LINUX_BUNDLE_DIR)/dts/rk3566-powkiddy-rk2023.dtsi \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	# Bundle file is used as a dtsi include for rgb20-pro DTS.
	$(SED) '/^\/dts-v1\/;$$/d' \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	if [ -f $(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20-pro.dts ]; then \
		$(SED) 's/"rk3566-powkiddy-rk2023\.dts"/"rk3566-powkiddy-rk2023.dtsi"/' \
			$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20-pro.dts; \
	fi
endef
LINUX_POST_RSYNC_HOOKS += RGB20PRO_LINUX_PATCHES_INSTALL_FILES

define RGB20PRO_LINUX_PATCHES_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_INPUT_JOYSTICK)
	$(call KCONFIG_ENABLE_OPT,CONFIG_INPUT_POLLDEV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_INPUT_FF_MEMLESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_IIO)
	$(call KCONFIG_ENABLE_OPT,CONFIG_IIO_MUX)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MUX_GPIO)
	$(call KCONFIG_ENABLE_OPT,CONFIG_ROCKCHIP_SARADC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_PWM)
	$(call KCONFIG_ENABLE_OPT,CONFIG_PWM_ROCKCHIP)
	$(call KCONFIG_ENABLE_OPT,CONFIG_BACKLIGHT_PWM)
	$(call KCONFIG_ENABLE_OPT,CONFIG_DRM_MIPI_DSI)
	$(call KCONFIG_ENABLE_OPT,CONFIG_DRM_ROCKCHIP)
	$(call KCONFIG_ENABLE_OPT,CONFIG_ROCKCHIP_DW_MIPI_DSI)
	$(call KCONFIG_ENABLE_OPT,CONFIG_DRM_PANEL)
	$(call KCONFIG_ENABLE_OPT,CONFIG_DRM_PANEL_NEWVISION_NV3051D)
endef

endif

$(eval $(generic-package))
