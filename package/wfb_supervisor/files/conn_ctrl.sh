#!/bin/sh
# set_connection.sh — runtime HT(11n) helpers (NO hostapd.conf edits)
# - Limit HT MCS (5 GHz): iw dev IFACE set bitrates ht-mcs-5 <idx...>
# - Change channel/width (5 GHz HT20/HT40±): ALWAYS via hostapd_cli chan_switch (CSA)
#
# Requirements:
#   - hostapd_cli must be present and able to talk to hostapd on IFACE (PING -> PONG)
#   - iw must be present for MCS masking and status/confirm
#
# Usage:
#   ./set_connection.sh status
#   ./set_connection.sh confirm
#   ./set_connection.sh mcs 0-7
#   ./set_connection.sh mcs 0-3
#   ./set_connection.sh mcs 0-2
#   ./set_connection.sh mcs 1-6
#   ./set_connection.sh mcs clear
#   ./set_connection.sh width 20 161
#   ./set_connection.sh width 40- 161
#
set -eu

IFACE="${IFACE:-wlan0}"
STATE="/tmp/wifi_htctl.${IFACE}.state"

have() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }

need_tools() {
  have hostapd_cli || die "hostapd_cli not found"
  have iw || die "iw not found"
}

ALLOWED_CH_5G="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165 169 173"

is_allowed_chan() {
  echo " $ALLOWED_CH_5G " | grep -q " $1 " 2>/dev/null
}

chan_to_freq() { echo $((5000 + ($1 * 5))); }

parse_chan_or_freq() {
  x="$1"
  case "$x" in *[!0-9]*|"") die "channel/freq must be numeric (got: '$x')" ;; esac
  if [ "$x" -ge 5000 ]; then
    freq="$x"
    ch=$(((freq - 5000) / 5))
    echo "$ch $freq"
  else
    ch="$x"
    is_allowed_chan "$ch" || die "channel $ch not in allowed list: $ALLOWED_CH_5G"
    freq="$(chan_to_freq "$ch")"
    echo "$ch $freq"
  fi
}

validate_ht40_dir() {
  ch="$1"
  dir="$2" # "+" or "-"
  case "$dir" in
    "+") ch2=$((ch + 4)) ;;
    "-") ch2=$((ch - 4)) ;;
    *) die "internal: bad ht40 dir '$dir'" ;;
  esac
  is_allowed_chan "$ch2" || die "HT40$dir invalid around channel $ch (needs adjacent channel $ch2 allowed). Try HT20 or opposite HT40 direction."
}

save_state() {
  key="$1"; val="$2"
  tmp="${STATE}.tmp"
  touch "$STATE"
  grep -v "^${key}=" "$STATE" >"$tmp" 2>/dev/null || true
  echo "${key}=${val}" >>"$tmp"
  mv -f "$tmp" "$STATE"
}

load_state() {
  key="$1"
  [ -f "$STATE" ] || return 0
  grep "^${key}=" "$STATE" | tail -n 1 | cut -d= -f2- || true
}

hostapd_ping() {
  hostapd_cli -i "$IFACE" ping 2>/dev/null | grep -q '^PONG'
}

# Expand tokens like: 0 1-3 5 6-7 -> "0 1 2 3 5 6 7"
expand_mcs_tokens() {
  out=""
  for tok in "$@"; do
    case "$tok" in
      *-*)
        a="${tok%-*}"
        b="${tok#*-}"
        case "$a" in *[!0-9]*|"") die "bad MCS range start '$a' (from '$tok')" ;; esac
        case "$b" in *[!0-9]*|"") die "bad MCS range end '$b' (from '$tok')" ;; esac
        [ "$a" -le "$b" ] || die "bad MCS range '$tok' (start > end)"
        [ "$a" -le 7 ] && [ "$b" -le 7 ] || die "MCS range '$tok' outside 0..7 (you asked for no MIMO)"
        i="$a"
        while [ "$i" -le "$b" ]; do
          out="${out}${out:+ }$i"
          i=$((i + 1))
        done
        ;;
      *)
        case "$tok" in *[!0-9]*|"") die "bad MCS index '$tok' (use digits or ranges like 0-2)" ;; esac
        [ "$tok" -le 7 ] || die "MCS '$tok' > 7 (implies more spatial streams). Use 0..7 only."
        out="${out}${out:+ }$tok"
        ;;
    esac
  done
  echo "$out"
}

do_status() {
  need_tools
  echo "== iface =="
  iw dev "$IFACE" info 2>/dev/null || true
  echo
  echo "== link =="
  iw dev "$IFACE" link 2>/dev/null || true
  echo
  echo "== stations (bitrate/MCS shown here) =="
  iw dev "$IFACE" station dump 2>/dev/null || true
  echo
  echo "== hostapd =="
  hostapd_cli -i "$IFACE" status 2>/dev/null || true
  echo
  echo "== last applied by this script =="
  [ -f "$STATE" ] && cat "$STATE" || echo "(none)"
}

