###############################################################################
#
# waybeam-link (ground station — built from source)
#
# Best-effort latency-first broadcast video + telemetry link over
# monitor/injection WiFi (RTL8812AU/CU/EU). Replaces wfb-ng on the waybeam
# ground image; the RX role delivers recovered RTP to 127.0.0.1:5600, which
# waybeam-hub's embedded decoder consumes.
#
# Private repo. Built locally via WAYBEAM_LINK_OVERRIDE_SRCDIR (set in
# waybeam-local.mk); the github SITE is a fallback for environments that can
# authenticate to the private repo. Mirrors the waybeam-hub packaging pattern.
#
###############################################################################
WAYBEAM_LINK_VERSION = 21f734a05900e0a4ca9439aa6fe69e409e658985
WAYBEAM_LINK_SITE = $(call github,snokvist,waybeam-link,$(WAYBEAM_LINK_VERSION))
WAYBEAM_LINK_LICENSE = GPL-2.0-or-later
WAYBEAM_LINK_LICENSE_FILES = LICENSE

# Vendored radio stack (third_party/devourer + third_party/libusb-cmake) builds
# in-tree — no system libusb dependency. C++20 needs a recent host cmake, which
# Buildroot provides via the cmake-package infrastructure.
WAYBEAM_LINK_DEPENDENCIES = host-pkgconf

# Ship the radio air backend (devourer, WBLINK_RADIO=ON by default); drop unit
# tests. The frame-shm/gst bench tools are already gated NOT CMAKE_CROSSCOMPILING
# in CMakeLists, so they never build in this cross package.
WAYBEAM_LINK_CONF_OPTS = \
	-DWBLINK_BUILD_TESTS=OFF \
	-DWBLINK_RADIO=ON

# The §10.7 (Pass 125) calibration artifact directory is created here because
# the store writes atomically (tmp + rename) and does NOT create its parent —
# without it every ground calibration would seek correctly and then fail to
# persist. It ships EMPTY by design: an artifact is measured per-unit against
# specific hardware and auto-applies only on an identity match, so shipping
# one would be shipping a placement for someone else's radio.
# (Comments live outside the define: lines inside are handed to the shell and
# echoed into the build log.)
define WAYBEAM_LINK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/waybeam-link $(TARGET_DIR)/usr/bin/waybeam-link
	$(INSTALL) -D -m 0644 $(WAYBEAM_LINK_PKGDIR)/files/rx.json \
		$(TARGET_DIR)/etc/waybeam-link/rx.json
	$(INSTALL) -D -m 0644 $(WAYBEAM_LINK_PKGDIR)/files/table.json \
		$(TARGET_DIR)/etc/waybeam-link/table.json
	$(INSTALL) -D -m 0755 $(WAYBEAM_LINK_PKGDIR)/files/S49waybeam-link \
		$(TARGET_DIR)/etc/init.d/S49waybeam-link
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/waybeam-link/calibration
endef

$(eval $(cmake-package))
