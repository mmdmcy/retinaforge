# Go 1.26.5 On macOS Big Sur

- Test date: `2026-07-24`
- Host: Intel `MacBookPro11,3`
- Operating system: macOS Big Sur `11.7.11`
- Upstream version: Go `1.26.5`
- Source SHA-256:
  `495be4bc87176ac567392e5b4116abd98466d33d7b49d41e764ccc6976b2dc42`

## Baseline Failure

The authenticated, unmodified source completed all bootstrap stages. Its new
`go` binary did not run on Big Sur:

```text
dyld: Symbol not found: _SecTrustCopyCertificateChain
```

Mach-O metadata also declared a minimum operating-system version of macOS 12.
The compile therefore succeeded while the resulting toolchain remained
incompatible with the host.

## Compatibility Change

The patch:

1. changes the generated Mach-O minimum target from macOS 12.0 to 11.0;
2. replaces Monterey's `SecTrustCopyCertificateChain` call with the older
   `SecTrustGetCertificateCount` and `SecTrustGetCertificateAtIndex` APIs.

The certificate APIs match the approach used by the last Go release line that
officially supported Big Sur.

## Result

The patched build:

- reported `go version go1.26.5 darwin/amd64`;
- produced Mach-O output with minimum OS `11.0`;
- compiled and ran an HTTPS request to `go.dev`, receiving HTTP 200;
- used the macOS 11 SDK available on the host.

Targeted package tests passed:

| Test | Result | Approximate time |
| --- | --- | ---: |
| `go test crypto/x509` | Pass | 103 s |
| `go test crypto/tls` | Pass | 99 s |
| `go test net/http` | Pass | 65 s |
| `go test runtime` | Pass | 267 s |
| Mach-O internal/external/cgo link mode | Pass | included in targeted linker checks |

The complete linker package encountered one Objective-C fixture failure in
Apple's Foundation SDK with Apple Clang 12. The same
`TestMachoIssue32233` failure reproduced under the stable Go 1.24 toolchain,
so it is a baseline SDK/compiler limitation rather than evidence of a
regression introduced by this patch.

## Scope Of The Claim

This proves that the Go 1.26.5 compiler and tested standard-library paths can
run natively on this Big Sur machine with the documented patch. It does not
claim official upstream support, full conformance across every package, or
future compatibility with later Go releases.

The original MacPorts Go installation was not replaced during testing.