do_confirm() {
  need_tools
  wanted="$(load_state MCS)"
  echo "== tx/rx bitrate (stations) =="
  out="$(iw dev "$IFACE" station dump 2>/dev/null || true)"
  echo "$out" | sed -n 's/^\s*\(tx bitrate:.*\)$/\1/p; s/^\s*\(rx bitrate:.*\)$/\1/p'
  echo
  echo "== extracted MCS lines (best effort) =="
  echo "$out" | awk '
    /tx bitrate:/ || /rx bitrate:/ {
      if (match($0, /MCS[[:space:]]+[0-9]+/)) print $0
    }'
  echo
  echo "== last requested mask: ${wanted:-"(none)"} =="
}

do_mcs() {
  need_root
  need_tools
  [ $# -ge 1 ] || die "mcs: need: clear | 0-7 | 0-3 | <list/ranges...> (e.g. '0-2' or '0 1 3-5')"

  case "$1" in
    clear)
      iw dev "$IFACE" set bitrates
      save_state MCS "clear"
      echo "[ok] cleared bitrate mask on $IFACE"
      ;;
    0-7)
      iw dev "$IFACE" set bitrates ht-mcs-5 0 1 2 3 4 5 6 7
      save_state MCS "0-7"
      echo "[ok] limited HT MCS on 5GHz to 0..7 (1SS) on $IFACE"
      ;;
    0-3)
      iw dev "$IFACE" set bitrates ht-mcs-5 0 1 2 3
      save_state MCS "0-3"
      echo "[ok] limited HT MCS on 5GHz to 0..3 (1SS) on $IFACE"
      ;;
    *)
      expanded="$(expand_mcs_tokens "$@")"
      # shellcheck disable=SC2086
      iw dev "$IFACE" set bitrates ht-mcs-5 $expanded
      save_state MCS "$expanded"
      echo "[ok] limited HT MCS on 5GHz to: $expanded on $IFACE"
      ;;
  esac

  echo "Run: $0 confirm"
}

do_width() {
  need_root
  need_tools
  [ $# -eq 2 ] || die "width: need: <20|40+|40-> <channel|freqMHz>   (e.g. '20 161' or '40- 161')"
  hostapd_ping || die "hostapd_cli can't talk to hostapd on $IFACE (hostapd not running, ctrl_interface missing, or wrong IFACE)"

  w="$1"
  chfreq="$2"
  set -- $(parse_chan_or_freq "$chfreq")
  ch="$1"
  freq="$2"

  case "$w" in
    20)
      sec_off="0"
      bw="20"
      cf1="$freq"
      ;;
    40+)
      validate_ht40_dir "$ch" "+"
      sec_off="1"
      bw="40"
      cf1=$((freq + 10))   # center freq for HT40+
      ;;
    40-)
      validate_ht40_dir "$ch" "-"
      sec_off="-1"
      bw="40"
      cf1=$((freq - 10))   # center freq for HT40-
      ;;
    *) die "width must be one of: 20, 40+, 40-" ;;
  esac

  save_state WIDTH "$w"
  save_state CH "$ch"
  save_state FREQ "$freq"

  echo "[wifi] hostapd_cli chan_switch: ch=$ch freq=${freq}MHz width=$w (HT only)"
  # chan_switch <cs_count> <freq> [sec_channel_offset=] [center_freq1=] [center_freq2=] [bandwidth=] ... [ht|vht|he|eht]
  hostapd_cli -i "$IFACE" chan_switch 5 "$freq" \
    "sec_channel_offset=$sec_off" "center_freq1=$cf1" "bandwidth=$bw" ht

  echo "[ok] requested channel switch (CSA). Stations may briefly disconnect."
  echo "Check: $0 status"
}

do_help() {
  cat <<EOF
set_connection.sh — runtime HT(11n) helpers (NO hostapd.conf edits)

Env:
  IFACE=wlan0

Commands:
  status
  confirm

  mcs clear
  mcs 0-7
  mcs 0-3
  mcs <list/ranges...>
      Examples:
        $0 mcs 0-2
        $0 mcs 0-4
        $0 mcs 1-6
        $0 mcs 0 1 3-5

  width 20  <channel|freqMHz>
  width 40+ <channel|freqMHz>
  width 40- <channel|freqMHz>
      Uses hostapd_cli chan_switch ONLY.

      Examples:
        $0 width 20 161
        $0 width 40- 161   # HT40+ is invalid on ch161; 40- is the valid direction

Allowed 5 GHz channels:
  $ALLOWED_CH_5G
EOF
}

cmd="${1:-help}"
shift || true
case "$cmd" in
  status)  do_status ;;
  confirm) do_confirm ;;
  mcs)     do_mcs "$@" ;;
  width)   do_width "$@" ;;
  help|-h|--help) do_help ;;
  *) die "unknown command: $cmd (try: $0 help)" ;;
esac
