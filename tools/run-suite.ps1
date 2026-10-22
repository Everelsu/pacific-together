# Full regression, one scenario at a time on one test pair (docs/LANES.md: run once on main after the lanes merge).
# tools\run-suite.ps1 [-Only a,b] [-Root ...] [-Port ...]; writes local\test-results\suite-<stamp>.txt, exit 1 if any failed.
param([string[]]$Only = @(), [string]$Root = "C:\PacificTogetherTest", [int]$Port = 7700)
$Repo = (Resolve-Path "$PSScriptRoot\..").Path
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })  # -File passes "a,b" as one string
# scenario = fixture ("" = none); the fixture each one needs comes from its lane's report
$Suite = [ordered]@{ # most affected by recent merges first, so a cut-short run still covers them
    session = ""; playpath = "zone"; carsync = "garage"; carenter = "garage"; lootsync = "zone"; lootsync2 = "zone"
    guestact = "gateway"; progsync = "zone"; playerhealth = "zone"; backpacksync = "zone"; garagesync = "garage"; guestparts = "gateway"
    guestcraft = "garage"; guestdeath = "zone"; lootcar = "zone"; dropfall = "zone"; carexit = "garage"; arckey = "garage"
    carfeel = "garage"; guestswap = "gateway"; pausemenu = "garage"; runloop = "garage"; worldsync = "gateway"; storysync = "garage"; overlay = "garage"
    anomalies = "zone"; anomalies2 = "zone"; safety = ""; nametag = ""; sessiontravel = "garage"; sessionrejoin = ""
    zonejoin = ""
}
$out = Join-Path $Repo "local\test-results\suite-$(Get-Date -f yyyyMMdd-HHmmss).txt"
$failed = @(); $ran = 0
foreach ($s in $Suite.Keys) {
    if ($Only.Count -and $Only -notcontains $s) { continue }
    $ran++
    $a = @("-Scenario", $s, "-Root", $Root, "-Port", $Port, "-Headless")
    if ($Suite[$s]) { $a += @("-Fixture", $Suite[$s]) }
    $lines = & powershell -NoProfile -File "$Repo\tools\run-test.ps1" @a 2>&1 | Select-String "SUMMARY|results:" | ForEach-Object { $_.Line }
    $ok = $LASTEXITCODE -eq 0
    if (-not $ok) { $failed += $s }
    $line = "{0} {1,-14} {2}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $s, ($lines -join " | ")
    Add-Content -Encoding utf8 $out $line
    $line
}
"suite: $($ran - $failed.Count)/$ran passed; failed: $($failed -join ' ')" | Tee-Object -FilePath $out -Append
if ($failed) { exit 1 }
