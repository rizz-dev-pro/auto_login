# Installs the auto-login: credentials, scheduled task (at logon + every 2 min), Ctrl+Alt+L hotkey.
# Run:  powershell -ExecutionPolicy Bypass -File install.ps1        (add -Uninstall to remove)
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$Dir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Login    = Join-Path $Dir 'login.ps1'
$ConfDir  = Join-Path $env:APPDATA 'auto-login'
$CredFile = Join-Path $ConfDir 'cred.xml'
$Vbs      = Join-Path $ConfDir 'run.vbs'
$TaskName = 'AutoLogin'
$Lnk      = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Auto Login.lnk'

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $Lnk, $Vbs -Force -ErrorAction SilentlyContinue
    Write-Host "Removed task and hotkey. Credentials remain in $CredFile (delete manually if desired)."
    exit 0
}

New-Item -ItemType Directory -Force -Path $ConfDir | Out-Null

if (-not (Test-Path $CredFile)) {
    $u = Read-Host 'Username'
    $p = Read-Host 'Password' -AsSecureString
    # Encrypted with DPAPI: only your Windows account on this PC can decrypt it.
    New-Object System.Management.Automation.PSCredential($u, $p) | Export-Clixml $CredFile
}

# Hidden launcher so a console window doesn't flash every 2 minutes.
@'
Set sh = CreateObject("WScript.Shell")
a = ""
For Each x In WScript.Arguments
  a = a & " " & x
Next
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""__LOGIN__""" & a, 0, True
'@ -replace '__LOGIN__', $Login | Set-Content -Path $Vbs -Encoding ASCII

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B `"$Vbs`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2)).Repetition
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Campus network auto login' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

# Hotkey: Windows supports these on Start Menu shortcuts.
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk)
$sc.TargetPath = 'wscript.exe'
$sc.Arguments = "//B `"$Vbs`" -Force -Notify"
$sc.Hotkey = 'CTRL+ALT+L'
$sc.Save()

Write-Host 'Installed. Task runs at logon and every 2 minutes; hotkey Ctrl+Alt+L.'
