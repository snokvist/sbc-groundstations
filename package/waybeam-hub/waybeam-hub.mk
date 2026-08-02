###############################################################################
#
# waybeam-hub (ground station — built from source)
#
# Locally built via WAYBEAM_HUB_OVERRIDE_SRCDIR (set in waybeam-local.mk).
# The github SITE is a fallback for CI where the override isn't set.
#
###############################################################################

WAYBEAM_HUB_VERSION = 9f4c215b4354ada6c8e7ebafe436fc94629b0335
WAYBEAM_HUB_SITE = $(call github,snokvist,waybeam-hub,$(WAYBEAM_HUB_VERSION))
WAYBEAM_HUB_DEPENDENCIES = rockchip-mpp gstreamer1 gst1-plugins-base \
	libdrm eudev libgpiod cjson libcurl libpng librga

ifeq ($(BR2_PACKAGE_MESA3D),y)
WAYBEAM_HUB_DEPENDENCIES += mesa3d
endif

# waybeam-hub Makefile uses pkg-config to discover flags — do not override CFLAGS/LDFLAGS
define WAYBEAM_HUB_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) ground \
		CC="$(TARGET_CC)" \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)"
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
