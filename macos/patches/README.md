# Compatibility Patches

## Go 1.26.5

[`go-1.26.5-big-sur.patch`](go-1.26.5-big-sur.patch) lowers the generated
Mach-O target to macOS 11 and restores certificate-chain APIs available on Big
Sur.

Apply it at the root of an authenticated Go 1.26.5 source tree:

```bash
patch -p0 < /path/to/go-1.26.5-big-sur.patch
```

The patch is intentionally version-specific. Do not assume it applies cleanly
or remains sufficient for a later Go release. See the
[validation record](../docs/go-1.26.5-validation.md) and the reproducible
[build script](../scripts/build-go-1.26.5-big-sur.sh).
