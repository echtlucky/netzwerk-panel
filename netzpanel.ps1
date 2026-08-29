# netzpanel.ps1
# Einstiegspunkt. Alles laeuft ueber dieses Skript.
#
#   .\netzpanel.ps1 einrichten      Zugangsdaten der FRITZ!Box hinterlegen
#   .\netzpanel.ps1 start           Panel starten
#   .\netzpanel.ps1 demo            Panel mit Beispieldaten ansehen
#   .\netzpanel.ps1 status          Verbindung und Einstellungen pruefen
#   .\netzpanel.ps1 zuruecksetzen   Zugangsdaten und Einstellungen loeschen

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'demo', 'einrichten', 'status', 'zuruecksetzen', 'hilfe')]
    [string] $Befehl = 'start',

    [int]    $Port,
    [switch] $KeinBrowser
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src\konfig.ps1')
. (Join-Path $PSScriptRoot 'src\tr064.ps1')
. (Join-Path $PSScriptRoot 'src\analyse.ps1')
. (Join-Path $PSScriptRoot 'src\hardware.ps1')
. (Join-Path $PSScriptRoot 'src\lokal.ps1')
. (Join-Path $PSScriptRoot 'src\demo.ps1')
. (Join-Path $PSScriptRoot 'src\server.ps1')

