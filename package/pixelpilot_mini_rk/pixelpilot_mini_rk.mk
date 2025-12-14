################################################################################
#
# pixelpilot_mini_rk
#
################################################################################

PIXELPILOT_MINI_RK_VERSION = main
PIXELPILOT_MINI_RK_SITE = https://github.com/snokvist/pixelpilot_mini_rk.git
PIXELPILOT_MINI_RK_SITE_METHOD = git
PIXELPILOT_MINI_RK_LICENSE = Proprietary

# Makefile uses pkg-config for these; host-pkgconf provides it during build.
PIXELPILOT_MINI_RK_DEPENDENCIES = host-pkgconf libdrm eudev libglib2 \
	gstreamer1 gst1-plugins-base rockchip-mpp

# If your Buildroot tree names differ:
# - "udev" might be "eudev" on some setups
# - rockchip-mpp package name may vary in your BR2_EXTERNAL

define PIXELPILOT_MINI_RK_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		$(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		ENABLE_NEON=auto \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		PKG_DRMCFLAGS="-I$(STAGING_DIR)/usr/include -I$(STAGING_DIR)/usr/include/libdrm" \
		PKG_DRMLIBS="-L$(STAGING_DIR)/usr/lib -ldrm -ludev" \
		PKG_MPPCFLAGS="-I$(STAGING_DIR)/usr/include/rockchip" \
		PKG_MPPLIBS="-L$(STAGING_DIR)/usr/lib -lrockchip_mpp"
endef



define PIXELPILOT_MINI_RK_INSTALL_TARGET_CMDS
	# Binary
	$(INSTALL) -D -m 0755 $(@D)/pixelpilot_mini_rk \
		$(TARGET_DIR)/usr/bin/pixelpilot_mini_rk

	# Assets
	$(INSTALL) -D -m 0644 $(@D)/assets/spinner_ai_1080p30.h265 \
		$(TARGET_DIR)/usr/share/pixelpilot_mini_rk/spinner_ai_1080p30.h265

	# Config: generate pixelpilot_mini.ini with ASSETDIR substituted
	$(INSTALL) -d $(TARGET_DIR)/etc
	sed -e 's|@ASSETDIR@|/usr/share/pixelpilot_mini_rk|g' \
		$(@D)/config/pixelpilot_mini.ini > $(TARGET_DIR)/etc/pixelpilot_mini.ini
	chmod 0644 $(TARGET_DIR)/etc/pixelpilot_mini.ini
endef

# SysV init script (BusyBox init)
define PIXELPILOT_MINI_RK_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(PIXELPILOT_MINI_RK_PKGDIR)/files/S99pixelpilot_mini_rk \
		$(TARGET_DIR)/etc/init.d/S99pixelpilot_mini_rk
endef

$(eval $(generic-package))
