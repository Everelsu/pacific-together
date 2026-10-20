# Small window: game folder + host IP, then installs/updates the mod (install.ps1) and starts the game through Steam.
Add-Type -AssemblyName System.Windows.Forms
$ErrorActionPreference = "Stop"
$settings = Join-Path $env:APPDATA "PacificTogether\launcher.txt"  # line 1 game folder, line 2 host IP
$saved = @(Get-Content $settings -ErrorAction SilentlyContinue) + @("", "")

$form = New-Object Windows.Forms.Form -Property @{ Text = "Pacific Together"; Width = 460; Height = 210; FormBorderStyle = "FixedDialog"; MaximizeBox = $false; StartPosition = "CenterScreen" }
function Add($ctl, $x, $y, $w, $text) { $ctl.Left = $x; $ctl.Top = $y; $ctl.Width = $w; $ctl.Text = $text; $form.Controls.Add($ctl); $ctl }

Add (New-Object Windows.Forms.Label) 12 12 420 "Game folder (the one with PenDriverPro in it)" | Out-Null
$path = Add (New-Object Windows.Forms.TextBox) 12 32 330 $(if ($saved[0]) { $saved[0] } else { & "$PSScriptRoot\install.ps1" -Find })
$browse = Add (New-Object Windows.Forms.Button) 350 30 80 "Browse..."
Add (New-Object Windows.Forms.Label) 12 66 420 "Host IP to join (leave empty if you are the host)" | Out-Null
$ip = Add (New-Object Windows.Forms.TextBox) 12 86 418 $saved[1]
$play = Add (New-Object Windows.Forms.Button) 330 122 100 "Play"
$form.AcceptButton = $play

$browse.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog -Property @{ Description = "Select the Pacific Drive folder"; SelectedPath = $path.Text }
    if ($d.ShowDialog() -eq "OK") { $path.Text = $d.SelectedPath }
})
$play.Add_Click({
    $play.Enabled = $false; $form.UseWaitCursor = $true
    try {
        & "$PSScriptRoot\install.ps1" -GameDir $path.Text.Trim() -Join $ip.Text.Trim() | Out-Null
        New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
        Set-Content $settings @($path.Text.Trim(), $ip.Text.Trim())
        Start-Process "steam://rungameid/1458140"
        $form.Close()
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Pacific Together", "OK", "Error") | Out-Null
    } finally { $play.Enabled = $true; $form.UseWaitCursor = $false }
})
[void]$form.ShowDialog()