function Show-Kopf {
    Write-Host ""
    Write-Host "  Netzwerk-Panel" -ForegroundColor Cyan
    Write-Host "  Lokale Verwaltung für FRITZ!Box-Heimnetze" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Hilfe {
    Show-Kopf
    Write-Host "  Befehle" -ForegroundColor Yellow
    Write-Host "    einrichten      Zugangsdaten der FRITZ!Box hinterlegen"
    Write-Host "    start           Panel starten und im Browser öffnen"
    Write-Host "    demo            Oberfläche mit Beispieldaten ansehen"
    Write-Host "    status          Verbindung und Einstellungen prüfen"
    Write-Host "    zuruecksetzen   Zugangsdaten und Einstellungen löschen"
    Write-Host ""
    Write-Host "  Zusätze" -ForegroundColor Yellow
    Write-Host "    -Port 8089      anderen Port verwenden"
    Write-Host "    -KeinBrowser    Browser nicht automatisch öffnen"
    Write-Host ""
    Write-Host "  Voraussetzung in der FRITZ!Box" -ForegroundColor Yellow
    Write-Host "    Heimnetz -> Netzwerk -> Netzwerkeinstellungen"
    Write-Host "    Haken bei 'Zugriff für Anwendungen zulassen'"
    Write-Host ""
}

# ------------------------------------------------------------- einrichten
function Invoke-Einrichten {
    Show-Kopf
    $konfig = Get-Konfig

    Write-Host "  Voraussetzung in der FRITZ!Box:" -ForegroundColor Yellow
    Write-Host "    Heimnetz -> Netzwerk -> Netzwerkeinstellungen"
    Write-Host "    Haken bei 'Zugriff für Anwendungen zulassen'"
    Write-Host ""
    Write-Host "  Verwende einen eigenen FRITZ!Box-Benutzer, nicht das Hauptkonto."
    Write-Host "  Anlegen unter: System -> FRITZ!Box-Benutzer"
    Write-Host "  Benötigte Berechtigung: 'FRITZ!Box Einstellungen'"
    Write-Host ""

    $adresse = Read-Host "  Adresse der FRITZ!Box [$($konfig.BoxAdresse)]"
    if (-not $adresse) { $adresse = $konfig.BoxAdresse }

    if (Test-ZugangVorhanden) {
        Write-Host ""
        Write-Host "  Es sind bereits Zugangsdaten hinterlegt." -ForegroundColor DarkGray
        $a = Read-Host "  Überschreiben? (j/n)"
        if ($a -ne 'j') { Write-Host "  Abgebrochen.`n" -ForegroundColor DarkGray; return }
    }

    Write-Host ""
    $benutzer = Read-Host "  Benutzername"
    Write-Host "  Passwort (wird nicht angezeigt)" -NoNewline
    $pw = Read-Host -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential($benutzer, $pw)

    Set-FritzVerbindung -Adresse $adresse -Port $konfig.BoxPort

    Write-Host ""
    Write-Host "  Verbindung wird geprüft ..." -ForegroundColor DarkGray
    try {
        $info = Get-FritzGeraeteInfo -Credential $cred
        $wan  = Get-FritzWanStatus   -Credential $cred
        $anz  = @(Get-FritzHosts     -Credential $cred).Count

        Write-Host ""
        Write-Host "  Verbindung steht." -ForegroundColor Green
        Write-Host "    Modell     : $($info.Modell)"
        Write-Host "    Firmware   : $($info.Firmware)"
        Write-Host "    Laufzeit   : $([math]::Round($info.LaufzeitSek / 86400, 1)) Tage"
        Write-Host "    Anschluss  : $($wan.Zugangsart), $($wan.DownMbit) / $($wan.UpMbit) Mbit/s"
        Write-Host "    Geräte     : $anz bekannt"

        Save-Zugang -Zugang $cred
        $konfig.BoxAdresse = $adresse
        Save-Konfig -Konfig $konfig | Out-Null

        Write-Host ""
        Write-Host "  Gespeichert unter $(Split-Path (Get-CredPfad) -Parent)" -ForegroundColor Green
        Write-Host "  Das Passwort ist mit der Windows-Datenschutz-API verschlüsselt."
        Write-Host "  Nur dein Windows-Konto auf diesem Rechner kann es wieder lesen."
        Write-Host ""
        Write-Host "  Starten mit:  .\netzpanel.ps1 start" -ForegroundColor Yellow
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "  Fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Häufigste Ursachen:" -ForegroundColor Yellow
        Write-Host "    1. 'Zugriff für Anwendungen zulassen' ist in der Box nicht gesetzt"
        Write-Host "    2. Dem Benutzer fehlt die Berechtigung 'FRITZ!Box Einstellungen'"
        Write-Host "    3. Benutzername oder Passwort stimmen nicht"
        Write-Host "    4. Die Box ist unter '$adresse' nicht erreichbar"
        Write-Host ""
    }
}

# ----------------------------------------------------------------- status
function Invoke-Status {
    Show-Kopf
    $konfig = Get-Konfig

    Write-Host "  Einstellungen" -ForegroundColor Yellow
    Write-Host "    Datei          : $(Get-KonfigPfad)"
    Write-Host "    FRITZ!Box      : $($konfig.BoxAdresse):$($konfig.BoxPort)"
    Write-Host "    Panel-Port     : $($konfig.PanelPort)"
    Write-Host ""

    Write-Host "  Zugangsdaten" -ForegroundColor Yellow
    if (Test-ZugangVorhanden) {
        Write-Host "    hinterlegt     : ja ($(Get-CredPfad))" -ForegroundColor Green
    } else {
        Write-Host "    hinterlegt     : nein — 'netzpanel einrichten' ausführen" -ForegroundColor DarkYellow
        Write-Host ""
        return
    }
    Write-Host ""

    Set-FritzVerbindung -Adresse $konfig.BoxAdresse -Port $konfig.BoxPort
    Write-Host "  Verbindung" -ForegroundColor Yellow
    try {
        $cred = Get-Zugang
        $info = Get-FritzGeraeteInfo -Credential $cred
        Write-Host "    Modell         : $($info.Modell)" -ForegroundColor Green
        Write-Host "    Firmware       : $($info.Firmware)"
        Write-Host "    Laufzeit       : $([math]::Round($info.LaufzeitSek / 86400, 1)) Tage"

        foreach ($p in @(
            @{ n='Geräteliste';       f={ @(Get-FritzHosts       -Credential $cred).Count.ToString() + ' Geräte' } },
            @{ n='Mesh';              f={ @((ConvertTo-MeshUebersicht -Mesh (Get-FritzMesh -Credential $cred)).Knoten).Count.ToString() + ' Knoten' } },
            @{ n='Funk-Clients';      f={ @(Get-FritzWlanClients -Credential $cred).Count.ToString() + ' verbunden' } },
            @{ n='DSL-Werte';         f={ (Get-FritzDslInfo      -Credential $cred).Status } },
            @{ n='Smart Home';        f={ @(Get-FritzSmartHome   -Credential $cred).Count.ToString() + ' Geräte' } },
            @{ n='Anrufliste';        f={ @(Get-FritzAnrufe      -Credential $cred).Count.ToString() + ' Einträge' } },
            @{ n='Ereignisprotokoll'; f={ @(Get-FritzProtokoll   -Credential $cred).Count.ToString() + ' Zeilen' } }
        )) {
            try   { Write-Host ("    {0,-15}: {1}" -f $p.n, (& $p.f)) -ForegroundColor Green }
            catch { Write-Host ("    {0,-15}: {1}" -f $p.n, $_.Exception.Message) -ForegroundColor DarkYellow }
        }
    }
    catch { Write-Host "    Fehlgeschlagen : $($_.Exception.Message)" -ForegroundColor Red }
    Write-Host ""
}

# ---------------------------------------------------------- zuruecksetzen
function Invoke-Zuruecksetzen {
    Show-Kopf
    Write-Host "  Das löscht Zugangsdaten und Einstellungen unter:" -ForegroundColor Yellow
    Write-Host "    $(Split-Path (Get-KonfigPfad) -Parent)"
    Write-Host ""
    $a = Read-Host "  Wirklich löschen? (j/n)"
    if ($a -ne 'j') { Write-Host "  Abgebrochen.`n" -ForegroundColor DarkGray; return }

    Remove-Zugang
    $kp = Get-KonfigPfad
    if (Test-Path $kp) { Remove-Item $kp -Force }
    Write-Host "  Gelöscht.`n" -ForegroundColor Green
}

# ------------------------------------------------------------------ Start
switch ($Befehl) {
    'einrichten'    { Invoke-Einrichten }
    'status'        { Invoke-Status }
    'zuruecksetzen' { Invoke-Zuruecksetzen }
    'hilfe'         { Show-Hilfe }
    'demo'          { Start-Panel -Port $Port -Demo -KeinBrowser:$KeinBrowser }
    default         { Start-Panel -Port $Port -KeinBrowser:$KeinBrowser }
}
