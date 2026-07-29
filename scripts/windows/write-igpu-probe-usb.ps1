# SPDX-License-Identifier: GPL-2.0-only
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 255)]
    [int]$DiskNumber,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactRoot,

    [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    throw "error: $Message"
}

function Assert-ArtifactChecksums([string]$Root, [string]$ManifestPath) {
    $failures = @()
    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(\.\/)?(.+)$') {
            Fail "invalid SHA256SUMS line: $line"
        }
        $expected = $Matches[1].ToUpperInvariant()
        $relative = $Matches[3] -replace '/', '\'
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)') {
            Fail "unsafe SHA256SUMS path: $relative"
        }
        $target = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $failures += "missing: $relative"
            continue
        }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
        if ($actual -cne $expected) { $failures += "hash mismatch: $relative" }
    }
    if ($failures.Count) { Fail ($failures -join '; ') }
}

$artifact = (Resolve-Path -LiteralPath $ArtifactRoot).Path
$bootloader = Join-Path $artifact "EFI\BOOT\BOOTX64.EFI"
$manifest = Join-Path $artifact "SHA256SUMS"
if (-not (Test-Path -LiteralPath $bootloader -PathType Leaf)) {
    Fail "probe bootloader not found: $bootloader"
}
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    Fail "probe checksum manifest not found: $manifest"
}
Assert-ArtifactChecksums -Root $artifact -ManifestPath $manifest

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$model = ([string]$disk.FriendlyName).Trim()
$size = [uint64]$disk.Size
if ($disk.BusType -ne "USB") { Fail "disk $DiskNumber is not USB" }
if ($disk.IsBoot -or $disk.IsSystem) { Fail "disk $DiskNumber is a boot/system disk" }
if ($disk.Number -eq 0) { Fail "disk 0 is permanently refused" }
if ($model -match "APPLE SSD SM1024F") { Fail "the internal Apple SSD is permanently refused" }
if ($size -lt 4GB -or $size -gt 256GB) { Fail "USB size is outside the 4-256 GiB safety range" }
if ($disk.OperationalStatus -notcontains "Online") { Fail "USB is not online" }

$artifactDrive = (Get-Item -LiteralPath $artifact).PSDrive
if ($artifactDrive -and $artifactDrive.Name -match '^[A-Za-z]$') {
    $artifactPartition = Get-Partition -DriveLetter $artifactDrive.Name -ErrorAction SilentlyContinue
    if ($artifactPartition -and $artifactPartition.DiskNumber -eq $DiskNumber) {
        Fail "artifact source is on disk $DiskNumber and would be erased"
    }
}

$tokenModel = $model -replace ':', '_'
$token = "ERASE:$DiskNumber`:$size`:$tokenModel"

Write-Host "Validated candidate USB (no writes performed):"
$disk | Format-List Number, FriendlyName, BusType, PartitionStyle, Size, OperationalStatus, HealthStatus, IsBoot, IsSystem
Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Format-Table PartitionNumber, DriveLetter, Type, Size -AutoSize
Get-Volume -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter -and (Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue).DiskNumber -eq $DiskNumber } |
    Format-Table DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining -AutoSize

if (-not $Confirm) {
    Write-Host ""
    Write-Host "To erase this exact USB, rerun from Administrator PowerShell with:"
    Write-Host "  -Confirm '$token'"
    exit 2
}
if ($Confirm -cne $token) { Fail "confirmation token does not match this disk, size, and model" }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail "destructive invocation requires Administrator PowerShell"
}

# Re-read every destructive identity gate after elevation and confirmation.
$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
if ($disk.Number -eq 0 -or $disk.BusType -ne "USB" -or [uint64]$disk.Size -ne $size -or
    ([string]$disk.FriendlyName).Trim() -cne $model -or $disk.IsBoot -or $disk.IsSystem) {
    Fail "disk identity changed after confirmation"
}

Write-Host "Erasing validated USB disk $DiskNumber..."
Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Where-Object DriveLetter |
    ForEach-Object { Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $_.PartitionNumber -AccessPath "$($_.DriveLetter):\" -ErrorAction SilentlyContinue }
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
Initialize-Disk -Number $DiskNumber -PartitionStyle GPT | Out-Null
$partition = New-Partition -DiskNumber $DiskNumber -Size 1GB -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}" -AssignDriveLetter
$volume = Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel "MBP_IGPU" -Confirm:$false
$root = "$($volume.DriveLetter):\"

Copy-Item -LiteralPath (Join-Path $artifact "EFI") -Destination $root -Recurse -Force
Copy-Item -LiteralPath (Join-Path $artifact "PROBE-README.txt") -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $artifact "SOURCE.txt") -Destination $root -Force
Copy-Item -LiteralPath $manifest -Destination $root -Force

Assert-ArtifactChecksums -Root $root -ManifestPath $manifest

$bootHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root "EFI\BOOT\BOOTX64.EFI")).Hash
Write-Host ""
Write-Host "USB provisioned and read-back verified."
Write-Host "Disk: $DiskNumber"
Write-Host "Volume: $root ($($volume.FileSystemLabel))"
Write-Host "BOOTX64.EFI SHA-256: $bootHash"
Write-Host "Do not perform the first boot unattended."
