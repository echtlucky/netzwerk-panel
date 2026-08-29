# install.ps1
# Installiert das Netzwerk-Panel nach %LOCALAPPDATA%\netzpanel.
#
# Aufruf in PowerShell:
#   iwr -useb https://raw.githubusercontent.com/BENUTZER/netzwerk-panel/main/install.ps1 | iex
#
# Es werden keine Administratorrechte gebraucht und nichts an Windows verändert.
# Deinstallieren heißt: den Ordner löschen.

param(
    [string] $Repo   = 'BENUTZER/netzwerk-panel',
    [string] $Zweig  = 'main',
    [string] $Ziel   = (Join-Path $env:LOCALAPPDATA 'netzpanel')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Schritt($t) { Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)      { Write-Host "  $t" -ForegroundColor Green }
function Info($t)    { Write-Host "  $t" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  Netzwerk-Panel" -ForegroundColor Cyan
Write-Host "  Lokale Verwaltung für FRITZ!Box-Heimnetze" -ForegroundColor DarkGray
Write-Host ""

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw "PowerShell 5.1 oder neuer wird benötigt. Gefunden: $($PSVersionTable.PSVersion)"
}

$zip  = Join-Path $env:TEMP "netzpanel-$Zweig.zip"
$temp = Join-Path $env:TEMP "netzpanel-entpackt"
$url  = "https://github.com/$Repo/archive/refs/heads/$Zweig.zip"

Schritt "Lade herunter von github.com/$Repo ..."
try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
catch { throw "Download fehlgeschlagen: $($_.Exception.Message)" }

Schritt "Entpacke ..."
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $temp -Force

$quelle = Get-ChildItem $temp -Directory | Select-Object -First 1
if (-not $quelle) { throw "Das Archiv enthält keinen Programmordner." }

# Einstellungen und Zugangsdaten liegen unter %APPDATA% und bleiben unberührt.
if (Test-Path $Ziel) {
    Info "Vorhandene Fassung wird ersetzt (Einstellungen bleiben erhalten)"
    Remove-Item $Ziel -Recurse -Force
}
New-Item -ItemType Directory -Path $Ziel -Force | Out-Null
Copy-Item -Path (Join-Path $quelle.FullName '*') -Destination $Ziel -Recurse -Force

Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue

Ok "Installiert nach $Ziel"

# Startbefehl bequem verfügbar machen, ohne die Ausführungsrichtlinie zu ändern
$starter = Join-Path $Ziel 'netzpanel.cmd'
@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0netzpanel.ps1" %*
"@ | Set-Content -Path $starter -Encoding ASCII

Write-Host ""
Write-Host "  So geht es weiter" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. In der FRITZ!Box freigeben:"
Write-Host "     Heimnetz -> Netzwerk -> Netzwerkeinstellungen"
Write-Host "     Haken bei 'Zugriff für Anwendungen zulassen'"
Write-Host ""
Write-Host "  2. Eigenen Benutzer anlegen:"
Write-Host "     System -> FRITZ!Box-Benutzer, Berechtigung 'FRITZ!Box Einstellungen'"
Write-Host ""
Write-Host "  3. Einrichten und starten:"
Write-Host "     & '$starter' einrichten" -ForegroundColor Cyan
Write-Host "     & '$starter' start" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ohne Einrichtung ansehen:"
Write-Host "     & '$starter' demo" -ForegroundColor Cyan
Write-Host ""
