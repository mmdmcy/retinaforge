# Gaming and the Retina panel — MacBookPro11,3

This 15-inch Late 2013 Retina is a **sharp portable workstation**, not a
gaming laptop that happens to be high-res. The 2880×1800 panel exists so
text, photos, and UI look like print. macOS draws it as **1440×900
points at 2×** (HiDPI). You do not “get more HUD”; you get the same
layout without fuzzy pixels.

Games were never the reason for that pixel count. A GT 750M (2 GB
Kepler) pushing a 5.2 million pixel framebuffer at native resolution was
the wrong target in 2013 and still is. Sensible play is a **lower
internal resolution** (1920×1200, 1440×900, or less), then the panel
upscales. The desktop can stay crisp the whole time.

The 15-inch discrete GPU is there to **fill that huge desktop** and to
help **pro GPU jobs** (timeline effects, filters, some CAD/OpenCL). The
13-inch Retina often had no NVIDIA. Boot Camp / Steam-on-Mac were side
doors, not the product.

Omarchy 4 is the **daily Linux** on this chassis (stock nouveau lid,
2880×1800). That is still not a reason to run the stock ISO as a
**whole-disk** wipe. Keep macOS. Cook-book:
[`omarchy.md`](omarchy.md),
[`../source-notes/2026-08-19-omarchy-daily.md`](../source-notes/2026-08-19-omarchy-daily.md).

## How 3D works on the accepted Omarchy boot (2026-08-19)

The GT 750M **owns the lid** (`nouveaudrmfb`, mux `DIS:+`). Native
**OpenGL** uses Mesa nouveau on that chip. Do **not** use `DRI_PRIME=1`
/ tray **Run on 750M** — those were for an Intel-owned panel.

Stock image: Mesa nouveau GL is present; **no** `vulkan-nouveau` ICD.
Intel HasVK exists on the iGPU but is not a 2026 Proton/Vulkan gaming
stack. Proprietary nvidia 470 left with CachyOS. Lower in-game
resolution to 1920×1200 or 1440×900.

## How 3D worked on the CachyOS Intel-lid boot (archived)

Intel Iris Pro owned the lid (`i915drmfb`). The unused 750M could
**render** one **OpenGL** process (`DRI_PRIME=1`) without moving the
GMUX. The tray plate’s **Run on 750M** did that.

That is *like* macOS using the 750M for 3D. It is **not** Automatic
Graphics Switching. Apple often moved the **panel cable**. Linux must
not send `IGD`/`DIS` from a running desktop.

Vulkan (most Proton/Windows Steam titles, CS2, current Dota 2) stayed on
**Iris Pro** on that boot. NVIDIA 470 Vulkan/CUDA was a **different
Limine entry**, not the plate.

## Native OpenGL titles (750M / nouveau)

Expect 2013 laptop performance. Turn the in-game resolution down.

Valve Source 1 Linux ports: **Portal**, **Portal 2**, **Half-Life 2**
and episodes, **Team Fortress 2**, **Left 4 Dead 2**,
**Counter-Strike: Source**, **Garry’s Mod**.

Common indie / sim / sandbox: **Minecraft** (Java, OpenGL),
**Terraria**, **Stardew Valley**, **Don’t Starve**, **FTL**,
**Kerbal Space Program**, **Factorio**, **RimWorld**, **Hollow Knight**,
**Celeste**, **Dead Cells**, **The Binding of Isaac: Rebirth**,
**Civilization V**, **XCOM: Enemy Unknown**, **Euro Truck Simulator 2**,
plus **SuperTuxKart** and classic **Quake/Doom** source ports (GZDoom
OpenGL).

If the Linux build is from that era and the renderer is OpenGL, it is a
candidate. If it is Windows-only / Proton / Vulkan / anti-cheat, it is
not this path.

## Popular titles that are not this button

**GTA V**, **Skyrim**, **Elden Ring**, **Cyberpunk**, **Fortnite**,
**League of Legends**, **Valorant**, **CS2**, current **Dota 2**:
Proton/Vulkan/anti-cheat. Play on Intel at a lowered resolution, or
reboot the NVIDIA LTS / 470 entry if you want that stack.

## Brief black flash (observed 2026-08-17)

X11 DPMS was already **off** (keep-awake helper running; `xset` timeout
0). No i915 underrun in `dmesg` for that boot. KDE PowerDevil’s
**backlight helper** did run in the same minute as a short black-then-
normal flash. i915 logs `Skipping intel_backlight registration` on this
path, so Plasma may be poking **apple-gmux** brightness.

That is PowerDevil poking **apple-gmux** brightness, not a reason to
leave the 750M powered. The Intel path no longer force-maxes gmux
(`work-battery.md`). Do not send `IGD`/`DIS` to chase a flash.
