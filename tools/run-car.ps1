# X7 carride: starts the lag relay (guest -> Port+1 -> host Port), runs the scenario, then the error analysis.
# Exit code 0 = the scenario's checks and the car-error checks passed.
param(
    [string]$Scenario = "carride",
    [string]$Root = "C:\PacificTogetherTest",
    [int]$Port = 7777,
    [string]$Mutate = "",
    [switch]$Headless,
    [string]$ResultsDir = "",
    [int]$Seconds = 600
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $ResultsDir) { $ResultsDir = Join-Path $Repo "local\test-results" }
$guestLog = Join-Path $Root "client2\PenDriverPro\Binaries\Win64\ue4ss\UE4SS.log"
# the relay follows the guest's "PT|lag" lines; an old log must not set the first lag
Remove-Item $guestLog -ErrorAction SilentlyContinue
$relayOut = Join-Path $env:TEMP "pt-udp-lag-$Port.txt"
$relay = Start-Process powershell -ArgumentList "-NoProfile", "-File", "$PSScriptRoot\udp-lag.ps1", "-Listen", ($Port + 1), "-Target", $Port,
    "-WatchLog", $guestLog, "-Seconds", ($Seconds + 120) -PassThru -WindowStyle Hidden -RedirectStandardOutput $relayOut
$started = Get-Date
try {
    $a = @{ Scenario = $Scenario; Root = $Root; Port = $Port; Seconds = $Seconds; ResultsDir = $ResultsDir }
    if ($Mutate) { $a.Mutate = $Mutate }
    if ($Headless) { $a.Headless = $true }
    & "$PSScriptRoot\run-test.ps1" @a
    $code = $LASTEXITCODE
} finally {
    if (-not $relay.HasExited) { Stop-Process $relay -Force }
}
$results = Get-ChildItem $ResultsDir -Directory | Where-Object { $_.Name -like "*-$Scenario*" -and $_.CreationTime -ge $started } |
    Sort-Object CreationTime | Select-Object -Last 1
if (-not $results) { Write-Host "no results folder"; exit 1 }
Copy-Item $relayOut (Join-Path $results.FullName "relay.txt") -ErrorAction SilentlyContinue
& "$PSScriptRoot\car-error.ps1" -Results $results.FullName
$carCode = $LASTEXITCODE
Write-Host "results: $($results.FullName)"
if ($code -eq 0 -and $carCode -eq 0) { exit 0 } else { exit 1 }
