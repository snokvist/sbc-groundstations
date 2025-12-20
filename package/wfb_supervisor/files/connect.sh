#!/bin/sh
set -eu

IFACE="${IFACE:-wlan0}"

# Where to keep runtime state
WPACONF="/tmp/wpa_supplicant.conf"
WPAPID="/var/run/wpa_supplicant.${IFACE}.pid"
UDHCPPID="/var/run/udhcpc.${IFACE}.pid"
UDHCPSCRIPT="/usr/share/udhcpc/default.script"

# -------- helpers --------

fw_get() {
    # fw_get <var> <default>
    fw_printenv -n "$1" 2>/dev/null || echo "$2"
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_udhcpc_script() {
    if [ -x "$UDHCPSCRIPT" ]; then
        return 0
    fi

    # Fallback minimal udhcpc script
    UDHCPSCRIPT="/tmp/udhcpc.script"
    cat >"$UDHCPSCRIPT" <<'EOF'
#!/bin/sh
[ -n "$interface" ] || interface="$1"
case "$1" in
  deconfig)
    ip addr flush dev "$interface" 2>/dev/null || true
    ;;
  bound|renew)
    ip addr flush dev "$interface" 2>/dev/null || true
    ip addr add "$ip/$subnet" dev "$interface"
    ip link set "$interface" up
    ip route replace default via "$router" dev "$interface" 2>/dev/null || true
    # DNS
    : > /etc/resolv.conf
    for s in $dns; do
      echo "nameserver $s" >> /etc/resolv.conf
    done
    ;;
esac
exit 0
EOF
    chmod +x "$UDHCPSCRIPT"
}

set_config() {
    SSID="$(fw_printenv -n wlanssid 2>/dev/null || echo waybeam-01)"
    PSK="$(fw_printenv -n wlanpass 2>/dev/null || echo waybeam-01)"
    FREQ="$(fw_printenv -n wlanfreq 2>/dev/null || echo 5805)"   # e.g. 5805 for ch161

    # Write wpa_supplicant config
    cat > "$WPACONF" <<EOF
update_config=0

network={
    ssid="$SSID"
    psk="$PSK"
    key_mgmt=WPA-PSK
    proto=RSN
    pairwise=CCMP
    group=CCMP
EOF

    # Only restrict frequency if user provided one
    if [ -n "$FREQ" ] && [ "$FREQ" != "0" ]; then
        echo "    freq_list=$FREQ" >> "$WPACONF"
    fi

    echo "}" >> "$WPACONF"

    # Only enable the control socket if wpa_cli exists
    if have wpa_cli; then
        # Put it at the top of the file
        tmp="${WPACONF}.tmp"
        {
            echo "ctrl_interface=/var/run/wpa_supplicant"
            cat "$WPACONF"
        } > "$tmp"
        mv -f "$tmp" "$WPACONF"
    fi
}



detect_and_load_driver() {
    driver=""

    # Scan USB IDs (VID:PID)
    for card in $(lsusb 2>/dev/null | awk '{print $6}' | sort -u); do
        case "$card" in
            # MediaTek / Ralink MT7612U (common IDs)
            "148f:7612"|"148f:761a"|"0e8d:7612"|"0e8d:761a")
                driver="mt76x2u"
                ;;

            # Your earlier Realtek examples (keep if you want multi-adapter support)
            "0bda:8812"|"0bda:881a"|"0b05:17d2"|"2357:0101"|"2604:0012")
                driver="8812au"
                ;;
            "0bda:a81a")
                driver="8812eu"
                ;;
            "0bda:f72b"|"0bda:b733")
                driver="8733bu"
                ;;
        esac
    done

    if [ -z "$driver" ]; then
        echo "Wireless module not detected (lsusb)."
        echo "Tip: if this is not USB or lsusb isn't available, set DRIVER=... in env."
        driver="${DRIVER:-}"
    fi

    if [ -z "$driver" ]; then
        exit 1
    fi

    echo "Detected/selected driver: $driver"

    # Load module (ignore if already loaded)
    if have modprobe; then
        modprobe "$driver" 2>/dev/null || true
    fi
}

start_client() {
    if ! have ip || ! have iw || ! have wpa_supplicant; then
        echo "Missing required tools (need ip/iw/wpa_supplicant)."
        exit 1
    fi

    # Optional TX power (mBm, same style as your template)
    # e.g. 1500 = 15.00 dBm
    PWR="$(fw_get wlanpwr "1500")"

    echo "[wifi] Bringing up $IFACE"
    ip link set "$IFACE" up 2>/dev/null || true
    ip addr flush dev "$IFACE" 2>/dev/null || true

    # Set txpower if supported
    iw "$IFACE" set txpower fixed "$PWR" 2>/dev/null || true

    set_config

    # Stop any existing instance
    killall -q wpa_supplicant 2>/dev/null || true

    echo "[wifi] Starting wpa_supplicant on $IFACE"
    wpa_supplicant -B -i "$IFACE" -c "$WPACONF" -P "$WPAPID"

    # DHCP client
    ensure_udhcpc_script

    if have udhcpc; then
        echo "[wifi] Starting DHCP client (udhcpc) on $IFACE"
        # -b background, -p pidfile, -s script
        # You can add "-t 5 -T 2" to tune retries/timeouts
        udhcpc -i "$IFACE" -b -p "$UDHCPPID" -s "$UDHCPSCRIPT"
    elif have dhcpcd; then
        echo "[wifi] Starting DHCP client (dhcpcd) on $IFACE"
        dhcpcd -B "$IFACE"
    else
        echo "[wifi] No DHCP client found (need udhcpc or dhcpcd)."
        exit 1
    fi

    echo "[wifi] Started. Config: SSID=$(fw_get wlanssid "OpenIPC") FREQ=$(fw_get wlanfreq "5200")"
}

stop_client() {
    echo "[wifi] Stopping DHCP client"
    if [ -f "$UDHCPPID" ]; then
        kill "$(cat "$UDHCPPID")" 2>/dev/null || true
        rm -f "$UDHCPPID"
    fi
    killall -q udhcpc dhcpcd 2>/dev/null || true

    echo "[wifi] Stopping wpa_supplicant"
    if [ -f "$WPAPID" ]; then
        kill "$(cat "$WPAPID")" 2>/dev/null || true
        rm -f "$WPAPID"
    fi
    killall -q wpa_supplicant 2>/dev/null || true

    echo "[wifi] Clearing $IFACE"
    ip addr flush dev "$IFACE" 2>/dev/null || true
    ip link set "$IFACE" down 2>/dev/null || true
}

status_client() {
    echo "=== link ==="
    ip link show "$IFACE" || true
    echo "=== addr ==="
    ip -4 addr show dev "$IFACE" || true
    echo "=== wpa ==="
    if have wpa_cli; then
        wpa_cli -i "$IFACE" status || true
    else
        ps | grep "[w]pa_supplicant" || true
    fi
}

case "${1:-}" in
    setup)
        detect_and_load_driver
        ;;
    start)
        start_client
        ;;
    stop)
        stop_client
        ;;
    restart)
        stop_client
        start_client
        ;;
    status)
        status_client
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|restart|status}"
        echo "Env overrides: IFACE=wlan0 DRIVER=mt76x2u"
        exit 1
        ;;
esac
