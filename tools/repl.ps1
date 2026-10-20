# Runs Lua in a running test game (test mod's repl.lua) and prints the result. Start a session first, e.g. in the
# background: run-test.ps1 -Scenario repl -Seconds 3600 -Headless. Exit code 0 = ok, 1 = Lua error, 2 = no answer.
#   repl.ps1 -Code "FindFirstOf('BP_PlayerCarNew_C')"            # an expression returns its value
#   repl.ps1 -Side client -File probe.lua                        # a block can call out(...) and return values
#   repl.ps1 -Stop                                               # ends the repl scenario on both sides
param(
    [string]$Root = "C:\PacificTogetherTest",
    [ValidateSet("host", "client")][string]$Side = "host",
    [string]$Code = "",
    [string]$File = "",
    [int]$Timeout = 20,
    [switch]$Stop
)
$ErrorActionPreference = "Stop"
$copies = @{ host = "client1"; client = "client2" }
function Get-Dir($side) { Join-Path $Root "$($copies[$side])\PenDriverPro\Binaries\Win64\ue4ss\pt_repl" }
# Lua chokes on a BOM, which PowerShell 5.1's utf8 writers add
$utf8 = New-Object Text.UTF8Encoding($false)

if ($Stop) {
    foreach ($s in "host", "client") { $d = Get-Dir $s; New-Item -ItemType Directory -Force $d | Out-Null; [IO.File]::WriteAllText("$d\stop", "", $utf8) }
    Write-Host "stop requested"; exit 0
}
if ($File) { $Code = [IO.File]::ReadAllText((Resolve-Path $File)) }
if (-not $Code) { throw "give -Code or -File" }

$dir = Get-Dir $Side
New-Item -ItemType Directory -Force $dir | Out-Null
$id = [guid]::NewGuid().ToString("N").Substring(0, 8)
# write then rename, so the game never reads a half-written file
[IO.File]::WriteAllText("$dir\in.tmp", "-- id=$id`n$Code", $utf8)
Move-Item -Force "$dir\in.tmp" "$dir\in.lua"

$deadline = (Get-Date).AddSeconds($Timeout)
$pattern = "(?s)=== id=$id (ok|err)\r?\n(.*?)\r?\n=== end id=$id"
while ((Get-Date) -lt $deadline) {
    if (Test-Path "$dir\out.txt") {
        $m = [regex]::Match([IO.File]::ReadAllText("$dir\out.txt"), $pattern)
        if ($m.Success) {
            Write-Output $m.Groups[2].Value
            exit $(if ($m.Groups[1].Value -eq "ok") { 0 } else { 1 })
        }
    }
    Start-Sleep -Milliseconds 200
}
Write-Host "no answer within $Timeout s (is a test game running on $Root, past the main menu?)"
if (Test-Path "$dir\in.lua") { Remove-Item "$dir\in.lua" }
exit 2
