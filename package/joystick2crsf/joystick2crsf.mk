################################################################################
#
# joystick2crsf
#
################################################################################

JOYSTICK2CRSF_VERSION = 2210280fad1d00a0f8951d8f27ced62a01b0b4d6
JOYSTICK2CRSF_SITE = https://github.com/snokvist/joystick2crsf.git
JOYSTICK2CRSF_SITE_METHOD = git
JOYSTICK2CRSF_LICENSE = Proprietary

# Uses pkg-config to find SDL2 at build time
JOYSTICK2CRSF_DEPENDENCIES = host-pkgconf sdl2

define JOYSTICK2CRSF_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		$(MAKE) -C $(@D) \
			CC="$(TARGET_CC)" \
			PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
			TARGET="joystick2crsf"
endef

define JOYSTICK2CRSF_INSTALL_TARGET_CMDS
	# Binary
	$(INSTALL) -D -m 0755 $(@D)/joystick2crsf \
		$(TARGET_DIR)/usr/bin/joystick2crsf

	# Default config
	$(INSTALL) -D -m 0644 $(@D)/joystick2crfs.conf \
		$(TARGET_DIR)/etc/joystick2crsf.conf
endef

# SysV init script (always installed; harmless if not used)
define JOYSTICK2CRSF_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(@D)/S96joystick2crsf \
		$(TARGET_DIR)/etc/init.d/S96joystick2crsf
endef

$(eval $(generic-package))
