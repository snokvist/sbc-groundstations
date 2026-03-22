#!/bin/sh
#
# waybeam-wifi.sh — Waybeam ground station WiFi manager
#
# Supports STA and AP modes, multi-driver (RTL8812CU/EU/AU, MediaTek, etc.),
# cooperative RX diversity with automatic helper lifecycle management.
#
# Usage: waybeam-wifi.sh {start|stop|restart|status|scan|coop-start|coop-stop|coop-status}
#

CONF="/etc/waybeam-wifi.conf"
TAG="waybeam-wifi"
MONITOR_PID="/var/run/waybeam-wifi-monitor.pid"
WPA_CONF="/tmp/waybeam_wpa.conf"
HOSTAPD_CONF="/tmp/waybeam_hostapd.conf"
UDHCPD_CONF="/tmp/waybeam_udhcpd_wifi.conf"
STATE_DIR="/var/run/waybeam-wifi"
LOG_FILE="/var/log/waybeam-wifi.log"

# ---------------------------------------------------------------------------
# Defaults (overridden by config)
# ---------------------------------------------------------------------------
WIFI_MODE="sta"
WIFI_NETWORKS=""
WIFI_PRIMARY_IFACE="auto"
WIFI_UDHCPC_SCRIPT="/etc/udhcpc/udhcpc.apfpv.script"
COOP_RX_ENABLED="auto"
COOP_RX_MONITOR_INTERVAL=5
WIFI_IFACE_WAIT=15
WIFI_ASSOC_TIMEOUT=15
WIFI_SCAN_RETRIES=3
WIFI_RECONNECT_TIMEOUT=60
AP_SSID="WaybeamGS"
AP_PSK="waybeamgs"
AP_CHANNEL=149
AP_COUNTRY="US"
AP_IP="192.168.4.1"
AP_NETMASK="255.255.255.0"
AP_DHCP_START="192.168.4.10"
AP_DHCP_END="192.168.4.20"

