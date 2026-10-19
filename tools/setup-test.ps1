# Makes two isolated test copies of the game with UE4SS and our mods, never touching the real install.
# client1 = full copy, client2 = hardlinks to client1 except its own PenDriverPro/Binaries/Win64 (own UE4SS, logs, mods).
param(
    [string]$Root = "C:\PacificTogetherTest",
    [string]$Game = "C:\Program Files (x86)\Steam\steamapps\common\Pacific Drive",
    [string]$UE4SSZip = "$PSScriptRoot\..\local\cache\ue4ss\zDEV-UE4SS_v3.0.1-1181-g83330635.zip"
)
$ErrorActionPreference = "Stop"
$ExeRel = "PenDriverPro\Binaries\Win64\PenDriverPro-Win64-Shipping.exe"
$BinRel = "PenDriverPro\Binaries\Win64"
$PinnedExe = "568BB63476C6DE5FC2B1878572A655DD631DD25BB44FE304E3D96A51F6B98F7E"
$PinnedUE4SS = @{
    "zDEV-UE4SS_v3.0.1-1181-g83330635.zip" = "82378CD7F679D055026286F11347355AC67C712F21EB892060C902BB0184B907"
    "UE4SS_v3.0.1-1181-g83330635.zip"      = "B9A166A756605B21058A64CDE93BCAAB1A855DBA3553E5C7E6CE0FA8FDFAD7B9"
}
$Repo = (Resolve-Path "$PSScriptRoot\..").Path

if ((Get-FileHash "$Game\$ExeRel").Hash -ne $PinnedExe) { throw "Game exe hash differs from the pinned build; stop (see CLAUDE.md)." }
$zipName = Split-Path $UE4SSZip -Leaf
if ((Get-FileHash $UE4SSZip).Hash -ne $PinnedUE4SS[$zipName]) { throw "UE4SS zip hash mismatch: $UE4SSZip" }
if ((Resolve-Path $Game).Path.TrimEnd('\') -eq $Root.TrimEnd('\')) { throw "Root must not be the real install." }

$c1 = Join-Path $Root "client1"; $c2 = Join-Path $Root "client2"

Write-Host "client1: copying the game (first run takes a while, later runs only copy changes)"
robocopy $Game $c1 /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
if ((Get-FileHash "$c1\$ExeRel").Hash -ne $PinnedExe) { throw "client1 exe hash mismatch after copy" }

Write-Host "client2: hardlinking game data, copying Binaries"
Get-ChildItem $c1 -Recurse -File | Where-Object { $_.FullName -notlike "$c1\$BinRel\*" } | ForEach-Object {
    $target = $c2 + $_.FullName.Substring($c1.Length)
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        New-Item -ItemType HardLink -Path $target -Target $_.FullName | Out-Null
    }
}
robocopy "$Game\$BinRel" "$c2\$BinRel" /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy Binaries failed with $LASTEXITCODE" }

foreach ($c in $c1, $c2) {
    $bin = Join-Path $c $BinRel
    # without it the copy restarts through Steam into the real install
    Set-Content -Path "$bin\steam_appid.txt" -Value "1458140" -Encoding ascii -NoNewline
    if (-not (Test-Path "$bin\ue4ss\UE4SS.dll")) { Expand-Archive -Path $UE4SSZip -DestinationPath $bin -Force }
    # junctions, so edits in the repo apply on the next game launch
    foreach ($m in @(@{n = "PacificTogether"; s = "$Repo\mod\PacificTogether"}, @{n = "PacificTogetherTest"; s = "$Repo\test\PacificTogetherTest"})) {
        $link = "$bin\ue4ss\Mods\$($m.n)"
        if ((Test-Path $m.s) -and -not (Test-Path $link)) { New-Item -ItemType Junction -Path $link -Target $m.s | Out-Null }
    }
}
Write-Host "Done: $c1, $c2"
exit 0  # robocopy leaves $LASTEXITCODE at 1 ("files copied")
