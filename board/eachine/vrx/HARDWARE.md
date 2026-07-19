# Eachine VRX — Hardware Profile

Ground-station VRX board built on a **Radxa Zero3 (Rockchip RK3566)** module.
Electrically identical to the `radxa/zero3` board, so this profile reuses that
board's kernel, U-Boot, DTS and patches — it overrides only the front-panel
**button map** and the image identity.

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

Panel button → header PIN → resolved gpiochip3 line:

| Button | gsmenu `PIN_<n>` | gpiochip3 line |
|--------|------------------|----------------|
| left   | PIN_13 | 2  |
| right  | PIN_11 | 1  |
| up     | PIN_16 | 9  |
| down   | PIN_18 | 10 |
| center | PIN_38 | 6  |
| rec    | PIN_32 | 18 |

### 1. Runtime menu buttons (pixelpilot `gsmenu`)

pixelpilot reads the header PIN numbers from `/etc/pixelpilot.yaml` and
resolves each via `gpiofind "PIN_<n>"`. The factory unit selects the layout at
boot from `setup.txt` (`gpio_layout = Ruby`); this profile bakes the resolved
Eachine/"Ruby" map straight into `overlay/etc/pixelpilot.yaml`.

> Note vs `radxa/zero3`: that profile's map is identical **except it omits
> `center: 38` (PIN_38)**. The Eachine panel has a working center/select
> button — carry it or the menu-select action is dead.

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
