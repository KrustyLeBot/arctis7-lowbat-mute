<#
.SYNOPSIS
    Install (or undo) the patched Arctis 7 headset firmware in SteelSeries GG.

.DESCRIPTION
    Run from an ADMINISTRATOR PowerShell (GG lives in Program Files). Nothing is flashed here: GG flashes
    when you click "Click to install" in its Engine page.

      .\install.ps1 install   back up the originals, copy the patched firmware, make GG offer the update
      .\install.ps1 restore   remove the patched firmware and the backups, leave only the official firmware,
                              and make GG offer the update again so the headset gets it back

    Backups are named "original-<name>.bak" and stay next to the originals. They must NOT start with
    "firmware": GG picks its firmware file in the folder with the pattern ^firmware.

.PARAMETER Firmware
    The patched headset firmware (.ef). Default: the single .ef in the "out" folder next to this script, or,
    if there is no "out" folder, the single .ef right next to this script (handy for a release: .ef + install.ps1).

#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet("install", "restore")][string]$Action,
    [string]$Firmware,
    [string]$GgDir = "C:\Program Files\SteelSeries\GG\apps\engine\firmware",
    [switch]$NoAdminCheck      # for tests on a copy of GG's folder
)
$ErrorActionPreference = "Stop"
# Written to version.json so that GG sees "a newer version" and shows the update. It is not a setting: it only
# has to be higher than the version GG reads from the device. The firmware's own version is never changed.
$OfferVersion = "1.42.0.0"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoAdminCheck) { throw "Run this script from an administrator PowerShell." }

# --- locate GG's folders by the device_name in each version.json (headset = rx, dongle = tx) -------------
function Find-DeviceFolder([string]$DeviceName) {
    if (-not (Test-Path $GgDir)) { throw "GG firmware folder not found: $GgDir (use -GgDir if GG is installed elsewhere)." }
    foreach ($dir in Get-ChildItem $GgDir -Directory) {
        $json = Join-Path $dir.FullName "version.json"
        if ((Test-Path $json) -and ((Get-Content $json -Raw | ConvertFrom-Json).device_name -eq $DeviceName)) { return $dir.FullName }
    }
    throw "No GG firmware folder for '$DeviceName' in $GgDir (is GG installed, was the headset connected once?)."
}
$headset = Find-DeviceFolder "arctis_7_2018_rx"
$dongle  = Find-DeviceFolder "arctis_7_2018_tx"

function Get-BackupPath([string]$Path) { Join-Path (Split-Path $Path) ("original-" + (Split-Path $Path -Leaf) + ".bak") }
function Save-Backup([string]$Path) {            # never overwrites an existing backup: that one is the original
    $bak = Get-BackupPath $Path
    if (-not (Test-Path $bak)) { Copy-Item $Path $bak; Write-Host "  backup: $bak" }
}
function Restore-Backup([string]$Path) {
    $bak = Get-BackupPath $Path
    if (Test-Path $bak) { Copy-Item $bak $Path -Force; Write-Host "  restored: $Path" }
}
function Set-OfferVersion([string]$Folder) {     # same json, only firmware_version changed
    $path = Join-Path $Folder "version.json"
    $info = Get-Content $path -Raw | ConvertFrom-Json
    $info.firmware_version = $OfferVersion
    ($info | ConvertTo-Json) | Set-Content $path -Encoding ASCII
}
function Get-FirmwareFiles([string]$Folder) { @(Get-ChildItem $Folder -File | Where-Object { $_.Name -like "firmware*" }) }

switch ($Action) {
    "install" {
        if (-not $Firmware) {                       # look in .\out first, then next to this script
            foreach ($dir in (Join-Path $PSScriptRoot "out"), $PSScriptRoot) {
                $found = @(if (Test-Path $dir) { Get-ChildItem $dir -Filter *.ef -File })
                if ($found.Count -gt 1) { throw "Several .ef files in ${dir}: pass the right one with -Firmware." }
                if ($found.Count -eq 1) { $Firmware = $found[0].FullName; break }
            }
        }
        if (-not $Firmware -or -not (Test-Path $Firmware)) { throw "Patched firmware not found (looked in .\out and next to this script). Run patch_lowbat.py first, or pass -Firmware." }
        $patchedName = Split-Path $Firmware -Leaf
        if ($patchedName -notlike "firmware*") { throw "The firmware file name must start with 'firmware' (GG's pattern)." }

        $current = Get-FirmwareFiles $headset
        if ($current.Count -ne 1) { throw "Expected exactly one firmware* file in $headset, found $($current.Count)." }
        if ((Get-FileHash $current[0].FullName).Hash -eq (Get-FileHash $Firmware).Hash -and
            -not (Test-Path (Get-BackupPath $current[0].FullName))) {
            throw "The patched firmware is already in GG's folder and there is no backup of the original."
        }
        $base = [version](Get-Content (Join-Path $headset "version.json") -Raw | ConvertFrom-Json).firmware_version
        if (Test-Path (Get-BackupPath (Join-Path $headset "version.json"))) {
            $base = [version](Get-Content (Get-BackupPath (Join-Path $headset "version.json")) -Raw | ConvertFrom-Json).firmware_version
        }
        if ($base -gt [version]$OfferVersion) { throw "GG's firmware version $base is not below ${OfferVersion}: GG would not offer the update." }

        Write-Host "Backups:"
        Save-Backup $current[0].FullName
        Save-Backup (Join-Path $headset "version.json")
        Save-Backup (Join-Path $dongle "version.json")
        Remove-Item $current[0].FullName
        Copy-Item $Firmware (Join-Path $headset $patchedName)
        Set-OfferVersion $headset
        Set-OfferVersion $dongle                  # the update offer appears on the dongle's card
        Write-Host "Installed $patchedName; version.json (headset and dongle) -> $OfferVersion"
        Write-Host "`nNext: restart GG (it only reads version.json at startup), connect the headset with its micro-USB cable,"
        Write-Host "then GG > Engine > Arctis 7 > 'Click to install'. Unplug nothing until it is done."
        Write-Host "Afterwards, switch the headset off and on."
    }
    "restore" {
        $bak = @(Get-ChildItem $headset -File | Where-Object { $_.Name -like "original-firmware*.ef.bak" })
        if ($bak.Count -ne 1) { throw "No original firmware backup (original-firmware*.ef.bak) in $headset." }
        Get-FirmwareFiles $headset | Remove-Item                       # the patched firmware goes away
        Move-Item $bak[0].FullName (Join-Path $headset $bak[0].Name.Substring("original-".Length).Replace(".bak", ""))
        foreach ($folder in $headset, $dongle) {
            Get-ChildItem $folder -File -Filter "original-*.bak" | Remove-Item   # leave only the official files
            Set-OfferVersion $folder
        }
        Write-Host "Only the official firmware is left in GG's folder, version.json -> $OfferVersion so GG offers the update."
        Write-Host "Restart GG, connect the headset with its micro-USB cable, then GG > Engine > Arctis 7 > 'Click to install'."
    }
}
