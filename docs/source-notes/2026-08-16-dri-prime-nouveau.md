# DRI_PRIME nouveau offload while Intel owns the panel (2026-08-16)

## Abstract

With the internal panel already on `i915` (`i915drmfb`, 2880×1800, mux
`IGD:+`), Mesa `DRI_PRIME=1` rendered an OpenGL client on **nouveau NVE7**
(GT 750M, `10de:0fe9`) and composited it through Intel. The GMUX did **not**
move. This is PC-style render offload, not Big Sur Automatic Graphics
Switching.

Vulkan did not follow `DRI_PRIME` to NVIDIA (Kepler has no usable NVK path
here); `vulkaninfo` stayed on Iris Pro.

## Setup (unchanged mux)

- Boot: Intel UKI (`apple_gmux.force_igd=1` + DDI A 4-lane poke)
- `i915` owns eDP-2; nouveau loaded; proprietary nvidia 470 **not** loaded
- switcheroo before and after: `IGD:+:Pwr`, `DIS: :Pwr`
- No `echo IGD` / `echo DIS` / `echo OFF`

## Results

| Command | Renderer |
| --- | --- |
| `DRI_PRIME=0 glxinfo` / `glxgears` | Mesa Intel Iris Pro P5200 (HSW GT3), GL 4.6 |
| `DRI_PRIME=1 glxinfo` / `glxgears` | Mesa NVE7, GL 4.3, ~2 GiB VRAM, PCI `10de:0fe9` |
| `DRI_PRIME=1 vulkaninfo` | still Intel (no NVIDIA Vulkan device) |

Mesa selected `/dev/dri/renderD128` (nouveau) for `DRI_PRIME=1` even though
`xrandr --listproviders` listed only the Intel `modesetting` provider. Offload
is via render nodes, not an xrandr output-source link.

Verbose GLX: `using driver nouveau` for the prime fd and `using driver i915`
(`crocus`) for the display fd. That is the expected PRIME split.

## How to use (manual, per app)

```bash
DRI_PRIME=1 glxgears
# or
scripts/graphics/prime-run firefox
```

The Plasma session stays on Intel. Only the launched process renders on
nouveau.

## What this is not

- Not automatic per-app switching like Big Sur WindowServer
- Not a runtime panel mux hop (still a hard stop on this indexed GMUX)
- Not the proprietary nvidia 470 stack (that driver does not join this
  offload while Intel owns the lid)
- Not a reason to wipe the install or chase Omarchy

Kepler nouveau is a weak substitute for Apple’s NVIDIA driver. Treat this as
“a GL app can use the other chip” proof, not a gaming/CUDA desktop.

## Helper

`scripts/graphics/prime-run` — `exec env DRI_PRIME=1 "$@"`.
