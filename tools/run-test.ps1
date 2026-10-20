# Runs one test scenario on the test copies (client1 = host, client2 = client) and judges the PT| lines in UE4SS.log.
# Exit code 0 = every check passed. Results go to local\test-results\<stamp>-<scenario>.
param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [string]$Root = "C:\PacificTogetherTest",
    [ValidateSet(0, 1, 2)][int]$Clients = 0,
    [int]$Seconds = 0,
    [string]$Mutate = "",
    [switch]$KeepOpen,
    [switch]$Headless,
    # parallel lanes must not share a port: a guest would join another lane's host
    [int]$Port = 7777,
    # lanes run from worktrees that get deleted, so they point this at the main repo's local\test-results
    [string]$ResultsDir = ""
)
$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path "$PSScriptRoot\..").Path
$BinRel = "PenDriverPro\Binaries\Win64"
$Defaults = @{ boot = @(2, 150); listen = @(2, 330); dump = @(1, 600); travel = @(2, 1500); zonejoin = @(2, 420); guestsave = @(2, 1200); body = @(2, 420); session = @(2, 1500); sessionmismatch = @(2, 420); sessionsolo = @(1, 600); sessionrejoin = @(2, 900) }
# M2: in these scenarios the shipping mod's guest joins by itself (PT_JOIN), the test mod never runs `open`
$AutoJoin = @("session", "sessionlook", "sessionprobe", "sessionrejoin")
# per-run Engine.ini additions, restored after the run; the mutations in skip run without them
$IniEdits = @{ zonejoin = @{ client = "[/Script/OnlineSubsystemUtils.IpNetDriver]`r`nResolutionConnectionTimeout=120`r`n"; skip = @("noconfig", "cdo") } }
$d = if ($Defaults.ContainsKey($Scenario)) { $Defaults[$Scenario] } else { @(2, 300) }
if (-not $Clients) { $Clients = $d[0] }
if (-not $Seconds) { $Seconds = $d[1] }
$DumpOutputs = "UHTHeaderDump", "CXXHeaderDump", "*.usmap", "Mods\shared\types"

$sides = @(@(
    @{ Role = "host"; Dir = Join-Path $Root "client1" },
    @{ Role = "client"; Dir = Join-Path $Root "client2" }
) | Select-Object -First $Clients)
foreach ($s in $sides) {
    $s.Bin = Join-Path $s.Dir $BinRel
    $s.Log = Join-Path $s.Bin "ue4ss\UE4SS.log"
    $s.Crashes = Join-Path $s.Dir "PenDriverPro\Saved\Crashes"
    $s.Ini = Join-Path $s.Dir "PenDriverPro\Saved\Config\WindowsNoEditor\Engine.ini"
    $s.Snaps = [ordered]@{}
    if (-not (Test-Path "$($s.Bin)\ue4ss\Mods\PacificTogetherTest")) { throw "$($s.Dir) is not set up; run tools\setup-test.ps1" }
}

