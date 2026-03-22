###############################################################################
#
# waybeam-hub (ground station — built from source)
#
# Builds waybeam-hub ground binary from the DVR color-correct branch.
# Requires: rockchip-mpp, gstreamer, libdrm, eudev, libpng, librga.
# Optional: mesa3d (EGL/GLES2/GBM) for color-corrected DVR recording.
#
###############################################################################

WAYBEAM_HUB_VERSION = claude/review-librga-integration-ZkXYG
WAYBEAM_HUB_SITE = $(call github,snokvist,waybeam-hub,$(WAYBEAM_HUB_VERSION))
WAYBEAM_HUB_DEPENDENCIES = rockchip-mpp gstreamer1 gst1-plugins-base \
	libdrm eudev libgpiod cjson libcurl libpng librga

# Pull in Mesa3D for color-corrected DVR if available
ifeq ($(BR2_PACKAGE_MESA3D),y)
WAYBEAM_HUB_DEPENDENCIES += mesa3d
endif

define WAYBEAM_HUB_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) ground \
		CC="$(TARGET_CC)" \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define WAYBEAM_HUB_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/build/ground/waybeam_hub \
		$(TARGET_DIR)/usr/bin/waybeam_hub

	$(INSTALL) -D -m 0644 $(WAYBEAM_HUB_PKGDIR)/files/waybeam_ground.conf \
		$(TARGET_DIR)/etc/waybeam_hub.conf

	$(INSTALL) -D -m 0755 $(WAYBEAM_HUB_PKGDIR)/files/S99waybeam_hub \
		$(TARGET_DIR)/etc/init.d/S99waybeam_hub
endef

$(eval $(generic-package))
