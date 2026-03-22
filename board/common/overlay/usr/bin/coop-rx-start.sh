#!/bin/sh
#
# coop-rx-start.sh — Legacy wrapper, delegates to waybeam-wifi.sh
#
# Usage: coop-rx-start.sh [SSID] [PSK]
#   If arguments are provided, they are ignored — network list is now
#   configured in /etc/waybeam-wifi.conf
#
exec /usr/bin/waybeam-wifi.sh coop-start
