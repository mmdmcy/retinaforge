# MacBookPro11,3 Intel Panel Ownership and Display Path (2026-08-01)

## Abstract

On `MacBookPro11,3` (Iris Pro 5200 + GeForce GT 750M + Apple GMUX), a
Linux boot path that combines (1) boot-time Apple Set OS via an EFI-stub
UKI and (2) Apple `gpu-power-prefs` written from macOS produced a stable
Intel-owned internal Retina panel under `i915`. Stock Limine entries that
boot the kernel with `protocol: linux` did not obtain Apple Set OS and
did not expose the iGPU. Discrete-GPU power-off via VGA switcheroo reduced
idle package temperature relative to a powered discrete client. External
1080p displays attached through a USB DisplayLink dock worked without
powering the GT 750M; sustained dual-DisplayLink desktop use was
CPU-heavy and thermally costly. Live GMUX handoff and forcing IGD mid-session
remained unsafe. Writable MSI+NCQ storage experiments remain out of scope
and rejected.

## Hardware and firmware context

| Item | Value |
| --- | --- |
| Model | `MacBookPro11,3` |
| iGPU | Intel Crystal Well / Iris Pro (`8086:0d26`) |
| dGPU | NVIDIA GK107M GT 750M Mac Edition (`10de:0fe9`) |
| Mux | Apple GMUX |
| Panel | Internal eDP Retina 2880×1800 |
| Reference OS | macOS Big Sur 11.7.x (APFS preserved) |
| Linux lab | CachyOS, Limine, UKI EFI stub |

Prior Windows probing on this same machine enumerated Iris Pro only when
chainloaded through a path that exercised Apple Set OS semantics, while
direct Windows boots restored NVIDIA-only visibility. Panel ownership was
not verified under Windows because `gpu-power-prefs` readback failed there.
See `docs/graphics/windows-intel-probe.md` and
`docs/source-notes/2026-07-29-windows-gmux-path.md`.

## Methods

### Boot path A — stock Limine `protocol: linux`

Limine loads `vmlinuz` + initramfs directly. The upstream kernel EFI stub
does not run as the loaded image, so firmware-side Apple Set OS associated
with EFI-stub entry is not applied by that path.

### Boot path B — Limine EFI entry to UKI / EFI stub

Limine loads a UKI (or equivalent EFI application) that enters the kernel
through the EFI stub. Upstream `apple_set_os()` can then run. The lab entry
was labeled as an Intel probe UKI and set as the Limine default entry for
repeatable boots.

### Panel preference

Apple `gpu-power-prefs` was written from macOS (not from Linux):

- Intel preference: `%01%00%00%00`
- Discrete preference: `%00%00%00%00`

Linux writes to this variable were previously observed as stubbed or not
reliably readable; macOS remains the supported writer for this workbench.

### Observations recorded

- DRM framebuffer name / connector state for internal eDP
- `vga_switcheroo` client power lines for IGD and DIS
- Approximate CPU package temperature at idle and under DisplayLink load
- Behavior of live `switcheroo` / `force_igd` style interventions
- External outputs via DisplayLink (USB) versus native GPU display links

No disk serials, hostnames, addresses, or raw captures are included here.
Aggregates only.

## Results

### 1. Apple Set OS is path-dependent under Limine

| Boot path | iGPU enumeration | Internal panel owner (lab outcome) |
| --- | --- | --- |
| Limine `protocol: linux` | Not obtained in the Intel-first configuration | Not used for Intel-panel daily attempts |
| Limine → UKI / EFI stub | `8086:0d26` present | `i915drmfb`, eDP 2880×1800 |

**Finding.** On this machine, “Limine boots Linux” is not sufficient for
Intel-first graphics. The image must enter through the EFI stub so Apple
Set OS runs. Keep stock `protocol: linux` entries only as nomodeset /
recovery fallbacks.

### 2. `gpu-power-prefs` from macOS selects Intel panel ownership

After setting Intel `%01…` in macOS and booting path B:

- Framebuffer reported as `i915drmfb`
- Internal connector active at 2880×1800
- Switcheroo showed IGD powered and selected

**Finding.** The combination EFI-stub Apple Set OS **plus** macOS-written
Intel `gpu-power-prefs` is the verified panel path. Either alone was not
treated as sufficient for a claimed Intel-owned Retina desktop.

### 3. Live mux handoff remains fragile

Attempts to force IGD or perform careless live IGD/DIS handoff produced
black screens. Boot-time preference plus a clean UKI boot was reliable;
mid-session mux surgery was not.

