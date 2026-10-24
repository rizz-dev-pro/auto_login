# Logs in to the IIT (ISM) captive portal if the network is not already authenticated.
# Usage: login.ps1 [-Force] [-Notify]
param([switch]$Force, [switch]$Notify)
$ErrorActionPreference = 'Stop'

$Portal    = 'https://netaccess.iitism.ac.in:6082'
$CheckUrl  = 'https://connectivitycheck.gstatic.com/generate_204'
$CredFile  = Join-Path $env:APPDATA 'auto-login\cred.xml'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

function Say([string]$msg) {
    Write-Output $msg
    if ($Notify) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $n = New-Object System.Windows.Forms.NotifyIcon
            $n.Icon = [System.Drawing.SystemIcons]::Information
            $n.Visible = $true
            $n.ShowBalloonTip(4000, 'Auto Login', $msg, 'Info')
            Start-Sleep -Seconds 4
            $n.Dispose()
        } catch { }
    }
}

# No auto-redirect, so we can see where the portal wants us.
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromSeconds(8)

function Get-Resp([string]$url) {
    try { $client.GetAsync($url).GetAwaiter().GetResult() } catch { $null }
}

function Test-Online {
    $r = Get-Resp $CheckUrl
    return ($null -ne $r -and [int]$r.StatusCode -eq 204)
}

if (-not (Test-Path $CredFile)) { Say "Missing credentials: $CredFile (run install.ps1)"; exit 1 }
$cred = Import-Clixml $CredFile
$username = $cred.UserName
$password = $cred.GetNetworkCredential().Password
if (-not $username -or -not $password) { Say "Error: username or password is empty in $CredFile"; exit 1 }

if (-not $Force -and (Test-Online)) {
    if ($Notify) { Say 'Already logged in' }
    exit 0
}

# Ask the portal where it wants us (follow up to 5 redirects by hand); fall back to our own IP.
$formUrl = $null
$url = 'http://neverssl.com'
for ($i = 0; $i -lt 5; $i++) {
    $r = Get-Resp $url
    if ($null -eq $r -or $null -eq $r.Headers.Location -or [int]$r.StatusCode -lt 300 -or [int]$r.StatusCode -ge 400) { break }
    $url = (New-Object Uri((New-Object Uri($url)), $r.Headers.Location)).AbsoluteUri
    if ($url -like "$Portal/*") {
        # Landed on the portal; one more hop gives the actual form URL.
        $formUrl = $url
        $r2 = Get-Resp $url
        if ($null -ne $r2 -and $null -ne $r2.Headers.Location -and [int]$r2.StatusCode -ge 300 -and [int]$r2.StatusCode -lt 400) {
            $formUrl = (New-Object Uri((New-Object Uri($url)), $r2.Headers.Location)).AbsoluteUri
        }
        break
    }
}

if (-not $formUrl) {
    $ip = $null
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
        $ip = (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 | Select-Object -First 1).IPAddress
    } catch { }
    if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        $formUrl = "$Portal/?src=$ip&url=http%3A%2F%2Fneverssl.com%2F"
    } else {
        $formUrl = "$Portal/"
    }
}

# Never send credentials anywhere but the real portal over HTTPS.
if (-not ($formUrl -like "$Portal/*" -or $formUrl -eq $Portal)) {
    Say "Security warning: aborting login, unexpected redirect target: $formUrl"
    exit 1
}

try {
    $body = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $body['username'] = $username
    $body['password'] = $password
    $content = New-Object System.Net.Http.FormUrlEncodedContent($body)
    $null = $client.PostAsync($formUrl, $content).GetAwaiter().GetResult()
} catch {
    Write-Output "POST failed: $($_.Exception.Message)"
}

Start-Sleep -Seconds 2
if (Test-Online) { Say 'Logged in' } else { Say 'Login failed (check credentials / portal)'; exit 2 }
