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

## Known Issues / TODOs

### 1. Panel Driver (CRITICAL)

The RGB20Pro's 1024x768 display uses an unidentified MIPI DSI controller.
ROCKNIX handles this with a custom `rocknix,generic-dsi` panel driver that
reads init sequences from the device tree.

**Options to get the display working:**

a) **Port the ROCKNIX generic-dsi driver** - Source at
   `github.com/stolen/overlay_server` (commit 04e5e55). Add as a kernel
   patch in `board/powkiddy/rgb20pro/linux-patches/`. This is the most
   proven approach since ROCKNIX ships this to real users.

b) **Create a proper panel driver** - Write a standard DRM panel driver
   (`panel-powkiddy-rgb20pro.c`) with the init sequence hardcoded.

c) **Extract from stock firmware** - Dump the panel init sequence via
   UART from the stock Powkiddy firmware if the ROCKNIX sequences don't
   work with the BSP kernel.

### 2. Joystick Driver

The analog sticks use a single SARADC channel (ch3) with GPIO-based
analog multiplexer. ROCKNIX uses a custom `rocknix-singleadc-joypad`
driver from `github.com/ROCKNIX/rocknix-joypad`.

**Options:**
- Port `rocknix-joypad` as an out-of-tree kernel module package
- Use the mainline `adc-joystick` driver if the BSP SARADC supports
  multiple channels natively (unlikely for muxed setup)
- Write a userspace daemon using `/dev/iio` to read the muxed ADC

### 3. U-Boot

Currently using the Radxa Zero 3 U-Boot defconfig. This should work for
basic boot but won't have RGB20Pro-specific detection (SARADC value 245).
For proper auto-detection, the Anbernic rgxx3-rk3566 U-Boot defconfig
with the RGB20Pro patch from ROCKNIX would be needed.

### 4. WiFi Variant Detection

Most units have RTL8821CS but some early units shipped with RTL8723DS.
Both drivers are enabled in the kernel fragment. ROCKNIX detects the
variant by checking USB ID `024C:D723`.

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
