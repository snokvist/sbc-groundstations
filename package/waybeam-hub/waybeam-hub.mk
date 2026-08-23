###############################################################################
#
# waybeam-hub (ground station — built from source)
#
# Locally built via WAYBEAM_HUB_OVERRIDE_SRCDIR (set in waybeam-local.mk).
# The github SITE is a fallback for CI where the override isn't set.
#
###############################################################################

# The PIN is what CI builds — WAYBEAM_HUB_OVERRIDE_SRCDIR resolves to empty
# without a sibling checkout — so it has to be verified, not assumed. An earlier
# pin (1491fb2) had ZERO `WBLINK` references in its Makefile, so the variables
# passed below were silently ignored and CI shipped a hub with no in-process
# node while the recipe looked correct.
#
# d9631be = waybeam-hub #219 (mod_gpio). Checked before pinning: on origin/main,
# 89 WBLINK references in its Makefile, and src/mod_gpio.{c,h} present — without
# the latter the gpio block in waybeam_ground.conf is inert on CI images.
WAYBEAM_HUB_VERSION = d9631be
WAYBEAM_HUB_SITE = $(call github,snokvist,waybeam-hub,$(WAYBEAM_HUB_VERSION))
WAYBEAM_HUB_DEPENDENCIES = rockchip-mpp gstreamer1 gst1-plugins-base \
	libdrm eudev libgpiod cjson libcurl libpng librga

ifeq ($(BR2_PACKAGE_MESA3D),y)
WAYBEAM_HUB_DEPENDENCIES += mesa3d
endif

# The link is IN-PROCESS on every image that ships the hub (mod_wblink): the hub
# links waybeam-link's static archives and no standalone link daemon is
# installed. That makes waybeam-link a BUILD dependency, not just another
# package that happens to be installed — without the ordering, the archives may
# not exist when the hub links.
#
# Unconditional, and a hub selected WITHOUT the link is a hard error rather than
# a quietly linkless build. The silent path is not hypothetical: CI shipped a
# hub with no in-process node for a month because the variables below were
# passed to a pin whose Makefile ignored them, and nothing failed.
ifeq ($(BR2_PACKAGE_WAYBEAM_HUB),y)
ifneq ($(BR2_PACKAGE_WAYBEAM_LINK),y)
$(error waybeam-hub requires BR2_PACKAGE_WAYBEAM_LINK — the radio link runs in-process (mod_wblink) and the hub links waybeam-link's static archives)
endif
endif

WAYBEAM_HUB_DEPENDENCIES += waybeam-link

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
WAYBEAM_HUB_WBLINK_ARGS = WBLINK=1 \
	WBLINK_SRCDIR="$(WAYBEAM_LINK_DIR)" \
	WBLINK_GROUND_BUILDDIR="$(WAYBEAM_LINK_DIR)"

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