# ---------------------------------------------------------------------------
# Logging — stdout + syslog + log file
# ---------------------------------------------------------------------------
_log() {
    _lvl="$1"; shift
    _ts=$(date '+%H:%M:%S' 2>/dev/null)
    echo "[$TAG] $_lvl: $*"
    echo "$_ts $_lvl: $*" >> "$LOG_FILE" 2>/dev/null
    logger -t "$TAG" "$_lvl: $*" 2>/dev/null
}
log_info()  { _log "INFO" "$@"; }
log_warn()  { _log "WARN" "$@"; }
log_error() { _log "ERROR" "$@" >&2; }

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
load_config() {
    if [ -f "$CONF" ]; then
        . "$CONF"
    else
        log_warn "Config $CONF not found, using defaults"
    fi
    mkdir -p "$STATE_DIR"
    # Ensure debugfs is mounted (needed for coop RX counters)
    if [ ! -d /sys/kernel/debug/block ]; then
        mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    fi
    # Rotate log if over 100KB
    if [ -f "$LOG_FILE" ]; then
        _sz=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$_sz" -gt 102400 ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Interface discovery (driver-agnostic)
# ---------------------------------------------------------------------------

# List all WiFi interface names
discover_wifi_ifaces() {
    _ifaces=""
    for _phy in /sys/class/net/*/phy80211; do
        [ -d "$_phy" ] || continue
        _name=$(basename "$(dirname "$_phy")")
        case "$_name" in lo|eth*|usb*) continue ;; esac
        _ifaces="$_ifaces $_name"
    done
    echo "$_ifaces" | xargs
}

# Get the kernel driver name for an interface
get_iface_driver() {
    _drv_link="/sys/class/net/$1/device/driver"
    if [ -L "$_drv_link" ]; then
        basename "$(readlink "$_drv_link")"
    else
        echo "unknown"
    fi
}

# Wait for at least one WiFi interface to appear
wait_for_wifi_ifaces() {
    _waited=0
    while [ "$_waited" -lt "$WIFI_IFACE_WAIT" ]; do
        _found=$(discover_wifi_ifaces)
        if [ -n "$_found" ]; then
            log_info "WiFi interfaces found: $_found"
            return 0
        fi
        [ "$((_waited % 5))" -eq 0 ] && [ "$_waited" -gt 0 ] && \
            log_info "Waiting for WiFi interfaces... (${_waited}s)"
        sleep 1
        _waited=$((_waited + 1))
    done
    log_error "No WiFi interfaces found after ${WIFI_IFACE_WAIT}s"
    return 1
}

# Select the primary interface
select_primary_iface() {
    if [ "$WIFI_PRIMARY_IFACE" != "auto" ]; then
        if [ -d "/sys/class/net/$WIFI_PRIMARY_IFACE" ]; then
            echo "$WIFI_PRIMARY_IFACE"
            return 0
        fi
        log_warn "Configured interface $WIFI_PRIMARY_IFACE not found, falling back to auto"
    fi
    _all=$(discover_wifi_ifaces)
    echo "$_all" | awk '{print $1}'
}

# Find the interface currently connected (associated)
find_connected_iface() {
    for _if in $(discover_wifi_ifaces); do
        if iw dev "$_if" link 2>/dev/null | grep -q "Connected"; then
            echo "$_if"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Process management helpers (BusyBox-compatible, no pgrep)
# ---------------------------------------------------------------------------

# Find PIDs of a given process name matching an interface argument.
# Usage: _find_pids_for_iface <process_name> <interface>
# Outputs space-separated PIDs.
_find_pids_for_iface() {
    _proc_name="$1"
    _iface_arg="$2"
    # BusyBox ps w gives full command line; filter by process name and interface
    ps w 2>/dev/null | grep "$_proc_name" | grep -v grep | \
        grep -- "-i $_iface_arg" | awk '{print $1}'
}

_kill_wpa() {
    _pids=$(_find_pids_for_iface wpa_supplicant "$1")
    if [ -n "$_pids" ]; then
        kill $_pids 2>/dev/null || true
        sleep 1
    fi
    rm -f "/var/run/wpa_supplicant/$1"
}

_kill_udhcpc() {
    _pids=$(_find_pids_for_iface udhcpc "$1")
    [ -n "$_pids" ] && kill $_pids 2>/dev/null || true
}

# Check if wpa_supplicant is running for an interface
_wpa_running() {
    _pids=$(_find_pids_for_iface wpa_supplicant "$1")
    [ -n "$_pids" ]
}

# ---------------------------------------------------------------------------
# WPA supplicant config generation
# ---------------------------------------------------------------------------
generate_wpa_conf() {
    # Run in subshell to scope the umask change
    (
        umask 077
        _prio=100
        cat > "$WPA_CONF" <<'HEADER'
ap_scan=1

# Sticky connection: disable roaming, never let wpa_supplicant give up
bgscan=""
autoscan=periodic:3
HEADER

        echo "$WIFI_NETWORKS" | while IFS= read -r _line; do
            _line=$(echo "$_line" | xargs)
            [ -z "$_line" ] && continue

            _ssid="${_line%%:*}"
            _psk="${_line#*:}"
            [ -z "$_ssid" ] || [ -z "$_psk" ] && continue

            cat >> "$WPA_CONF" <<EOF

network={
    ssid="$_ssid"
    psk="$_psk"
    key_mgmt=WPA-PSK
    proto=RSN WPA
    pairwise=CCMP TKIP
    group=CCMP TKIP
    priority=$_prio
}
EOF
            _prio=$((_prio - 1))
        done
    )
    log_info "Generated wpa_supplicant config at $WPA_CONF"
}

# ---------------------------------------------------------------------------
# STA mode
# ---------------------------------------------------------------------------
sta_connect() {
    _iface=$(select_primary_iface)
    if [ -z "$_iface" ]; then
        log_error "No WiFi interface available"
        return 1
    fi

    _drv=$(get_iface_driver "$_iface")
    log_info "Primary interface: $_iface (driver: $_drv)"

    # Check if already connected
    if iw dev "$_iface" link 2>/dev/null | grep -q "Connected"; then
        _ssid=$(iw dev "$_iface" link 2>/dev/null | grep "SSID:" | awk '{print $2}')
        log_info "$_iface already connected to $_ssid"
        echo "$_iface" > "$STATE_DIR/primary"
        return 0
    fi

    # Kill stale wpa_supplicant for this interface
    _kill_wpa "$_iface"

    # Generate config
    generate_wpa_conf

    # Bring interface up
    ip link set "$_iface" up
    iw dev "$_iface" set power_save off 2>/dev/null || true

    # Try to connect with retries
    _attempt=0
    _connected=0
    while [ "$_attempt" -lt "$WIFI_SCAN_RETRIES" ]; do
        _attempt=$((_attempt + 1))
        log_info "Connection attempt $_attempt/$WIFI_SCAN_RETRIES on $_iface..."

        rm -f "/var/run/wpa_supplicant/$_iface"
        mkdir -p /var/run/wpa_supplicant
        if ! wpa_supplicant -B -D nl80211 -i "$_iface" -c "$WPA_CONF"; then
            log_warn "wpa_supplicant failed to start (attempt $_attempt)"
            sleep 2
            continue
        fi

        # Wait for association
        _t=0
        while [ "$_t" -lt "$WIFI_ASSOC_TIMEOUT" ]; do
            if iw dev "$_iface" link 2>/dev/null | grep -q "Connected"; then
                _ssid=$(iw dev "$_iface" link 2>/dev/null | grep "SSID:" | awk '{print $2}')
                _freq=$(iw dev "$_iface" link 2>/dev/null | grep "freq:" | awk '{print $2}')
                log_info "Connected to $_ssid on ${_freq}MHz"
                _connected=1
                break 2
            fi
            sleep 1
            _t=$((_t + 1))
        done

        # Association failed this attempt
        log_warn "Association timeout (attempt $_attempt)"
        _kill_wpa "$_iface"

        # Backoff before retry
        if [ "$_attempt" -lt "$WIFI_SCAN_RETRIES" ]; then
            _backoff=$((3 * _attempt))
            log_info "Retrying in ${_backoff}s..."
            sleep "$_backoff"
        fi
    done

    if [ "$_connected" -ne 1 ]; then
        log_error "Failed to connect after $WIFI_SCAN_RETRIES attempts"
        return 1
    fi

    # Record primary
    echo "$_iface" > "$STATE_DIR/primary"

    # Get DHCP lease — single udhcpc with -b (try foreground, then background for renewal)
    log_info "Requesting DHCP lease on $_iface..."
    _udhcpc_args="-i $_iface -t 5 -b -R"
    if [ -f "$WIFI_UDHCPC_SCRIPT" ]; then
        _udhcpc_args="$_udhcpc_args -s $WIFI_UDHCPC_SCRIPT"
    fi
    udhcpc $_udhcpc_args 2>/dev/null || log_warn "DHCP request failed"

    _ip=$(ip -4 addr show "$_iface" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')
    log_info "Interface $_iface IP: ${_ip:-pending}"
    return 0
}

sta_disconnect() {
    for _if in $(discover_wifi_ifaces); do
        _kill_wpa "$_if"
        _kill_udhcpc "$_if"
        ip addr flush dev "$_if" 2>/dev/null || true
        ip link set "$_if" down 2>/dev/null || true
    done
    rm -f "$STATE_DIR/primary"
    log_info "STA disconnected"
}

# ---------------------------------------------------------------------------
# Cooperative RX diversity
# ---------------------------------------------------------------------------

# List interfaces that have coop_rx sysfs directory
_coop_rx_ifaces() {
    _cifaces=""
    for _dev in /sys/class/net/*/coop_rx; do
        [ -d "$_dev" ] || continue
        _cifaces="$_cifaces $(basename "$(dirname "$_dev")")"
    done
    echo "$_cifaces" | xargs
}

# Check if cooperative RX is possible (driver + 2 interfaces)
coop_rx_capable() {
    [ "$COOP_RX_ENABLED" = "no" ] && return 1

    _cifaces=$(_coop_rx_ifaces)
    _count=$(echo "$_cifaces" | wc -w)
    [ "$_count" -ge 2 ] || return 1
    return 0
}

# Find the coop_rx_info sysfs path (primary interface has the full info)
_coop_rx_info_path() {
    for _dev in /sys/class/net/*/coop_rx/coop_rx_info; do
        [ -f "$_dev" ] || continue
        if grep -q "state=" "$_dev" 2>/dev/null; then
            echo "$_dev"
            return 0
        fi
    done
    return 1
}

# Check if coop RX session is currently ACTIVE
coop_rx_active() {
    _info=$(_coop_rx_info_path) || return 1
    grep -q "state_name=ACTIVE" "$_info" 2>/dev/null
}

# Get coop RX state as string
_coop_rx_state() {
    _info=$(_coop_rx_info_path) || { echo "UNAVAILABLE"; return; }
    _state_name=$(grep "^state_name=" "$_info" 2>/dev/null | cut -d= -f2)
    echo "${_state_name:-UNKNOWN}"
}

coop_rx_start() {
    if ! coop_rx_capable; then
        log_info "Cooperative RX not available (need 2+ capable interfaces)"
        return 0
    fi

    if coop_rx_active; then
        log_info "Cooperative RX already ACTIVE"
        return 0
    fi

    _cifaces=$(_coop_rx_ifaces)
    log_info "Coop RX capable interfaces: $_cifaces"

    # Find the connected interface as primary
    _primary=""
    for _if in $_cifaces; do
        if iw dev "$_if" link 2>/dev/null | grep -q "Connected"; then
            _primary="$_if"
            break
        fi
    done

    if [ -z "$_primary" ]; then
        log_warn "No connected coop RX interface found, skipping coop setup"
        return 1
    fi

    log_info "Coop RX primary: $_primary"

    # Pair each helper
    _paired=0
    for _if in $_cifaces; do
        [ "$_if" = "$_primary" ] && continue

        _role=$(cat "/sys/class/net/$_if/coop_rx/coop_rx_role" 2>/dev/null)
        if [ "$_role" = "helper" ]; then
            log_info "Helper $_if already paired"
            _paired=1
            continue
        fi

        log_info "Pairing helper: $_if"
        ip link set "$_if" up 2>/dev/null || true

        if echo "$_if" > "/sys/class/net/$_primary/coop_rx/coop_rx_pair" 2>/dev/null; then
            _paired=1
            log_info "Paired $_if as helper"
        else
            log_warn "Failed to pair $_if"
        fi
    done

    if [ "$_paired" -eq 0 ]; then
        log_warn "No helpers paired"
        return 1
    fi

    # Bind the session
    log_info "Binding cooperative RX session..."
    if echo "1" > "/sys/class/net/$_primary/coop_rx/coop_rx_bind" 2>/dev/null; then
        sleep 1
        _state=$(_coop_rx_state)
        log_info "Cooperative RX state: $_state"
        if [ "$_state" = "ACTIVE" ]; then
            log_info "Cooperative RX ACTIVE"
            _info=$(_coop_rx_info_path) && \
                grep -E "channel|num_helpers|primary_iface|helper.*_iface" "$_info" 2>/dev/null | \
                while IFS= read -r _line; do log_info "  $_line"; done
            return 0
        fi
    fi

    log_warn "Cooperative RX bind did not reach ACTIVE state"
    return 1
}

coop_rx_stop() {
    _cifaces=$(_coop_rx_ifaces)
    [ -z "$_cifaces" ] && return 0

    log_info "Stopping cooperative RX..."

    # Unbind
    for _if in $_cifaces; do
        echo "0" > "/sys/class/net/$_if/coop_rx/coop_rx_bind" 2>/dev/null || true
    done

    # Bring helpers down (not primary)
    _primary=""
    [ -f "$STATE_DIR/primary" ] && _primary=$(cat "$STATE_DIR/primary")
    for _if in $_cifaces; do
        [ "$_if" = "$_primary" ] && continue
        ip link set "$_if" down 2>/dev/null || true
    done

    log_info "Cooperative RX stopped"
}

coop_rx_status() {
    if ! coop_rx_capable; then
        echo "Cooperative RX: not available"
        return
    fi

    _cifaces=$(_coop_rx_ifaces)
    _state=$(_coop_rx_state)
    echo "Cooperative RX: $_state"
    echo "Capable interfaces: $_cifaces"

    for _if in $_cifaces; do
        _role=$(cat "/sys/class/net/$_if/coop_rx/coop_rx_role" 2>/dev/null || echo "unknown")
        _drv=$(get_iface_driver "$_if")
        echo "  $_if: role=$_role driver=$_drv"
    done

    # Show sysfs info
    _info=$(_coop_rx_info_path 2>/dev/null) && {
        echo ""
        echo "Info:"
        cat "$_info" 2>/dev/null | sed 's/^/  /'
    }

    # Show debugfs counters if available
    _stats="/sys/kernel/debug/rtw_coop_rx/stats"
    if [ -f "$_stats" ]; then
        echo ""
        echo "Counters:"
        cat "$_stats" 2>/dev/null | sed 's/^/  /'
    fi
}

# ---------------------------------------------------------------------------
# Background monitor — coop RX lifecycle + STA watchdog
# ---------------------------------------------------------------------------
coop_rx_monitor_start() {
    # Don't double-start
    if [ -f "$MONITOR_PID" ]; then
        _pid=$(cat "$MONITOR_PID")
        if kill -0 "$_pid" 2>/dev/null; then
            log_info "WiFi monitor already running (PID $_pid)"
            return 0
        fi
        rm -f "$MONITOR_PID"
    fi

    log_info "Starting WiFi monitor (interval: ${COOP_RX_MONITOR_INTERVAL}s)"

    (
        trap 'exit 0' TERM INT
        _sta_fail_count=0
        _was_connected=1
        while true; do
            # Aggressive polling when disconnected (2s), normal when connected
            if [ "$_sta_fail_count" -gt 0 ]; then
                sleep 2
            else
                sleep "$COOP_RX_MONITOR_INTERVAL"
            fi

            # --- STA watchdog ---
            _primary=""
            [ -f "$STATE_DIR/primary" ] && _primary=$(cat "$STATE_DIR/primary" 2>/dev/null)
            if [ -n "$_primary" ] && [ "$WIFI_MODE" = "sta" ]; then
                # Check if interface still exists
                if [ ! -d "/sys/class/net/$_primary" ]; then
                    _sta_fail_count=$((_sta_fail_count + 1))
                    [ "$_sta_fail_count" -eq 1 ] && log_warn "Monitor: primary interface $_primary disappeared"
                    # Try every 10s (5 * 2s) to find a new interface
                    if [ "$((_sta_fail_count % 5))" -eq 0 ]; then
                        log_info "Monitor: attempting STA recovery on new interface..."
                        sta_connect 2>/dev/null && _sta_fail_count=0
                    fi
                    continue
                fi

                # Check if wpa_supplicant is still running
                if ! _wpa_running "$_primary"; then
                    log_warn "Monitor: wpa_supplicant not running for $_primary, restarting..."
                    _kill_udhcpc "$_primary"
                    sta_connect 2>/dev/null || true
                    _sta_fail_count=0
                    _was_connected=0
                    continue
                fi

                # Check if still associated
                if ! iw dev "$_primary" link 2>/dev/null | grep -q "Connected"; then
                    _sta_fail_count=$((_sta_fail_count + 1))
                    if [ "$_sta_fail_count" -eq 1 ]; then
                        log_warn "Monitor: lost association on $_primary, waiting for reconnect..."
                        _was_connected=0
                    fi
                    # wpa_supplicant handles reconnect internally — give it
                    # generous time (60s) before we restart it entirely.
                    # Log progress every 10s.
                    if [ "$((_sta_fail_count % 5))" -eq 0 ]; then
                        log_info "Monitor: still disconnected (${_sta_fail_count}x2s elapsed)..."
                    fi
                    _max_polls=$((WIFI_RECONNECT_TIMEOUT / 2))
                    if [ "$_sta_fail_count" -ge "$_max_polls" ]; then
                        # Timeout exceeded — restart wpa_supplicant
                        log_warn "Monitor: no association for ${WIFI_RECONNECT_TIMEOUT}s, restarting wpa_supplicant..."
                        _kill_wpa "$_primary"
                        _kill_udhcpc "$_primary"
                        sta_connect 2>/dev/null || true
                        _sta_fail_count=0
                        _was_connected=0
                    fi
                    continue
                fi

                # Connected — handle reconnection recovery
                if [ "$_was_connected" -eq 0 ]; then
                    _ssid=$(iw dev "$_primary" link 2>/dev/null | grep "SSID:" | awk '{print $2}')
                    log_info "Monitor: reconnected to ${_ssid:-unknown}"
                    # Re-acquire DHCP after reconnect
                    _kill_udhcpc "$_primary"
                    _udhcpc_args="-i $_primary -t 5 -b -R"
                    [ -f "$WIFI_UDHCPC_SCRIPT" ] && _udhcpc_args="$_udhcpc_args -s $WIFI_UDHCPC_SCRIPT"
                    udhcpc $_udhcpc_args 2>/dev/null || true
                    # Re-setup cooperative RX
                    if coop_rx_capable 2>/dev/null && ! coop_rx_active 2>/dev/null; then
                        log_info "Monitor: re-establishing cooperative RX..."
                        coop_rx_start 2>/dev/null || true
                    fi
                    _was_connected=1
                fi
                _sta_fail_count=0
            fi

            # --- Cooperative RX lifecycle ---
            if ! coop_rx_capable 2>/dev/null; then
                continue
            fi

            # If active, check for newly plugged interfaces
            if coop_rx_active 2>/dev/null; then
                _cifaces=$(_coop_rx_ifaces)
                _conn=$(find_connected_iface 2>/dev/null) || continue
                for _if in $_cifaces; do
                    [ "$_if" = "$_conn" ] && continue
                    _role=$(cat "/sys/class/net/$_if/coop_rx/coop_rx_role" 2>/dev/null)
                    if [ "$_role" = "none" ]; then
                        log_info "Monitor: new interface $_if detected, pairing..."
                        ip link set "$_if" up 2>/dev/null || true
                        echo "$_if" > "/sys/class/net/$_conn/coop_rx/coop_rx_pair" 2>/dev/null || true
                        echo "1" > "/sys/class/net/$_conn/coop_rx/coop_rx_bind" 2>/dev/null || true
                    fi
                done
                continue
            fi

            # Not active — try to recover if primary is connected
            _conn=$(find_connected_iface 2>/dev/null) || continue
            log_info "Monitor: coop RX not active, attempting recovery..."
            coop_rx_start 2>/dev/null || true
        done
    ) &

    echo $! > "$MONITOR_PID"
    log_info "WiFi monitor started (PID $(cat "$MONITOR_PID"))"
}

coop_rx_monitor_stop() {
    if [ -f "$MONITOR_PID" ]; then
        _pid=$(cat "$MONITOR_PID")
        if kill -0 "$_pid" 2>/dev/null; then
            kill "$_pid" 2>/dev/null || true
            # Wait briefly for clean exit
            _w=0
            while [ "$_w" -lt 5 ] && kill -0 "$_pid" 2>/dev/null; do
                sleep 1
                _w=$((_w + 1))
            done
            # Force kill if still alive
            kill -9 "$_pid" 2>/dev/null || true
            log_info "WiFi monitor stopped (PID $_pid)"
        fi
        rm -f "$MONITOR_PID"
    fi
}

# ---------------------------------------------------------------------------
# AP mode
# ---------------------------------------------------------------------------
ap_start() {
    _iface=$(select_primary_iface)
    if [ -z "$_iface" ]; then
        log_error "No WiFi interface available for AP mode"
        return 1
    fi

    _drv=$(get_iface_driver "$_iface")
    log_info "AP mode on $_iface (driver: $_drv)"

    # Kill any existing wpa_supplicant on this interface
    _kill_wpa "$_iface"

    # Set regulatory domain
    iw reg set "$AP_COUNTRY" 2>/dev/null || true

    # Bring interface up
    ip link set "$_iface" up

    # Determine hw_mode based on channel
    if [ "$AP_CHANNEL" -ge 36 ]; then
        _hw_mode="a"
        _vht="1"
    else
        _hw_mode="g"
        _vht="0"
    fi

    # Disable power save (latency-sensitive)
    iw dev "$_iface" set power_save off 2>/dev/null || true

    # Generate hostapd config
    cat > "$HOSTAPD_CONF" <<EOF
interface=$_iface
driver=nl80211
ssid=$AP_SSID
country_code=$AP_COUNTRY
hw_mode=$_hw_mode
channel=$AP_CHANNEL
ieee80211n=1
ieee80211ac=$_vht
wpa=2
wpa_passphrase=$AP_PSK
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wmm_enabled=1

# FPV link stability
disassoc_low_ack=0
ap_max_inactivity=86400
max_num_sta=4
uapsd_advertisement_enabled=0
EOF

    # Start hostapd
    if ! hostapd -B "$HOSTAPD_CONF"; then
        log_error "hostapd failed to start"
        return 1
    fi
    log_info "hostapd started (SSID: $AP_SSID, ch: $AP_CHANNEL)"

    # Assign static IP
    ip addr flush dev "$_iface" 2>/dev/null || true
    ip addr add "$AP_IP/24" dev "$_iface"
    log_info "AP IP: $AP_IP"

    # Generate and start DHCP server
    cat > "$UDHCPD_CONF" <<EOF
interface $_iface
start $AP_DHCP_START
end $AP_DHCP_END
opt dns $AP_IP
opt router $AP_IP
opt subnet $AP_NETMASK
opt lease 300
EOF

    udhcpd -S "$UDHCPD_CONF"
    log_info "DHCP server started ($AP_DHCP_START - $AP_DHCP_END)"

    echo "$_iface" > "$STATE_DIR/primary"
    return 0
}

ap_stop() {
    log_info "Stopping AP mode..."
    killall hostapd 2>/dev/null || true

    # Kill only the WiFi udhcpd (not the usb0 one)
    _pids=$(ps w 2>/dev/null | grep "udhcpd" | grep -v grep | \
        grep -- "$UDHCPD_CONF" | awk '{print $1}')
    [ -n "$_pids" ] && kill $_pids 2>/dev/null || true

    for _if in $(discover_wifi_ifaces); do
        ip addr flush dev "$_if" 2>/dev/null || true
        ip link set "$_if" down 2>/dev/null || true
    done

    rm -f "$HOSTAPD_CONF" "$UDHCPD_CONF" "$STATE_DIR/primary"
    log_info "AP stopped"
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
do_status() {
    _ifaces=$(discover_wifi_ifaces)
    if [ -z "$_ifaces" ]; then
        echo "No WiFi interfaces found"
        return
    fi

    echo "WiFi interfaces:"
    for _if in $_ifaces; do
        _drv=$(get_iface_driver "$_if")
        _state=$(cat "/sys/class/net/$_if/operstate" 2>/dev/null || echo "unknown")
        _ip=$(ip -4 addr show "$_if" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')

        printf "  %-24s driver=%-12s state=%-6s" "$_if" "$_drv" "$_state"
        if iw dev "$_if" link 2>/dev/null | grep -q "Connected"; then
            _ssid=$(iw dev "$_if" link 2>/dev/null | grep "SSID:" | awk '{print $2}')
            _freq=$(iw dev "$_if" link 2>/dev/null | grep "freq:" | awk '{print $2}')
            _signal=$(iw dev "$_if" link 2>/dev/null | grep "signal:" | awk '{print $2, $3}')
            printf " ssid=%s freq=%s signal=%s ip=%s" "$_ssid" "$_freq" "$_signal" "${_ip:-none}"
        fi
        echo ""
    done

    echo ""
    echo "wpa_supplicant:"
    _primary=""
    [ -f "$STATE_DIR/primary" ] && _primary=$(cat "$STATE_DIR/primary" 2>/dev/null)
    if [ -n "$_primary" ] && _wpa_running "$_primary"; then
        echo "  running for $_primary"
    else
        echo "  not running"
    fi

    # Coop RX status
    echo ""
    coop_rx_status

    # Monitor status
    echo ""
    if [ -f "$MONITOR_PID" ] && kill -0 "$(cat "$MONITOR_PID")" 2>/dev/null; then
        echo "WiFi monitor: running (PID $(cat "$MONITOR_PID"))"
    else
        echo "WiFi monitor: not running"
    fi
}

# Scan for visible networks
do_scan() {
    _iface=$(select_primary_iface)
    if [ -z "$_iface" ]; then
        log_error "No WiFi interface for scan"
        return 1
    fi
    ip link set "$_iface" up 2>/dev/null || true
    log_info "Scanning on $_iface..."
    iw dev "$_iface" scan 2>/dev/null | grep -E "SSID:|signal:|freq:" | \
        sed 's/^[[:space:]]*/  /'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
load_config

case "${1:-}" in
    start)
        if ! wait_for_wifi_ifaces; then
            exit 1
        fi

        case "$WIFI_MODE" in
            sta)
                if sta_connect; then
                    coop_rx_start || true
                    coop_rx_monitor_start || true
                else
                    # Start monitor anyway — it will retry STA connection
                    coop_rx_monitor_start || true
                    exit 1
                fi
                ;;
            ap)
                ap_start || exit 1
                ;;
            *)
                log_error "Unknown WIFI_MODE: $WIFI_MODE"
                exit 1
                ;;
        esac
        ;;

    stop)
        coop_rx_monitor_stop
        coop_rx_stop 2>/dev/null || true
        case "$WIFI_MODE" in
            sta) sta_disconnect ;;
            ap)  ap_stop ;;
        esac
        rm -f "$WPA_CONF"
        ;;

    restart)
        "$0" stop
        sleep 2
        "$0" start
        ;;

    status)
        do_status
        ;;

    scan)
        do_scan
        ;;

    coop-start)
        coop_rx_start
        ;;

    coop-stop)
        coop_rx_monitor_stop
        coop_rx_stop
        ;;

    coop-status)
        coop_rx_status
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|scan|coop-start|coop-stop|coop-status}"
        exit 1
        ;;
esac
