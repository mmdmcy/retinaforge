# 2026-07-24 `MacBookPro11,3` Graphics Upstream Review

- Checked: `2026-07-24 Europe/Amsterdam`
- Researcher: `Codex`
- Scope: current native-Linux support for the Iris Pro 5200, NVIDIA GK107M
  GeForce GT 750M, Apple GMUX, panel selection, dGPU power-off, and external
  displays on this exact model.
- Status: a credible Intel-first native route exists; a stable, fully automatic
  dual-GPU route is not yet demonstrated on this machine.

## Questions

- Can current upstream Linux expose the firmware-hidden Intel GPU without a
  third-party EFI shim?
- Can Linux actually remove power from the GT 750M rather than merely leave it
  driverless?
- Should Nouveau be blacklisted for an Intel-only daily-driver setup?
- What functionality is lost when the NVIDIA GPU is off?
- Is compiling the proprietary 470 driver a better modern route?

## Source Register

| Source | Authority | Checked | Status | Notes |
| --- | --- | --- | --- | --- |
| [EFI-stub `apple_set_os()` commit `71e49eccdca6`](https://github.com/torvalds/linux/commit/71e49eccdca6328eecc335ed8f5557bd0ed70fc6) | Upstream kernel commit | 2026-07-24 | Required, present in 7.1.3 | Explicitly includes `MacBookPro11,3` so Apple firmware leaves its Intel GPU enabled. |
| [SMBIOS fallback commit `4f90742d4a09`](https://github.com/torvalds/linux/commit/4f90742d4a09a8253861b0d5fd0984e3cd399c9b) | Upstream kernel commit | 2026-07-24 | Required, present in 7.1.3 | Makes product matching work on Apple EFI implementations where the normal SMBIOS lookup is unavailable. |
| [Linux VGA Switcheroo and Apple GMUX documentation](https://docs.kernel.org/gpu/vga-switcheroo.html) | Official kernel documentation/source | 2026-07-24 | Current | Documents EFI selection, manual switching, real GMUX rail control, Retina eDP behavior, and dGPU-only external links. |
| [Linux `apple-gmux.c`](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/apple-gmux.c) | Upstream kernel source | 2026-07-24 | Current | Implements Retina indexed GMUX, panel switching, and sequenced dGPU core/VRAM/PCIe rail shutdown. |
| [Linux `vga_switcheroo.c`](https://github.com/torvalds/linux/blob/master/drivers/gpu/vga/vga_switcheroo.c) | Upstream kernel source | 2026-07-24 | Current | `OFF` suspends the inactive GPU client and then invokes the handler's power callback. |
| [Linux Nouveau core](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nouveau_drm.c) and [switcheroo client](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/nouveau/nouveau_vga.c) | Upstream kernel source | 2026-07-24 | Current | Runtime PM defaults to Optimus/DSM systems; manual switcheroo remains the clearer Apple-GMUX path. |
| [Nouveau current status](https://nouveau.freedesktop.org/) | Upstream project | 2026-07-24 | Current | Kepler has OpenGL, Vulkan/NVK, video decoding on most pre-Maxwell cards, and manual—not automatic—reclocking. |
| [Nouveau power-management matrix](https://nouveau.freedesktop.org/PowerManagement.html) | Upstream project | 2026-07-24 | Current, caution | Kepler/NVE0 engine and memory reclocking remain work in progress; automatic reclocking is unavailable. |
| [Mesa NVK documentation](https://docs.mesa3d.org/drivers/nvk.html) | Upstream Mesa documentation | 2026-07-24 | Current | NVK supports Kepler but warns that some enumerated GPUs may be poorly tested or broken; requires Linux 6.6+. |
| [NVIDIA Unix driver archive](https://www.nvidia.com/en-us/drivers/unix/) | Vendor | 2026-07-24 | Legacy | Lists `470.256.02` as the latest 470 legacy release; it dates from 2024. |
| [NVIDIA supported-chip list](https://download.nvidia.com/XFree86/Linux-x86_64/570.133.07/README/supportedchips.html) | Vendor | 2026-07-24 | Current classification | PCI IDs `0fe4` and `0fe9` are relegated to the legacy 470 branch. |

## Findings

### The Intel path is now upstream

Linux can use the Intel Iris Pro without compiling a private GPU driver or
running an old `apple_set_os.efi` shim. A current kernel entered through its
EFI stub calls Apple's `set_os` protocol for `MacBookPro11,3`; the later SMBIOS
fallback makes that match reliable on affected Apple firmware.

The boot path matters. A UKI chainloaded as an EFI application is the clearest
way to guarantee that the EFI-stub logic runs. Merely using a new kernel is not
proof if a bootloader bypasses the relevant EFI entry path.

The initial panel owner can then be selected through Apple's
`gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9` variable. Its fifth byte
selects Intel (`1`) or discrete NVIDIA (`0`). This is a boot-time preference,
not a safe excuse for an unprepared live handoff.

### Real dGPU power-off requires GMUX coordination

Apple GMUX is not just a display selector. Upstream `apple-gmux` sequences the
GT 750M's core voltage, VRAM, and PCIe power rails. In manual
`vga_switcheroo` mode, `OFF` first asks the inactive GPU driver to suspend the
device and then calls the GMUX power handler.

This creates a counterintuitive requirement: both graphics drivers and the
GMUX handler must register before `/sys/kernel/debug/vgaswitcheroo/switch`
becomes usable. Blacklisting Nouveau may prevent rendering on the GT 750M, but
it also removes the normal Nouveau client used for a coordinated suspend.
Therefore:

- `nouveau` absent is not evidence that the GT 750M is off;
- `nouveau` loaded does not mean it must render the desktop;
- the strongest Intel-only candidate is i915 owning the panel while Nouveau
  remains an inactive switcheroo client, followed by a verified manual `OFF`;
- forcing Nouveau runtime PM is not the first choice. Its default runtime-PM
  detection targets Optimus/DSM machines, and the Apple-GMUX power path is
  clearer in switcheroo's manual mode.

No power command should be issued until the switcheroo state proves that Intel
is active and NVIDIA is inactive, and no process has the NVIDIA DRM or HDA
device open.

### External displays are a hardware tradeoff

On pre-T2 Retina generations, the internal eDP panel is muxed but the newer
Thunderbolt/DisplayPort main links cannot be fully switched to Intel. Upstream
documents that those **native GPU display links** can only be driven by the
discrete GPU.

**Supersession (2026-08-01):** USB DisplayLink outputs are a separate path.
Lab work drove dual 1080p DisplayLink panels with the GT 750M left off; that
does not validate native DP/HDMI through the dGPU. See
[`2026-08-01-intel-panel-and-display-path.md`](2026-08-01-intel-panel-and-display-path.md).

An Intel-only, dGPU-off mode therefore sacrifices **native** external-display
output unless an alternate transport (for example DisplayLink) is accepted.
A complete native-connector configuration still needs an explicit NVIDIA-on
mode:

- safest first implementation: a separate boot entry preselected for NVIDIA;
- later possibility: keep the panel on Intel and wake the NVIDIA GPU for the
  external connector, but validate it independently because that uses both
  GPUs and a more complex display stack.

This is physical routing, not a distro defect and not something native
compilation can remove.

### Nouveau is usable, but Kepler performance management is unfinished

The GT 750M is GK107/NVE7 Kepler. Current Nouveau reports:

- OpenGL support;
- Kepler Vulkan support through NVK on modern Mesa and Linux 6.6+;
- video decode support on most pre-Maxwell GPUs;
- manual performance-state selection;
- no automatic Kepler reclocking, with engine and memory reclocking still
  marked work in progress.

That is enough to justify a controlled native test for display output and
ordinary acceleration. It is not enough to promise proprietary-driver-level
performance, seamless switching, or safe manual reclocking. First testing
should leave clock controls untouched.

### Compiling NVIDIA 470 is not the preferred modern route

The exact PCI ID remains on NVIDIA's 470 legacy branch, whose latest official
release is `470.256.02` from 2024. Compiling its kernel interface can sometimes
bridge newer kernel API changes, but it does not modernize the closed user-space
stack, improve Apple GMUX integration, or turn legacy support into a current
Wayland path. It would also replace an upstream-debuggable stack with a
permanent out-of-tree compatibility burden.

Keep 470 as a narrowly scoped fallback only if Nouveau cannot drive a required
external-display workload and an Xorg-oriented configuration is acceptable.
It should not be the baseline for the native daily-driver design.

## Proposed Native Graphics Architecture

This is a design, not authorization to mutate the machine.

### Intel daily mode

1. Use a current upstream kernel containing both Apple EFI commits and built
   with `CONFIG_APPLE_GMUX`, i915, Nouveau, debugfs, and VGA Switcheroo.
2. Boot a one-time UKI through the EFI application path while retaining macOS
   and a known-good boot entry.
3. Back up and verify the complete original `gpu-power-prefs` EFI variable,
   then select Intel only for the isolated test.
4. Confirm the Intel GPU exists, i915 owns the internal panel, Apple GMUX
   registered, and the desktop is usable before any power operation.
5. Load Nouveau as the inactive dGPU client with manual switcheroo power
   control; do not enable experimental reclocking.
6. Confirm switcheroo reports `IGD` active and `DIS` inactive, and identify
   any process holding the NVIDIA DRM or HDA nodes.
7. Issue only `OFF`, not a live `IGD` handoff, and verify switcheroo reports
   the discrete client off. Record temperature, battery draw, suspend/resume,
   cold boot, brightness, and kernel logs.
8. Keep a paired rollback and remote recovery path. Do not make the EFI
   preference or boot policy persistent until repeated cold boots pass.

### NVIDIA/external-display mode

1. Use a separate one-time boot entry with the original/discrete EFI
   preference.
2. Test Nouveau at default clocks first with the internal panel and one
   external display.
3. Validate Xorg or the selected Wayland compositor, suspend/resume, hotplug,
   audio over the external connector, and thermals.
4. Test NVK and any manual performance state only after display stability is
   established.
5. Consider proprietary 470 only after a logged Nouveau blocker, and keep it
   out of the Intel daily-mode image.

## Product Implications

- A native Intel-first Linux laptop is technically credible without writing a
  new graphics driver.
- The best route uses more upstream integration, not more blacklisting.
- Full dGPU power-off and **native** external-display support are mutually
  exclusive operating states on this model; the configuration should expose
  both as named boot/use modes. USB DisplayLink is a separate transport and
  does not refute that native-link tradeoff (see 2026-08-01 note).
- Graphics work does not solve the independent internal-SSD flush problem.
- The first graphics experiment should run from independent Linux storage or
  after storage is acceptable, and must not be mixed with an AHCI experiment.

## Recheck Triggers

- Nouveau adds automatic Kepler reclocking or Apple-GMUX runtime-PM support.
- Mesa changes NVK's Kepler support level or default OpenGL path.
- A current distro removes Nouveau Kepler packages or 470 compatibility.
- Physical logs show `apple-gmux`, i915, Nouveau, or switcheroo failing to
  register on this exact machine.

## Open Questions

- Does the one-time EFI/UKI path consistently expose Intel after cold boot on
  this machine?
- With Intel preselected, does `OFF` produce a stable GMUX power cut across
  suspend/resume and repeated boots?
- Can the external connector be used reliably with the panel left on Intel,
  or is a discrete-preselected boot materially more stable?
- Does this exact `0fe9` board run NVK and default Nouveau clocks reliably
  enough for the required workloads?
