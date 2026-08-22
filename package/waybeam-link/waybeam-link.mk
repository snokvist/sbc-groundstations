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
WAYBEAM_LINK_VERSION = 1b00c5a845f51da0440e763fd689a3a249a44ecc
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

# files/S49waybeam-link is DELIBERATELY not installed below. waybeam-hub runs
# this node in-process (`wblink.enabled`, waybeam-hub #218), and the two must
# never both claim the adapter. The binary and configs still ship, so a
# standalone fallback is one command away —
# `waybeam-link rx -c /etc/waybeam-link/rx.json` — after setting
# wblink.enabled=false and pixelpilot.frame_shm.source="ring" TOGETHER.
#
# The script stays in the tree as the reference for that fallback. If you
# reinstate it, note rcS globs /etc/init.d/S??*, so disabling it again means
# renaming OUT of that glob (K49...), not suffixing it.
#
# The explicit `rm -f` below is NOT redundant with simply dropping the INSTALL
# line, and was added after measuring the difference. TARGET_DIR is cumulative
# — in per-package mode too — so on any tree that has built this package
# before, deleting the install command leaves the previously installed
# S49waybeam-link sitting in the rootfs. The recipe was already correct and the
# stale file shipped anyway. Only a from-scratch build would have cleared it,
# which is exactly the kind of difference between a dev tree and a release
# build that nobody notices until an image boots two link claimants.
define WAYBEAM_LINK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/waybeam-link $(TARGET_DIR)/usr/bin/waybeam-link
	$(INSTALL) -D -m 0644 $(WAYBEAM_LINK_PKGDIR)/files/rx.json \
		$(TARGET_DIR)/etc/waybeam-link/rx.json
	$(INSTALL) -D -m 0644 $(WAYBEAM_LINK_PKGDIR)/files/table.json \
		$(TARGET_DIR)/etc/waybeam-link/table.json
	rm -f $(TARGET_DIR)/etc/init.d/S49waybeam-link
endef

$(eval $(cmake-package))
