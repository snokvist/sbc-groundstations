################################################################################
#
# wifibroadcast-ng
#
################################################################################
WFB_BINS_ONLY_VERSION = 7ffc689e3f1194dca79dca4b5b56ee560c0cc3be
WFB_BINS_ONLY_SITE = https://github.com/svpcom/wfb-ng.git
WFB_BINS_ONLY_SITE_METHOD = git
WFB_BINS_ONLY_LICENSE = GPL-3.0

WFB_BINS_ONLY_DEPENDENCIES = libpcap libsodium libevent

define WFB_BINS_ONLY_BUILD_CMDS
	$(MAKE) CC=$(TARGET_CC) CXX=$(TARGET_CXX) LDFLAGS=-s -C $(@D) all_bin
endef

define WFB_BINS_ONLY_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WIFIBROADCAST_NG_PKGDIR)/files/gs.key
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WIFIBROADCAST_NG_PKGDIR)/files/drone.key

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/wfb_rx
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/wfb_tx
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/wfb_tx_cmd
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/wfb_tun
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/wfb_keygen

	echo 'WIFIBROADCAST_ENABLED=true' >> $(TARGET_DIR)/etc/default/wifibroadcast

endef

$(eval $(generic-package))
