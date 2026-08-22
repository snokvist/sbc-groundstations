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
# Bumped to a commit that HAS node/ — the pin is what CI builds, since
# WAYBEAM_LINK_OVERRIDE_SRCDIR resolves to empty without a sibling checkout.
# The previous pin (1b00c5a) predates the node layer entirely: zero files under
# node/, so it cannot produce libwblink_node.a or the header mod_wblink.c
# includes. With the standalone daemon now retired, a CI image built on that
# pin would have had no in-process link AND no binary — no RF claimant at all.
WAYBEAM_LINK_VERSION = f4d66c4
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
#
# WBLINK_DEVOURER_CHIPS=all is deliberate and costs binary size. A GROUND may
# meet any craft in the fleet, so it carries every USB chip family; a craft
# knows its own adapter and pins a single one. The cmake default is `fleet`
# (8812AU/CU/EU), which silently omits the RTL8733BU — an adapter that would
# then simply never be claimed, with no build-time complaint. Matches the
# posture documented in waybeam-hub's CLAUDE.md for the `ground` target.
WAYBEAM_LINK_CONF_OPTS = \
	-DWBLINK_BUILD_TESTS=OFF \
	-DWBLINK_RADIO=ON \
	-DWBLINK_DEVOURER_CHIPS=all

# THIS PACKAGE NO LONGER SHIPS A DAEMON. The link runs IN-PROCESS inside
# waybeam-hub (mod_wblink), which links the static archives this package builds
# — so what it provides the image is a CONFIG, and what it provides the build is
# libwblink_{core,io,node}.a plus vendored devourer/libusb. See
# WAYBEAM_HUB_DEPENDENCIES in the waybeam-hub package.
#
# Neither /usr/bin/waybeam-link nor files/S49waybeam-link is installed: the
# in-process node and a standalone daemon would both claim the same adapter.
# Both stay in the tree as the reference for a fallback — run
# `waybeam-link rx -c /etc/waybeam-link/rx.json` from a build output after
# setting wblink.enabled=false AND pixelpilot.frame_shm.source="ring" TOGETHER
# (either alone leaves you with no video). If you reinstate the init script,
# note rcS globs /etc/init.d/S??*, so disabling it again means renaming OUT of
# that glob (K49...), not suffixing it.
#
# The explicit `rm -f`s below are NOT redundant with dropping the INSTALL lines,
# and were added after measuring the difference. TARGET_DIR is cumulative — in
# per-package mode too — so on any tree that has built this package before,
# deleting an install command leaves the previously installed file sitting in
# the rootfs. The recipe was already correct and the stale file shipped anyway;
# only a from-scratch build would have cleared it, which is exactly the kind of
# dev-tree-vs-release-build difference nobody notices until an image boots two
# link claimants.
define WAYBEAM_LINK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(WAYBEAM_LINK_PKGDIR)/files/rx.json \
		$(TARGET_DIR)/etc/waybeam-link/rx.json
	$(INSTALL) -D -m 0644 $(WAYBEAM_LINK_PKGDIR)/files/table.json \
		$(TARGET_DIR)/etc/waybeam-link/table.json
endef

$(eval $(cmake-package))
