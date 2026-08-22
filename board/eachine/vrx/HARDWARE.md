# Eachine VRX — Hardware Profile

Ground-station VRX board built on a **Radxa Zero3 (Rockchip RK3566)** module.
Electrically identical to the `radxa/zero3` board, so this profile reuses that
board's kernel, U-Boot, DTS, patches and overlay — `eachine_vrx_defconfig`
differs from `waybeam_radxa3e_defconfig` only in image identity (hostname) and
the explicitly-pinned boot-hold button pins. This file records the verified
Eachine-specific hardware setup so it travels with the chassis.

## Provenance

Facts below were probed from a **factory Eachine unit at `192.168.2.170`**
(login `root:root`) on 2026-07-19. That unit ships the stock Radxa Debian 11
+ OpenIPC/Ruby groundstation stack (`pixelpilot` + `wifibroadcast-ng` +
`adaptive-link`), firmware banner `v2.0.0 beta 2`. We do **not** carry that
stack — we build our own Waybeam image (`waybeam-hub` + ecosystem). Only the
hardware-specific setup below needs to travel with the chassis.

## Buttons — two independent subsystems

The chassis has 6 front-panel buttons. There is **no kernel `gpio-keys` /
`adc-keys` node** — buttons are read in userspace. Both consumers use the
**same namespace**: the Radxa 40-pin header **line names** `PIN_<n>`, all on
`gpiochip3`, resolved via `gpiofind`. Verified live on the factory unit — the
six lines pixelpilot claims (`lvgl_input`) are exactly the ones named
`PIN_11/13/16/18/38/32`, matching the gsmenu values below.

Panel button → header PIN → resolved gpiochip3 line.

**CORRECTED 2026-08-22 by pressing each button on the unit.** The table below
this one is what the factory `gsmenu` config claims; two of its entries are
WRONG for this chassis and following them leaves `right` dead while `centre`
behaves as `right`:

| Button | header PIN | gpiochip3 line | how known |
|--------|-----------|----------------|-----------|
| up     | PIN_16 | 9  | pressed, confirmed |
| down   | PIN_18 | 10 | pressed, confirmed |
| left   | PIN_13 | 2  | pressed, confirmed |
| **right**  | **PIN_40** | **5**  | pressed — **not in the factory list at all** |
| **centre** | **PIN_11** | **1**  | pressed — factory list calls this "right" |
| ?      | PIN_38 | 6  | fires, but is NOT the stick centre; identity unknown |
| ?      | PIN_32 | 18 | fires; factory list calls it "rec", unverified |

The stick is a **5-way** (up/down/left/right/centre). `PIN_38` and `PIN_32` are
two further chassis buttons that both fire but have not been identified.

**The trap that cost two debugging rounds: the factory list names six lines on
`gpiochip3`, and taking those six as the search space hides `PIN_40`.** The
Radxa header pins are spread across **gpiochip0, 1, 3 and 4** — `PIN_3`, `PIN_5`
and `PIN_37` are on chip1, `PIN_8`/`PIN_10` on chip0, and `PIN_19`, `PIN_21`,
`PIN_23`, `PIN_24`, `PIN_26`, `PIN_27`, `PIN_28` on chip4. When mapping a new
chassis, monitor **every unused line on every chip** and press one button at a
time:

```sh
for c in 0 1 2 3 4 5; do
  offs=$(gpioinfo gpiochip$c | awk '/^[[:space:]]*line/ && /unused/ {gsub(/:/,"",$2); print $2}')
  [ -n "$offs" ] && ( gpiomon --format="chip'"$c"' %o %e" gpiochip$c $offs > /tmp/gm_$c.txt & )
done
```

Include a known-good button as a control, or a capture that records nothing is
indistinguishable from a button that does nothing.

Original factory `gsmenu` claim, kept because it is what the stock stack uses —
**do not treat it as this chassis's map**:

| Button | gsmenu `PIN_<n>` | gpiochip3 line |
|--------|------------------|----------------|
| left   | PIN_13 | 2  |
| right  | PIN_11 | 1  |
| up     | PIN_16 | 9  |
| down   | PIN_18 | 10 |
| center | PIN_38 | 6  |
| rec    | PIN_32 | 18 |

### 1. Runtime menu buttons — NOT used by the waybeam image

On the **factory** unit, standalone `pixelpilot` reads these PIN numbers from
`/etc/pixelpilot.yaml` (`gsmenu` block) and resolves each via
`gpiofind "PIN_<n>"`, selecting the layout at boot from `setup.txt`
(`gpio_layout = Ruby`).

Our **waybeam image does not build pixelpilot** — `waybeam-hub` embeds the
decoder/OSD and its config lives in `/etc/waybeam_hub.conf`, not
`/etc/pixelpilot.yaml`. waybeam-hub currently has **no panel-GPIO button
input**; its menu (`mod_menu`) is navigated by **RC channels**
(`ch5`/`ch10`/`action_threshold`). A `pixelpilot.yaml` overlay was therefore
inert and has been removed — the PIN→button map above is retained here as the
reference to wire up if/when waybeam-hub gains GPIO-button support (upstream
waybeam-hub feature).

### 2. Boot-hold buttons (initramfs `init`)

`board/common/overlay/init` resolves two buttons by the same `PIN_<n>` name via
`gpiofind`, for hold-at-boot recovery actions. Hold-at-boot convention is
**Left = gadget, Right = factory-reset**:

| Function | Kconfig | Value | Panel button |
|----------|---------|-------|--------------|
| Factory reset (hold at boot) | `BR2_FACTORY_RESET_GPIO_PIN_NAME` | `PIN_11` | right |
| USB gadget mode (hold at boot) | `BR2_GADGET_MODE_GPIO_PIN_NAME` | `PIN_13` | left |

Verified against the panel map above: `PIN_11` = right, `PIN_13` = left. These
match the values inherited from `waybeam_radxa3e_defconfig`, so no numeric
change was needed — they are pinned explicitly in `eachine_vrx_defconfig` with
this rationale.

## WiFi / RF

- USB adapter observed in use: **RTL8822/8812EU** (`rtl88x2eu`, `8812eu`
  driver). Onboard **AIC8800** also present.
- Factory WFB defaults (reference only — our image sets its own): channel
  `161`, region `00`, bandwidth `40`, video `connect://127.0.0.1:5600`,
  mavlink `connect://127.0.0.1:14550`.
- Adapter auto-rename: the factory `autoload-wfb-nics.sh` renames the first
  non-USB wireless iface to `wlan0` and writes `WFB_NICS`. Our image handles
  NIC selection through its own mechanism.

## Display / DVR (factory reference)

- `screen_mode = 1920x1080@60`, `rec_fps = 60` (from factory `setup.txt`).
- Factory ran a Flask "Video Server" DVR web UI on port 80 (`dvrUI`); not
  carried.

## Factory-image quirks NOT to replicate

- `stream.sh` `case` references a `gpio/Emax.yaml` layout that does not exist
  in the factory `/config/scripts/gpio/` — selecting Emax would fail the copy.
- `stream.sh` parses the OSD mode with `render =` but `setup.txt` writes
  `osd = air`, so the ground-side `msposd_rockchip` never starts on the
  factory image.
