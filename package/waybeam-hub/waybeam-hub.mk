###############################################################################
#
# waybeam-hub (ground station build)
#
###############################################################################

WAYBEAM_HUB_VERSION = 82c509476de097dd58f9f2af179c60db063a114f
WAYBEAM_HUB_SITE = https://github.com/snokvist/waybeam-hub.git
WAYBEAM_HUB_SITE_METHOD = git
WAYBEAM_HUB_GIT_SUBMODULES = YES
WAYBEAM_HUB_INSTALL_STAGING = NO
WAYBEAM_HUB_INSTALL_TARGET = YES
WAYBEAM_HUB_DEPENDENCIES = gstreamer1 gst1-plugins-base rockchip-mpp libdrm eudev libpng

WAYBEAM_HUB_MAKE_ENV = \
	CC="$(TARGET_CC)" \
	PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
	PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig:$(STAGING_DIR)/usr/share/pkgconfig" \
	PKG_CONFIG_SYSROOT_DIR="$(STAGING_DIR)"

define WAYBEAM_HUB_BUILD_CMDS
	$(WAYBEAM_HUB_MAKE_ENV) $(MAKE) -C $(@D) ground
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
