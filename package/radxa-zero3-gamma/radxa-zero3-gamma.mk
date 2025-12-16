################################################################################
#
# radxa-zero3-gamma
#
################################################################################

RADXA_ZERO3_GAMMA_VERSION = main
RADXA_ZERO3_GAMMA_SITE = https://github.com/snokvist/radxa-zero3-gamma.git
RADXA_ZERO3_GAMMA_SITE_METHOD = git
RADXA_ZERO3_GAMMA_LICENSE = Proprietary

RADXA_ZERO3_GAMMA_DEPENDENCIES = libdrm

define RADXA_ZERO3_GAMMA_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		DEFAULT_CRTC="$(BR2_PACKAGE_RADXA_ZERO3_GAMMA_DEFAULT_CRTC)" \
		PREFIX="/usr" \
		CFLAGS="$(TARGET_CFLAGS)" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define RADXA_ZERO3_GAMMA_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		DESTDIR="$(TARGET_DIR)" \
		PREFIX="/usr" \
		install
ifeq ($(BR2_PACKAGE_RADXA_ZERO3_GAMMA_INSTALL_PRESETS),y)
	$(INSTALL) -D -m 0644 $(@D)/presets.ini $(TARGET_DIR)/etc/gamma-presets.ini
endif
endef

$(eval $(generic-package))

