# D23 / Q9 proof: one deliberate guest crash on a test pair while Windows Firewall blocks the pair's exes outbound, then check that
# nothing tried to leave the machine. NEEDS AN ELEVATED POWERSHELL (firewall rule, audit policy, Security log). Run by the owner only.
#
#   powershell -File tools\q9-firewall.ps1 -Root C:\PacificTogetherTest -Port 7821 -ResultsDir <repo>\local\test-results
#   -DryRun      print what would happen, change nothing, run nothing (works without admin)
#   -NoCrc       do not put CrashReportClient.exe into the guest copy (the refusal is then not exercised, only Sentry/crashpad)
#
# What it does, in order (the finally block undoes every change even when something fails or you press Ctrl+C):
#   1. copies CrashReportClient.exe from the Steam install (read only) into <Root>\client2\Engine\Binaries\Win64 (setup-test.ps1
#      removes it; without it "no CrashReportClient ran" proves nothing)
#   2. adds outbound BLOCK rules named PT-Q9-* for both game exes and both CrashReportClient paths of the pair
#   3. turns on the audit subcategory "Filtering Platform Connection" (failures), so every blocked attempt becomes Security event 5157
#   4. runs tools\run-test.ps1 -Scenario crashfw (the guest crashes on purpose; host checks marker, no CrashReportClient process)
#   5. reads event 5157 for the run: any blocked outbound attempt by the pair's exes to a non-loopback address, split into
#      "before the crash" and "from the crash on". Loopback is not filtered by Windows Firewall (the pair talks over it).
#   6. removes the rules, the copied exe, restores the audit setting
# PASS = the runner passed AND no blocked attempt from CrashReportClient at all AND none from the game exes from the crash on.
# Blocked attempts before the crash (game start-up) are listed but do not fail the proof.
param(
    [string]$Root = "C:\PacificTogetherTest",
    [int]$Port = 7821,
    [string]$ResultsDir = "",
    [string]$Game = "C:\Program Files (x86)\Steam\steamapps\common\Pacific Drive",
    [switch]$DryRun,
    [switch]$NoCrc,
    [switch]$Headless = $true
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $ResultsDir) { $ResultsDir = Join-Path $Repo "local\test-results" }
$ExeRel = "PenDriverPro\Binaries\Win64\PenDriverPro-Win64-Shipping.exe"
$CrcRel = "Engine\Binaries\Win64\CrashReportClient.exe"
$copies = "client1", "client2" | ForEach-Object { Join-Path $Root $_ }
foreach ($c in $copies) { if (-not (Test-Path (Join-Path $c "PenDriverPro"))) { throw "no test pair at $Root (missing $c)" } }
if ((Resolve-Path $Game).Path.TrimEnd('\') -eq $Root.TrimEnd('\') -or $Root.StartsWith($Game, "OrdinalIgnoreCase")) { throw "Root must not be the real install." }
$programs = @(); foreach ($c in $copies) { $programs += Join-Path $c $ExeRel; $programs += Join-Path $c $CrcRel }
$crcSource = Join-Path $Game $CrcRel
$crcCopy = Join-Path $copies[1] $CrcRel

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($DryRun) {
    Write-Host "DRY RUN (nothing changes). Admin: $admin"
    if (-not $NoCrc) { Write-Host "would copy $crcSource -> $crcCopy" }
    $programs | ForEach-Object { Write-Host "would add outbound block rule PT-Q9-* for $_" }
    Write-Host "would enable audit 'Filtering Platform Connection' failures and run: tools\run-test.ps1 -Scenario crashfw -Root $Root -Port $Port -ResultsDir $ResultsDir$(if ($Headless) { ' -Headless' })"
    exit 0
}
if (-not $admin) { Write-Host "Run this from an elevated PowerShell (Run as administrator): it adds a firewall rule and reads the Security log."; exit 2 }
if (Get-NetFirewallRule -DisplayName "PT-Q9-*" -ErrorAction SilentlyContinue) { throw "PT-Q9-* firewall rules already exist (a killed earlier run?). Remove them first: Remove-NetFirewallRule -DisplayName 'PT-Q9-*'" }
if (-not $NoCrc -and -not (Test-Path $crcSource)) { throw "no CrashReportClient.exe in the install at $crcSource (use -NoCrc)" }

$auditBefore = (auditpol /get /subcategory:"Filtering Platform Connection" /r | ConvertFrom-Csv).'Inclusion Setting'
$t0 = Get-Date
$passed = $false
try {
    Write-Host "== rules"
    $i = 0
    foreach ($p in $programs) {
        New-NetFirewallRule -DisplayName "PT-Q9-$((++$i))-$(Split-Path $p -Leaf)" -Direction Outbound -Action Block -Program $p -Profile Any | Out-Null
        Write-Host "blocked outbound: $p"
    }
    auditpol /set /subcategory:"Filtering Platform Connection" /failure:enable | Out-Null
    if (-not $NoCrc) { Copy-Item $crcSource $crcCopy -Force; Write-Host "copied CrashReportClient.exe into the guest copy (blocked by rule, refused by the mod)"; $env:PT_Q9 = "1" }

    Write-Host "== crash run"
    $runArgs = @("-File", (Join-Path $PSScriptRoot "run-test.ps1"), "-Scenario", "crashfw", "-Root", $Root, "-Port", $Port, "-ResultsDir", $ResultsDir)
    if ($Headless) { $runArgs += "-Headless" }
    & powershell @runArgs
    $runnerOk = $LASTEXITCODE -eq 0
    $results = Get-ChildItem $ResultsDir -Directory | Where-Object { $_.Name -like "*crashfw" -and $_.CreationTime -ge $t0 } | Sort-Object CreationTime | Select-Object -Last 1
    $crashAt = $null
    if ($results) {
        $crash = Get-ChildItem $results.FullName -Directory -Filter "crash-client-*" | Select-Object -First 1
        if ($crash) { $crashAt = (Get-ChildItem $crash.FullName -File | Sort-Object CreationTime | Select-Object -First 1).CreationTime }
    }
    Write-Host "runner passed: $runnerOk; results: $($results.FullName); guest crash folder created: $crashAt"

    Write-Host "== blocked connections (Security 5157) since $t0"
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 5157; StartTime = $t0 } -ErrorAction SilentlyContinue | ForEach-Object {
        $x = [xml]$_.ToXml(); $d = @{}; $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
        [pscustomobject]@{ Time = $_.TimeCreated; App = $d.Application; Dest = $d.DestAddress; Port = $d.DestPort; Proto = $d.Protocol }
    } | Where-Object { $_.App })
    # app paths come as \device\harddiskvolumeN\...; match by the path below the drive
    $tail = $copies | ForEach-Object { $_.Substring(2).ToLower() }
    $mine = @($events | Where-Object { $a = $_.App.ToLower(); ($tail | Where-Object { $a.Contains($_) }) -and $_.Dest -notin "127.0.0.1", "::1" })
    $crc = @($mine | Where-Object { $_.App -like "*CrashReportClient*" })
    $after = @($mine | Where-Object { $_.App -notlike "*CrashReportClient*" -and $crashAt -and $_.Time -ge $crashAt.AddSeconds(-2) })
    $before = @($mine | Where-Object { $_.App -notlike "*CrashReportClient*" -and $after -notcontains $_ })
    $report = Join-Path $results.FullName "q9-firewall.txt"
    @("Q9 firewall proof $(Get-Date -Format s)", "runner passed: $runnerOk", "CrashReportClient exe in guest copy: $(-not $NoCrc)", "guest crash folder created: $crashAt",
      "blocked non-loopback attempts: CrashReportClient=$($crc.Count) game exes before crash=$($before.Count) game exes from crash on=$($after.Count)", "",
      "-- CrashReportClient"; ($crc | Format-Table -AutoSize | Out-String), "-- game exes, from the crash on"; ($after | Format-Table -AutoSize | Out-String),
      "-- game exes, before the crash (info only)"; ($before | Format-Table -AutoSize | Out-String)) | Set-Content -Encoding utf8 $report
    Get-Content $report | Write-Host
    $audited = (auditpol /get /subcategory:"Filtering Platform Connection" /r | ConvertFrom-Csv).'Inclusion Setting'
    if ($audited -notmatch "Failure") { Write-Host "WARNING: failure auditing is not on ($audited); an empty event list proves nothing." }
    $passed = $runnerOk -and $crc.Count -eq 0 -and $after.Count -eq 0 -and $audited -match "Failure"
} finally {
    Write-Host "== cleanup"
    Remove-NetFirewallRule -DisplayName "PT-Q9-*" -ErrorAction SilentlyContinue
    Remove-Item $crcCopy -Force -ErrorAction SilentlyContinue
    Remove-Item Env:PT_Q9 -ErrorAction SilentlyContinue
    if ($auditBefore -notmatch "Failure") { auditpol /set /subcategory:"Filtering Platform Connection" /failure:disable | Out-Null }
    Write-Host "rules removed: $(-not (Get-NetFirewallRule -DisplayName 'PT-Q9-*' -ErrorAction SilentlyContinue)); guest copy has no CrashReportClient.exe: $(-not (Test-Path $crcCopy))"
}
Write-Host "Q9 PROOF: $(if ($passed) { 'PASS' } else { 'FAIL' })"
if ($passed) { exit 0 } else { exit 1 }
