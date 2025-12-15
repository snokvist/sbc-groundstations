################################################################################
#
# ip2uart
#
################################################################################

IP2UART_VERSION = main
IP2UART_SITE = https://github.com/snokvist/ip2uart.git
IP2UART_SITE_METHOD = git
IP2UART_LICENSE = Proprietary

define IP2UART_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		$(MAKE) -C $(@D) \
			CROSS_COMPILE="$(TARGET_CROSS)" \
			PREFIX="/usr"
endef

define IP2UART_INSTALL_TARGET_CMDS
	# Binary -> /usr/sbin
	$(INSTALL) -D -m 0755 $(@D)/ip2uart \
		$(TARGET_DIR)/usr/bin/ip2uart

	# Default config
	$(INSTALL) -D -m 0644 $(@D)/ip2uart.conf \
		$(TARGET_DIR)/etc/ip2uart.conf
endef

define IP2UART_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(@D)/S96ip2uart \
		$(TARGET_DIR)/etc/init.d/S96ip2uart
endef

$(eval $(generic-package))
