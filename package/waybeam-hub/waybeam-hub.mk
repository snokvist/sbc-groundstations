###############################################################################
#
# waybeam-hub (ground station — built from source)
#
# Source comes from local override (WAYBEAM_HUB_OVERRIDE_SRCDIR) since
# the repo is private. Set in waybeam-local.mk.
#
###############################################################################

WAYBEAM_HUB_VERSION = 1.0
WAYBEAM_HUB_SITE_METHOD = local
WAYBEAM_HUB_SITE = $(WAYBEAM_HUB_OVERRIDE_SRCDIR)
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
