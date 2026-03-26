# Powkiddy RGB20Pro - Ground Station Target

## Hardware Summary

| Component | Detail |
|-----------|--------|
| SoC | RK3566 (Cortex-A55 quad @ 1.8GHz) |
| RAM | 1GB LPDDR4 |
| Display | 3.2" 1024x768 MIPI DSI IPS (65x49mm) |
| WiFi/BT | RTL8821CS SDIO (some units: RTL8723DS) |
| Battery | 5000mAh (RK817 charger) |
| Audio | RK817 codec, speaker amp GPIO0_PA6 |
| Video out | Mini HDMI |
| Storage | Dual MicroSD |
| Rumble | PWM5-based motor |
| LEDs | Green (PWM6), Red (PWM7) |

## Ported Drivers

### Panel Driver (`package/panel-generic-dsi`)
Ported from ROCKNIX. Reads panel config (timing modes, DSI init sequence)
from the `panel_description` device tree property. The DTS contains the
complete init sequence and 12 display modes (default: 60fps at 51072kHz).

### Joystick Driver (`package/rocknix-joypad`)
Ported from ROCKNIX (Miyoo serial code removed, only SARADC+mux kept).
Single SARADC channel (ch3) with GPIO analog mux for 4 axes (LX/LY/RX/RY).
Includes radial deadzone, axis inversion, and PWM rumble support.

## Remaining TODOs

### 1. U-Boot
Currently using the Radxa Zero 3 U-Boot defconfig. This should work for
basic boot but won't have RGB20Pro-specific detection (SARADC value 245).
For proper auto-detection, the Anbernic rgxx3-rk3566 U-Boot defconfig
with the RGB20Pro patch from ROCKNIX would be needed.

### 2. WiFi Variant Detection
Most units have RTL8821CS but some early units shipped with RTL8723DS.
Both drivers are enabled in the kernel fragment. ROCKNIX detects the
variant by checking USB ID `024C:D723`.

### 3. Kernel Compatibility
The joypad driver has been ported from the legacy `input-polldev.h` API
to the modern `input_setup_polling()` API for kernel 6.1+ compatibility.

The BSP kernel is Radxa 6.1.84. DTS node labels differ from
mainline/ROCKNIX (e.g. `combphy1_usq` not `combphy1`,
`usbdrd_dwc3` not `usb_host0_xhci`).

## Build

```bash
DEFCONFIG=powkiddy_rgb20pro_defconfig ./build.sh
```

## References

- ROCKNIX RGB20Pro DTS patch: `0018-arm64-dts-rockchip-add-device-tree-for-powkiddy-rgb2.patch`
- ROCKNIX generic-dsi driver: `github.com/stolen/overlay_server`
- ROCKNIX joypad driver: `github.com/ROCKNIX/rocknix-joypad`
- Mainline Powkiddy base DTSI: `rk3566-powkiddy-rk2023.dtsi`
- U-Boot RGB20Pro detection: ADC value 245 in rgxx3-rk3566 board
