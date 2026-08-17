#!/bin/sh
# Sourced by startplasma so KWin Wayland sees the Intel DRM pin + legacy modeset.
export KWIN_DRM_DEVICES=/dev/dri/intel-igpu
export KWIN_DRM_NO_AMS=1
export KWIN_DRM_USE_MODIFIERS=0
export KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1
export AQ_DRM_DEVICES=/dev/dri/intel-igpu
export AQ_NO_ATOMIC=1
export WLR_DRM_DEVICES=/dev/dri/intel-igpu
export WLR_DRM_NO_ATOMIC=1