**Finding.** Do not use live `apple_gmux.force_igd=1` or ad-hoc switcheroo
handoff as a substitute for EFI preference + clean boot. Documented as a
hard operational stop for this workbench.

### 4. Discrete GPU power state vs thermals

With Intel owning the panel:

- Explicit `OFF` through `vga_switcheroo` for the discrete client yielded
  cooler idle package temperatures (order ~50–56 °C under light desktop
  idle in lab notes) than runs where DIS remained powered.
- After some boots/sessions, DIS was observed powered again (`:Pwr`) while
  IGD remained the panel owner; re-issuing `OFF` restored the cooler idle
  profile.

**Finding.** “Nouveau loaded” or “NVIDIA PCI visible” is not rail-off.
Switcheroo `OFF` is a distinct, measurable state and matters for thermals.
Persistence of `OFF` across boots/sessions should not be assumed without
re-check.

### 5. External displays: DisplayLink without GT 750M

A USB DisplayLink dock (`17e9:6015` class device in lab) drove two
1920×1080 panels under X11 while the discrete GPU remained off.

| Configuration | Outcome |
| --- | --- |
| DisplayLink dual 1080p + Intel eDP | Functional span/mirror layouts |
| Same, sustained | High userspace CPU (DisplayLink manager ~tens of percent) and elevated package temperature (~67–81 °C class under load) |
| DisplayLink service masked | Returns to laptop-only; cooler |

Native DisplayPort/HDMI behavior through the GT 750M was **not** re-proven
in this session and remains a separate experiment from USB DisplayLink.

**Finding (corrects an over-broad earlier assumption).** External pixels on
this machine are not exclusively gated on powering the GT 750M when a
DisplayLink path is used. DisplayLink is a practical presenting path and a
poor all-day thermal path.

### 6. Desktop stack notes (X11)

- Multi-GPU X11 required explicit DRM device preference for the Intel card
  when both GPUs were visible.
- A heavy Plasma/X11 session exhibited hard UI stalls under the lab
  configuration; a lighter Xfce/X11 session remained usable for validation
  work.
- Retina UI scaling was effective only when toolkit scale factors were
  actually inherited by the session (example: Qt scale 1.5 usable;
  2.0 oversized for this panel density).

These desktop observations are environmental, not driver proofs. They
matter for experiment operators who need a usable console while collecting
GPU evidence.

## Negative results / non-goals this session

- No claim of Big Sur–equivalent automatic graphics switching.
- No Nouveau modeset or CUDA bring-up campaign.
- No GMUX register-level rail-off proof beyond switcheroo `OFF` observation.
- No writable MSI+NCQ storage retest (permanently rejected elsewhere).
- No assertion that Homebrew or third-party VM stacks on Big Sur are part of
  the graphics evidence chain.

## Implications for upstream-oriented work

1. **Reproducible Intel-first boot recipe (this hardware):** macOS sets Intel
   `gpu-power-prefs` → Limine loads UKI/EFI stub → verify `i915drmfb` + eDP →
   optionally `switcheroo OFF` for DIS → record thermals.
2. **Separate experiments:** (a) GT 750M native outputs / Nouveau or
   proprietary, (b) GMUX D3cold/rail measurement, (c) suspend/resume with
   Intel panel ownership, (d) DisplayLink-only presenting policy.
3. **Do not conflate** driver blacklist, PCI D3hot, switcheroo `OFF`, and
   physical rail-off in reports.
4. Keep graphics patches and AHCI/libata patches in separate series with
   separate evidence.

## Reproducibility checklist

- [ ] Confirm Limine entry uses EFI/UKI stub, not bare `protocol: linux`
- [ ] Confirm `gpu-power-prefs` Intel value from an OS that can write it
- [ ] Record `ls /sys/class/drm`, fb name, switcheroo dump, package temp
- [ ] If testing externals, record whether outputs are DisplayLink or GPU
- [ ] Photograph/log black-screen incidents; do not iterate live mux guesses
- [ ] Preserve APFS; no MSI+NCQ writable storage trials

## References (in-repo)

- `docs/source-notes/2026-07-24-macbookpro11-3-graphics-upstream.md`
- `docs/source-notes/2026-07-29-windows-gmux-path.md`
- `docs/graphics/README.md`
- `docs/findings.md` (graphics subsection)
- Upstream Apple Set OS / product-name support:
  [`71e49eccdca6`](https://github.com/torvalds/linux/commit/71e49eccdca6328eecc335ed8f5557bd0ed70fc6)
