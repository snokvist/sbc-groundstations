# Rocknix RGB20 Pro Port Bundle

This folder contains the required files gathered from Rocknix to port
Powkiddy RGB20 Pro display + input support into another Buildroot tree.

## Contents

- `linux-patches/`
  - `0001-gpiolib-of-revert-api-changes-needed-for-joypad-driv.patch`
  - `0004-input-adc-keys-redirect-keycode-316-to-rocknix-joypa.patch`
  - `0006-drm-panel-nv3051d-fix-panel-timings-and-display-mode.patch`
  - `0018-arm64-dts-rockchip-add-device-tree-for-powkiddy-rgb2.patch`
- `dts/`
  - `rk3566-powkiddy-rk2023.dtsi`
- `uboot-patches/`
  - `0003-board-rockchip-Fix-panel-detection-logic-for-mainlin.patch`
  - `003-fix-dtb-and-vs.patch`
  - `004-rgb20pro.patch`
- `drivers/generic-dsi/`
  - `panel-generic-dsi.c`
  - `importpanel.py`
  - `rocknix-package.mk`
- `drivers/rocknix-joypad/`
  - `Makefile`
  - `rocknix-joypad.c`
  - `rocknix-joypad.h`
  - `rocknix-singleadc-joypad.c`
  - `rocknix-package.mk`
- `quirks/`
  - `001-detect-device`

## Notes

- The `0018` DTS patch expects Rocknix-style RK2023 DT definitions. The
  bundled `dts/rk3566-powkiddy-rk2023.dtsi` is required for labels/properties
  referenced by the RGB20 Pro DTS patch.
- Apply kernel patches in dependency order (gpiolib/adc-keys first).
- Integrate driver sources either as kernel-tree additions (Rocknix style) or
  as out-of-tree kernel modules in your Buildroot.
