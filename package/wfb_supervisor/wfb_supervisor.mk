WFB_SUPERVISOR_VERSION = main
WFB_SUPERVISOR_SITE = https://github.com/snokvist/wfb_supervisor.git
WFB_SUPERVISOR_SITE_METHOD = git
WFB_SUPERVISOR_LICENSE = Proprietary

# Simple C build, no extra deps

define WFB_SUPERVISOR_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)"
endef

define WFB_SUPERVISOR_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/wfb_supervisor $(TARGET_DIR)/usr/bin/wfb_supervisor
	$(INSTALL) -D -m 0755 $(@D)/scripts/monitor.sh $(TARGET_DIR)/usr/bin/monitor.sh
	$(INSTALL) -D -m 0755 $(@D)/scripts/shaper.sh $(TARGET_DIR)/usr/bin/shaper.sh
	$(INSTALL) -D -m 0644 $(@D)/config/wfb.conf $(TARGET_DIR)/etc/wfb.conf
endef

ifeq ($(BR2_INIT_SYSTEMD),y)
define WFB_SUPERVISOR_INSTALL_SYSTEMD_SERVICE
	$(INSTALL) -D -m 0644 $(@D)/scripts/wfb_supervisor.service \
		$(TARGET_DIR)/usr/lib/systemd/system/wfb_supervisor.service
	$(SED) 's|@WFB_SUPERVISOR_BIN@|/usr/bin/wfb_supervisor|g' \
		$(TARGET_DIR)/usr/lib/systemd/system/wfb_supervisor.service
	$(SED) 's|@WFB_SUPERVISOR_CONF@|/etc/wfb.conf|g' \
		$(TARGET_DIR)/usr/lib/systemd/system/wfb_supervisor.service
	$(SED) 's|@VRX_DIR@|/etc|g' \
		$(TARGET_DIR)/usr/lib/systemd/system/wfb_supervisor.service
endef
WFB_SUPERVISOR_INSTALL_TARGET_CMDS += $(WFB_SUPERVISOR_INSTALL_SYSTEMD_SERVICE)
endif

$(eval $(generic-package))