function Get-TestProcesses($names) {
    Get-Process -Name $names -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith("$Root\", "OrdinalIgnoreCase") }
}
# UE4SS keeps its log open while the game runs
function Read-Shared($path) {
    if (-not (Test-Path $path)) { return "" }
    $r = New-Object IO.StreamReader([IO.File]::Open($path, "Open", "Read", "ReadWrite, Delete"))
    try { $r.ReadToEnd() } finally { $r.Close() }
}

# X10: names, sizes, times and hashes of everything under Saved\SaveGames and Saved\Config
function Get-Snapshot($s) {
    $base = Join-Path $s.Dir "PenDriverPro\Saved"
    foreach ($sub in "SaveGames", "Config") {
        Get-ChildItem (Join-Path $base $sub) -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $h = (Get-FileHash $_.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            "{0}`t{1}`t{2:o}`t{3}" -f $_.FullName.Substring($base.Length + 1), $_.Length, $_.LastWriteTimeUtc, $h
        }
    }
}
# a side prints PT|snap side=<role> tag=<tag>; the runner snapshots that side within one poll (3 s)
function Update-Snapshots {
    foreach ($s in $sides) {
        foreach ($m in [regex]::Matches((Read-Shared $s.Log), "PT\|snap side=$($s.Role) tag=(\S+)")) {
            $tag = $m.Groups[1].Value
            if (-not $s.Snaps.Contains($tag)) { $s.Snaps[$tag] = @(Get-Snapshot $s) }
        }
    }
}

$running = @(Get-TestProcesses "PenDriverPro-Win64-Shipping", "PenDriverPro")
if ($running) {
    Write-Host "A game from $Root is already running (PID $($running.Id -join ', ')). Close it first; this script only stops games it started."
    exit 2
}

# at most $env:PT_SLOTS (default 4) runs at once across all lanes on this machine; a dead runner's mutex is abandoned and reusable
$maxSlots = if ($env:PT_SLOTS) { [int]$env:PT_SLOTS } else { 4 }
$slot = $null
while (-not $slot) {
    foreach ($i in 1..$maxSlots) {
        $m = New-Object Threading.Mutex($false, "Local\PacificTogetherGameSlot$i")
        try { if ($m.WaitOne(0)) { $slot = $m; break } } catch [Threading.AbandonedMutexException] { $slot = $m; break }
        $m.Dispose()
    }
    if (-not $slot) { Write-Host "all $maxSlots game slots busy, waiting"; Start-Sleep 10 }
}

$oldCrashes = @{}
foreach ($s in $sides) {
    Remove-Item $s.Log -ErrorAction SilentlyContinue
    $oldCrashes[$s.Role] = @(Get-ChildItem $s.Crashes -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
    if ($Scenario -eq "dump") { foreach ($o in $DumpOutputs) { Remove-Item "$($s.Bin)\ue4ss\$o" -Recurse -Force -ErrorAction SilentlyContinue } }
}

$edit = $IniEdits[$Scenario]
foreach ($s in $sides) {
    if ($edit -and $edit[$s.Role] -and $edit.skip -notcontains $Mutate) {
        # each copy has its own Saved\Config (not hardlinked), so this only changes this copy
        $s.IniBackup = [IO.File]::ReadAllBytes($s.Ini)
        [IO.File]::AppendAllText($s.Ini, "`r`n" + $edit[$s.Role])
        Write-Host "$($s.Role): appended to $($s.Ini)"
    }
}

$started = Get-Date
$procs = @()
$env:PT_SCENARIO = $Scenario; $env:PT_STATUS = "2000"; $env:PT_HOST = "127.0.0.1:$Port"; $env:PT_MUTATE = $Mutate
try {
    foreach ($s in $sides) {
        if ($procs) { Start-Sleep 8 }
        $env:PT_ROLE = $s.Role
        $env:PT_JOIN = if ($s.Role -eq "client" -and $AutoJoin -contains $Scenario) { "127.0.0.1:$Port" } else { "" }
        $exe = Join-Path $s.Bin "PenDriverPro-Win64-Shipping.exe"
        # -nullrhi: no rendering, ~1 GB RAM and no GPU per instance, so many lanes can test at once; screenshots need a normal run
        $gameArgs = if ($Headless) { "-NotInstalled", "-nullrhi", "-nosound", "-log", "-port=$Port" } else { "-NotInstalled", "-windowed", "-ResX=960", "-ResY=540", "-log", "-port=$Port" }
        $procs += Start-Process $exe -ArgumentList $gameArgs -WorkingDirectory $s.Bin -PassThru
        Write-Host "started $($s.Role) PID $($procs[-1].Id)"
    }
} finally {
    Remove-Item Env:PT_ROLE, Env:PT_SCENARIO, Env:PT_STATUS, Env:PT_HOST, Env:PT_MUTATE, Env:PT_JOIN -ErrorAction SilentlyContinue
}

function Get-NewCrashes {
    foreach ($s in $sides) {
        Get-ChildItem $s.Crashes -Directory -ErrorAction SilentlyContinue | Where-Object { $oldCrashes[$s.Role] -notcontains $_.Name } |
            ForEach-Object { [pscustomobject]@{ Role = $s.Role; Dir = $_ } }
    }
}

$deadline = (Get-Date).AddSeconds($Seconds)
$stop = "timeout after $Seconds s"
while ((Get-Date) -lt $deadline) {
    Start-Sleep 3
    Update-Snapshots
    $done = @($sides | Where-Object { (Read-Shared $_.Log) -match "\[PacificTogetherTest\] PT\|done side=" })
    if ($done.Count -eq $sides.Count) { $stop = "all sides done"; break }
    if (Get-NewCrashes) { $stop = "crash"; break }
    $exited = @($procs | Where-Object HasExited)
    if ($exited) { $stop = "process exited (PID $($exited.Id -join ', '))"; break }
}
$elapsed = [int]((Get-Date) - $deadline.AddSeconds(-$Seconds)).TotalSeconds
Write-Host "stopped waiting: $stop ($elapsed s)"

if (-not $ResultsDir) { $ResultsDir = Join-Path $Repo "local\test-results" }
$lane = if ($Root.TrimEnd('\') -ne "C:\PacificTogetherTest") { "-" + (Split-Path $Root -Leaf) } else { "" }
$results = Join-Path $ResultsDir ("{0}{1}-{2}{3}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $lane, $Scenario, $(if ($Mutate) { "-$Mutate" }))
New-Item -ItemType Directory -Force $results | Out-Null
if (-not $KeepOpen) {
    $procs | Where-Object { -not $_.HasExited } | Stop-Process -Force
    $procs | ForEach-Object { $_.WaitForExit(15000) | Out-Null }
}
Update-Snapshots
foreach ($s in $sides) {
    if ($s.Snaps.Count) { $s.Snaps["end"] = @(Get-Snapshot $s) }
    if ($null -ne $s.IniBackup) { [IO.File]::WriteAllBytes($s.Ini, $s.IniBackup) }
}
# a crashed game opens CrashReportClient a moment later; close it without sending anything
Start-Sleep 3
Get-TestProcesses "CrashReportClient" | Stop-Process -Force

$crashes = @(Get-NewCrashes | ForEach-Object {
    $ctx = Join-Path $_.Dir.FullName "CrashContext.runtime-xml"
    $msg = if (Test-Path $ctx) { ([regex]::Match((Get-Content $ctx -Raw), "<ErrorMessage>([^<]*)")).Groups[1].Value } else { "no CrashContext" }
    Copy-Item $_.Dir.FullName (Join-Path $results "crash-$($_.Role)-$($_.Dir.Name)") -Recurse
    "$($_.Role): $msg"
})

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check($name, $pass, $detail) { $checks.Add([pscustomobject]@{ Name = $name; Pass = [bool]$pass; Detail = $detail }) }
foreach ($s in $sides) {
    $r = $s.Role
    $text = Read-Shared $s.Log
    [IO.File]::WriteAllText((Join-Path $results "$r-UE4SS.log"), $text)
    Copy-Item (Join-Path $s.Dir "PenDriverPro\Saved\Logs\PenDriverPro.log") (Join-Path $results "$r-PenDriverPro.log") -ErrorAction SilentlyContinue
    # X13: HighResShot writes under Saved\Screenshots; copy this run's shots in the order they were taken
    Get-ChildItem (Join-Path $s.Dir "PenDriverPro\Saved\Screenshots") -Recurse -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -ge $started |
        Sort-Object LastWriteTime | ForEach-Object { Copy-Item $_.FullName (Join-Path $results "$r-$($_.Name)") }

    $boot = [regex]::Match($text, "\[PacificTogether\] PT\|boot (.*)")
    Add-Check "$r main mod booted" $boot.Success $boot.Groups[1].Value.Trim()
    $plan = [regex]::Match($text, "\[PacificTogetherTest\] PT\|plan side=$r checks=(\d+)")
    $planned = if ($plan.Success) { [int]$plan.Groups[1].Value } else { -1 }
    Add-Check "$r test plan" $plan.Success "checks=$planned"
    $reported = [regex]::Matches($text, "\[PacificTogetherTest\] PT\|check side=$r name=(\S+) result=(PASS|FAIL) detail=(.*)")
    foreach ($m in $reported) { Add-Check "$r $($m.Groups[1].Value)" ($m.Groups[2].Value -eq "PASS") $m.Groups[3].Value.Trim() }
    if ($planned -ge 0 -and $reported.Count -ne $planned) { Add-Check "$r all planned checks reported" $false "$($reported.Count) of $planned" }
    Add-Check "$r done" ($text -match "\[PacificTogetherTest\] PT\|done side=$r") ""
    $errors = [regex]::Matches($text, "PT\|error .*")
    Add-Check "$r no PT|error" ($errors.Count -eq 0) $(if ($errors.Count) { "$($errors.Count): $($errors[0].Value.Trim())" })
    if ($s.Snaps.Count) {
        $tags = @($s.Snaps.Keys)
        $s.Snaps.GetEnumerator() | ForEach-Object { "## $($_.Key)"; $_.Value } | Set-Content -Encoding utf8 (Join-Path $results "snapshots-$r.txt")
        foreach ($tag in $tags[1..($tags.Count - 1)]) {
            # content = name, size, hash; a rewrite with the same bytes (the game rewrites GameUserSettings.ini on every map load) is listed, not failed
            $content = { param($lines) @($lines | ForEach-Object { $f = $_ -split "`t"; "$($f[0])`t$($f[1])`t$($f[3])" }) }
            $diff = @(Compare-Object (& $content $s.Snaps[$tags[0]]) (& $content $s.Snaps[$tag]) | ForEach-Object { "$($_.SideIndicator)$(($_.InputObject -split "`t")[0])" })
            $touched = @(Compare-Object @($s.Snaps[$tags[0]]) @($s.Snaps[$tag]) | Where-Object SideIndicator -eq "=>" | ForEach-Object { ($_.InputObject -split "`t")[0] })
            Add-Check "$r saves unchanged $($tags[0])->$tag" ($diff.Count -eq 0) (($diff -join " ") + $(if ($touched) { " rewritten: $($touched -join ' ')" }))
        }
    }
}
# X3: host and client actor counts side by side, one csv per survey tag
$actors = foreach ($s in $sides) {
    foreach ($m in [regex]::Matches((Read-Shared $s.Log), "PT\|actors side=(\S+) tag=(\S+) class=(\S+) role=(\S+) rep=(\d) loaded=(\d) owner=(\S+) n=(\d+)")) {
        $g = $m.Groups
        [pscustomobject]@{ Side = $g[1].Value; Tag = $g[2].Value; Class = $g[3].Value; Role = $g[4].Value; Rep = $g[5].Value; Loaded = $g[6].Value; Owner = $g[7].Value; N = [int]$g[8].Value }
    }
}
foreach ($t in @($actors | Group-Object Tag)) {
    $t.Group | Group-Object Class, Role, Rep, Loaded, Owner | ForEach-Object {
        $f = $_.Group[0]
        [pscustomobject]@{ Class = $f.Class; Role = $f.Role; Rep = $f.Rep; Loaded = $f.Loaded; Owner = $f.Owner
            Host = [int]($_.Group | Where-Object Side -eq "host" | Measure-Object N -Sum).Sum
            Client = [int]($_.Group | Where-Object Side -eq "client" | Measure-Object N -Sum).Sum }
    } | Sort-Object Class, Role | Export-Csv -NoTypeInformation (Join-Path $results "actors-$($t.Name).csv")
}
Add-Check "no crash" ($crashes.Count -eq 0) ($crashes -join "; ")

if ($Scenario -eq "dump") {
    $dumps = Join-Path $Repo "local\dumps"
    New-Item -ItemType Directory -Force $dumps | Out-Null
    foreach ($o in $DumpOutputs) {
        $src = @(Get-Item "$($sides[0].Bin)\ue4ss\$o" -ErrorAction SilentlyContinue)
        Add-Check "dump output $o" $src.Count (Join-Path $dumps ($src.Name -join ", "))
        foreach ($i in $src) {
            Remove-Item (Join-Path $dumps $i.Name) -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item $i.FullName (Join-Path $dumps $i.Name) -Recurse
        }
    }
}

$passed = @($checks | Where-Object Pass).Count
$lines = @($checks | ForEach-Object { "{0}  {1}  {2}" -f $(if ($_.Pass) { "PASS" } else { "FAIL" }), $_.Name, $_.Detail })
$lines += "SUMMARY: $passed/$($checks.Count) passed ($Scenario$(if ($Mutate) { ", mutate=$Mutate" }); $stop)"
$lines | Set-Content -Encoding utf8 (Join-Path $results "summary.txt")
$lines | Write-Host
Write-Host "results: $results"
if ($passed -eq $checks.Count) { exit 0 } else { exit 1 }
