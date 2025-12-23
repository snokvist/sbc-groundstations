################################################################################
#
# radxa-zero3-gamma
#
################################################################################

RADXA_ZERO3_GAMMA_VERSION = 5ef5b5daf94b0f2b4f80ad4032a7c6315e2dfbbf
RADXA_ZERO3_GAMMA_SITE = https://github.com/snokvist/radxa-zero3-gamma.git
RADXA_ZERO3_GAMMA_SITE_METHOD = git
RADXA_ZERO3_GAMMA_LICENSE = Proprietary
RADXA_ZERO3_GAMMA_DEPENDENCIES = libdrm

define RADXA_ZERO3_GAMMA_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		DEFAULT_CRTC="$(BR2_PACKAGE_RADXA_ZERO3_GAMMA_DEFAULT_CRTC)" \
		PREFIX="/usr" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include/libdrm"
endef

define RADXA_ZERO3_GAMMA_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		DESTDIR="$(TARGET_DIR)" \
		PREFIX="/usr" \
		install
	$(INSTALL) -D -m 0644 $(@D)/presets.ini $(TARGET_DIR)/etc/gamma-presets.ini
endef

$(eval $(generic-package))
