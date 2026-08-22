###############################################################################
#
# waybeam-hub (ground station — built from source)
#
# Locally built via WAYBEAM_HUB_OVERRIDE_SRCDIR (set in waybeam-local.mk).
# The github SITE is a fallback for CI where the override isn't set.
#
###############################################################################

# Bumped to a commit whose Makefile knows WBLINK at all. The previous pin
# (1491fb2) has ZERO WBLINK references, so the variables passed below were
# silently ignored and CI shipped a hub with no in-process node.
# NOTE: mod_gpio lands with waybeam-hub #219 — bump again once that merges, or
# the gpio block in waybeam_ground.conf stays inert on CI images.
WAYBEAM_HUB_VERSION = e3d0799
WAYBEAM_HUB_SITE = $(call github,snokvist,waybeam-hub,$(WAYBEAM_HUB_VERSION))
WAYBEAM_HUB_DEPENDENCIES = rockchip-mpp gstreamer1 gst1-plugins-base \
	libdrm eudev libgpiod cjson libcurl libpng librga

ifeq ($(BR2_PACKAGE_MESA3D),y)
WAYBEAM_HUB_DEPENDENCIES += mesa3d
endif

# The link is IN-PROCESS on this image (mod_wblink), so the hub links
# waybeam-link's static archives and there is no standalone link daemon. That
# makes waybeam-link a BUILD dependency, not just another package that happens
# to be installed — without the ordering, the archives may not exist when the
# hub links.
ifeq ($(BR2_PACKAGE_WAYBEAM_LINK),y)
WAYBEAM_HUB_DEPENDENCIES += waybeam-link
endif

# WBLINK_SRCDIR must be passed explicitly. The hub Makefile defaults it to
# `../waybeam-link`, which is correct for a side-by-side developer checkout but
# resolves to nothing inside buildroot, where the sibling is named
# `waybeam-link-custom`. The failure was not obvious: mod_wblink.c stopped at
# `fatal error: wblink/node/rx_node_c.h: No such file or directory`, the link
# step never ran, and the STALE binary from the previous build stayed in place
# — so `make` reported an error while the image still contained a working (but
# months-old) hub.
#
# Both variables point at the same directory because buildroot builds
# waybeam-link in-tree: the sources (node/include) and the cmake outputs
# (libwblink_*.a, devourer/, libusb/) share $(WAYBEAM_LINK_DIR).
#
# waybeam-hub Makefile uses pkg-config to discover flags — do not override CFLAGS/LDFLAGS
# WBLINK=0 when the link package is not selected. powkiddy_rgb20pro enables the
# hub WITHOUT waybeam-link, and an unconditional dependency there would both
# drag the retired daemon back into that rootfs (per-package dirs are
# hardlink-rsynced into dependents) and ask the hub to link archives nothing
# built.
ifeq ($(BR2_PACKAGE_WAYBEAM_LINK),y)
WAYBEAM_HUB_WBLINK_ARGS = WBLINK=1 \
	WBLINK_SRCDIR="$(WAYBEAM_LINK_DIR)" \
	WBLINK_GROUND_BUILDDIR="$(WAYBEAM_LINK_DIR)"
else
WAYBEAM_HUB_WBLINK_ARGS = WBLINK=0
endif

define WAYBEAM_HUB_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) ground \
		CC="$(TARGET_CC)" \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		$(WAYBEAM_HUB_WBLINK_ARGS)
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
