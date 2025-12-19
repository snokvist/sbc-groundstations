WFB_SUPERVISOR_VERSION = 99ef2105b8b075809d5fed1f4f8ea9396ce0b18a
#main
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

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WFB_SUPERVISOR_PKGDIR)/files/cluster_supervisor.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WFB_SUPERVISOR_PKGDIR)/files/wfb.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WFB_SUPERVISOR_PKGDIR)/files/wifi_supervisor.conf

	# Wrapper "alias" that forces a config
	$(INSTALL) -D -m 0755 /dev/null $(TARGET_DIR)/usr/bin/wifi_supervisor
	printf '%s\n' '#!/bin/sh' \
		'exec /usr/bin/wfb_supervisor /etc/wifi_supervisor.conf "$$@"' \
		> $(TARGET_DIR)/usr/bin/wifi_supervisor
	$(INSTALL) -D -m 0755 /dev/null $(TARGET_DIR)/usr/bin/cluster_supervisor
	printf '%s\n' '#!/bin/sh' \
		'exec /usr/bin/wfb_supervisor /etc/cluster_supervisor.conf "$$@"' \
		> $(TARGET_DIR)/usr/bin/wifi_supervisor

endef

$(eval $(generic-package))
