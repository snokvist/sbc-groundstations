#!/bin/bash
# RGB20Pro post-build: install recompiled DTB
# The kernel build system produces a DTB with wrong phandle resolution.
# The recompile hook in local.mk produces the correct one in BINARIES_DIR.
DTB_SRC="${BINARIES_DIR}/rockchip/rk3566-powkiddy-rgb20pro.dtb"
DTB_DST="${TARGET_DIR}/boot/rockchip/rk3566-powkiddy-rgb20pro.dtb"
if [ -f "$DTB_SRC" ]; then
    cp "$DTB_SRC" "$DTB_DST"
    echo "RGB20Pro: installed recompiled DTB ($(stat -c%s "$DTB_SRC") bytes)"
fi
