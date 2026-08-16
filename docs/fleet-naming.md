# Fleet Naming

Use these short names in SSH configs, scripts, and notes so the **MacBook Neo**
(controller Mac) is not confused with the **MacBook Pro 11,3 Retina** lab
machine (`MacBookPro11,3`) that RetinaForge targets.

| Short name | Hardware | Typical OS | Role |
| --- | --- | --- | --- |
| `neo` | MacBook Neo | macOS | Daily controller / fleet operator Mac |
| `mini` | LinuxMice mini | Linux | Additional controller; same `mbp113-*` SSH aliases |
| `Sparta` | Windows workstation | Windows | Additional controller; same `mbp113-*` SSH aliases |
| `mbp113-linux` | MacBook Pro 11,3 Retina (Late 2013) | CachyOS Linux | RetinaForge lab OS; **Intel i915 desktop target** |
| `mbp113-macos` | Same `MacBookPro11,3` unit | macOS Big Sur | Recovery reference and Intel-panel experiments |

Only one of `mbp113-linux` / `mbp113-macos` is reachable at a time (dual-boot).
Controller hosts should share the same SSH `Host` aliases so research can
continue from `neo`, `mini`, or `Sparta`. Keep real `HostName`, usernames, and
keys in local `~/.ssh/config` only.

## Legacy aliases

Older configs may still use vague names. Treat them as aliases, not separate
machines:

| Legacy alias | Maps to |
| --- | --- |
| `nitori` | `neo` |
| `macbook-linux`, `cachyos-x8664` | `mbp113-linux` |
| `macbook`, `retinaforge` (when meaning the lab laptop) | context-dependent: `mbp113-linux` or `mbp113-macos` |

When in doubt, prefer the `neo` / `mbp113-*` names in new material.

## Tailscale / LAN hostnames

SSH `Host` names are stable aliases you control. Tailscale machine names and
local `.home` / mDNS names may differ. Configure `HostName` in `~/.ssh/config`
from your tailnet or LAN; do not assume `Host` and Tailscale names match.

## Other fleet hosts

LinuxMice hosts (`lawnmower`, `mini`, `nerv`, …) keep their existing short
names. Only the two Apple laptops above needed disambiguation.

## Example SSH aliases

Keep real `HostName` values in local `~/.ssh/config` only. Example shape:

```ssh
Host neo nitori
  HostName <tailscale-or-lan-name-for-macbook-neo>
  User <your-macos-user>

Host mbp113-linux macbook-linux
  HostName <tailscale-or-lan-name-for-mbp113-cachyos>
  User <your-linux-user>

Host mbp113-macos macbook
  HostName <lan-name-for-mbp113-macos>
  User <your-macos-admin-user>
```

Legacy aliases on the same `Host` line keep old commands working while you
migrate scripts and muscle memory.
