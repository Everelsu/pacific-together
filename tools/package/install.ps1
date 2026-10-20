# Installs (or removes) Pacific Together into the Steam copy of Pacific Drive. Run from the unpacked zip:
#   install.cmd                      host: you start the game and your friend joins you
#   install.cmd -Join 100.64.1.2     guest: joins that host when the game reaches the main menu
#   install.cmd -Uninstall           removes UE4SS and the mod; saves are left alone
param(
    [string]$Join = "",
    [string]$GameDir = "",
    [switch]$Uninstall,
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$ExeSha = "568BB63476C6DE5FC2B1878572A655DD631DD25BB44FE304E3D96A51F6B98F7E"  # Steam build 21896301 (v1.15.0)

if (-not $GameDir) {
    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
    $libs = @()
    if ($steam) {
        $libs += $steam
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) { $libs += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } }
    }
    $GameDir = $libs | ForEach-Object { Join-Path $_ "steamapps\common\Pacific Drive" } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $GameDir) { throw "Pacific Drive not found in your Steam libraries. Run again with -GameDir `"<folder with PenDriverPro>`"" }
}
$bin = Join-Path $GameDir "PenDriverPro\Binaries\Win64"
$exe = Join-Path $bin "PenDriverPro-Win64-Shipping.exe"
if (-not (Test-Path $exe)) { throw "not a Pacific Drive folder: $GameDir" }
if (Get-Process PenDriverPro* -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$GameDir*" }) { throw "close Pacific Drive first" }
Write-Host "Game: $GameDir"

if ($Uninstall) {
    Remove-Item (Join-Path $bin "dwmapi.dll") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $bin "ue4ss") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed. Your saves were not touched."
    exit 0
}

if ((Get-FileHash $exe).Hash -ne $ExeSha -and -not $Force) {
    throw "your game build differs from the one this mod was tested on (Steam probably updated it). Wait for a new mod build, or run with -Force at your own risk."
}

# one backup per install, before the modded game ever runs
$saved = Join-Path $env:LOCALAPPDATA "PenDriverPro\Saved"
if (Test-Path $saved) {
    $backup = Join-Path ([Environment]::GetFolderPath("MyDocuments")) ("PacificDrive-saves-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".zip")
    Compress-Archive -Path $saved -DestinationPath $backup
    Write-Host "Saves backed up to $backup"
}

Copy-Item (Join-Path $PSScriptRoot "game\*") $bin -Recurse -Force
$joinFile = Join-Path $bin "ue4ss\Mods\PacificTogether\join.txt"
if ($Join) {
    [IO.File]::WriteAllText($joinFile, $Join)
    Write-Host "Installed as GUEST: the game joins $Join from the main menu."
} else {
    Remove-Item $joinFile -Force -ErrorAction SilentlyContinue
    Write-Host "Installed as HOST: load your save, your friend joins you."
}
