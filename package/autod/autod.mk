################################################################################
#
# autod
#
################################################################################

AUTOD_VERSION = 640747bb6d405c008062f2fdfbe4f069b8eb71dd
AUTOD_SITE = https://github.com/snokvist/autod.git
AUTOD_SITE_METHOD = git
AUTOD_LICENSE = Proprietary

# No external deps needed (civetweb/parson are vendored); links pthread only.

define AUTOD_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CFLAGS="$(TARGET_CFLAGS)" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		$(MAKE) -C $(@D) \
			CC="$(TARGET_CC)" \
			STRIP="$(TARGET_STRIP)" \
			PREFIX="/usr"
endef

define AUTOD_INSTALL_TARGET_CMDS
	# Binary
	$(INSTALL) -D -m 0755 $(@D)/autod \
		$(TARGET_DIR)/usr/bin/autod

	# VRX UI directory
	$(INSTALL) -d $(TARGET_DIR)/usr/share/autod/vrx

	# VRX index
	$(INSTALL) -D -m 0644 $(@D)/html/autod/vrx_index.html \
		$(TARGET_DIR)/usr/share/autod/vrx/vrx_index.html

	# Assets (copy full tree)
	cp -a $(@D)/html/autod/assets \
		$(TARGET_DIR)/usr/share/autod/vrx/

	# Exec handler + optional .msg helpers
	$(INSTALL) -D -m 0755 $(@D)/scripts/vrx/exec-handler.sh \
		$(TARGET_DIR)/usr/share/autod/vrx/exec-handler.sh
	@if ls $(@D)/scripts/vrx/*.msg >/dev/null 2>&1; then \
		$(INSTALL) -d $(TARGET_DIR)/usr/share/autod/vrx; \
		for f in $(@D)/scripts/vrx/*.msg; do \
			$(INSTALL) -m 0644 $$f $(TARGET_DIR)/usr/share/autod/vrx/; \
		done; \
	fi

	# Config
	$(INSTALL) -d $(TARGET_DIR)/etc/autod
	$(INSTALL) -m 0644 $(@D)/configs/autod.conf \
		$(TARGET_DIR)/etc/autod/autod.conf

	# Patch config to point to installed paths
	$(SED) 's|^interpreter=.*|interpreter=/usr/share/autod/vrx/exec-handler.sh|' \
		$(TARGET_DIR)/etc/autod/autod.conf
	$(SED) 's|^ui_path=.*|ui_path=/usr/share/autod/vrx/vrx_index.html|' \
		$(TARGET_DIR)/etc/autod/autod.conf
endef

# SysV init (BusyBox/sysvinit)
define AUTOD_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(AUTOD_PKGDIR)/files/S99autod \
		$(TARGET_DIR)/etc/init.d/S99autod
endef

$(eval $(generic-package))
