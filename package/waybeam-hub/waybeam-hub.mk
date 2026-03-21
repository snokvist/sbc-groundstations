###############################################################################
#
# waybeam-hub (ground station — pre-built aarch64 binary)
#
# Binary published by waybeam-hub CI to snokvist/waybeam-releases on every
# push to main.  Tag format: waybeam-hub-ground-<sha8>
# Update WAYBEAM_HUB_VERSION to the short SHA of the desired waybeam-hub
# commit when bumping.
#
###############################################################################

WAYBEAM_HUB_VERSION = cfbc9003
WAYBEAM_HUB_SITE = https://github.com/snokvist/waybeam-releases/releases/download/waybeam-hub-ground-$(WAYBEAM_HUB_VERSION)
WAYBEAM_HUB_SITE_METHOD = wget
WAYBEAM_HUB_SOURCE = waybeam_hub_ground.tar.gz
WAYBEAM_HUB_STRIP_COMPONENTS = 0
WAYBEAM_HUB_INSTALL_STAGING = NO
WAYBEAM_HUB_INSTALL_TARGET = YES

define WAYBEAM_HUB_BUILD_CMDS
	@true # pre-built binary
endef

define WAYBEAM_HUB_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/waybeam_hub \
		$(TARGET_DIR)/usr/bin/waybeam_hub

	$(INSTALL) -D -m 0644 $(WAYBEAM_HUB_PKGDIR)/files/waybeam_ground.conf \
		$(TARGET_DIR)/etc/waybeam_hub.conf

	$(INSTALL) -D -m 0755 $(WAYBEAM_HUB_PKGDIR)/files/S99waybeam_hub \
		$(TARGET_DIR)/etc/init.d/S99waybeam_hub
endef

$(eval $(generic-package))
