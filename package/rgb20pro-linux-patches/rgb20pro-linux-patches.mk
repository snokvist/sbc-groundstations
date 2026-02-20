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
	# Some BSP kernels omit the upstream nv3051d panel driver. Inject a vendored
	# copy so the RK2023/RGB20 Pro timing fix can still be used.
	if [ ! -f $(@D)/drivers/gpu/drm/panel/panel-newvision-nv3051d.c ]; then \
		mkdir -p $(@D)/drivers/gpu/drm/panel; \
		cp -f $(RGB20PRO_LINUX_BUNDLE_DIR)/drivers/nv3051d/panel-newvision-nv3051d.c \
			$(@D)/drivers/gpu/drm/panel/panel-newvision-nv3051d.c; \
		grep -q 'panel-newvision-nv3051d.o' $(@D)/drivers/gpu/drm/panel/Makefile || \
			echo 'obj-y += panel-newvision-nv3051d.o' >> $(@D)/drivers/gpu/drm/panel/Makefile; \
		echo "rgb20pro-linux-patches: injected panel-newvision-nv3051d.c"; \
	fi
	if [ -f $(@D)/drivers/gpu/drm/panel/panel-newvision-nv3051d.c ]; then \
		if grep -q 'MIPI_DSI_CLOCK_NON_CONTINUOUS' $(@D)/drivers/gpu/drm/panel/panel-newvision-nv3051d.c; then \
			echo "rgb20pro-linux-patches: 0006 already applied in panel-newvision-nv3051d.c"; \
		else \
			$(APPLY_PATCHES) $(@D) \
				$(RGB20PRO_LINUX_PATCH_DIR) \
				0006-drm-panel-nv3051d-fix-panel-timings-and-display-mode.patch; \
		fi; \
	else \
		echo "rgb20pro-linux-patches: skipping 0006 (panel-newvision-nv3051d.c not in kernel tree)"; \
	fi
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
	# Avoid endpoint label collisions with rk356x base dtsi labels.
	$(SED) 's/\<vp0_out_hdmi:[[:space:]]*//' \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	$(SED) 's/\<vp1_out_dsi0:[[:space:]]*//' \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	$(SED) 's/\<dsi0_in_vp1:[[:space:]]*//' \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	# Radxa BSP DTS trees may miss some RK2023 labels used by Rocknix.
	# Prune incompatible override blocks from the copied rk2023 dtsi.
	dts_label_files="$(@D)/arch/arm64/boot/dts/rockchip/rk3566.dtsi"; \
	if [ -f $(@D)/arch/arm64/boot/dts/rockchip/rk356x.dtsi ]; then \
		dts_label_files="$$dts_label_files $(@D)/arch/arm64/boot/dts/rockchip/rk356x.dtsi"; \
	fi; \
	for lbl in combphy1 hdmi_in hdmi_out usb_host0_xhci usb_host1_xhci usb2phy1_host; do \
		if ! grep -qs "^[[:space:]]*$$lbl:" \
			$$dts_label_files; then \
			echo "rgb20pro-linux-patches: pruning &$$lbl block (label missing in BSP DTS)"; \
			$(SED) "/^[[:space:]]*&$$lbl[[:space:]]*{/,/^};[[:space:]]*$$/d" \
				$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi; \
		fi; \
	done
	# Some BSP trees do not expose vdd_cpu label used by Rocknix rk2023 dtsi.
	dts_label_files="$(@D)/arch/arm64/boot/dts/rockchip/rk3566.dtsi"; \
	if [ -f $(@D)/arch/arm64/boot/dts/rockchip/rk356x.dtsi ]; then \
		dts_label_files="$$dts_label_files $(@D)/arch/arm64/boot/dts/rockchip/rk356x.dtsi"; \
	fi; \
	if ! grep -qs "^[[:space:]]*vdd_cpu:" \
		$$dts_label_files; then \
		echo "rgb20pro-linux-patches: removing cpu-supply references to missing vdd_cpu label"; \
		$(SED) '/cpu-supply = <&vdd_cpu>;/d' \
			$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi; \
	fi
	# If hdmi_in/out blocks were pruned, these endpoint links can become dangling.
	$(SED) '/remote-endpoint = <&hdmi_out_con>;/d' \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	$(SED) '/remote-endpoint = <&hdmi_in_vp0>;/d' \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi
	# RGB20 Pro DTS in this BSP does not define mipi_in_panel graph endpoint.
	if ! grep -qs "^[[:space:]]*mipi_in_panel:" \
		$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rgb20-pro.dts; then \
		$(SED) '/remote-endpoint = <&mipi_in_panel>;/d' \
			$(@D)/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-rk2023.dtsi; \
	fi
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
