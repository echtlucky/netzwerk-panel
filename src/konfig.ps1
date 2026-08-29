# konfig.ps1
# Verwaltet Einstellungen und Zugangsdaten.
#
# Beides liegt bewusst NICHT im Programmordner, sondern unter
#   %APPDATA%\netzpanel\
# Damit kann nichts davon versehentlich in einem Git-Repository landen,
# und eine Neuinstallation ueberschreibt die Einstellungen nicht.

$script:KonfigOrdner = Join-Path $env:APPDATA 'netzpanel'
$script:KonfigDatei  = Join-Path $script:KonfigOrdner 'config.json'
$script:CredDatei    = Join-Path $script:KonfigOrdner 'zugang.xml'

$script:Standard = [ordered]@{
    # Verbindung
    BoxAdresse      = 'fritz.box'
    BoxPort         = 49000
    PanelPort       = 8088

    # Verschluesselte Verbindung zur Box (TR-064 ueber TLS).
    # Der Fingerabdruck wird bei der Einrichtung gemerkt und danach geprueft -
    # so wie SSH es beim ersten Verbinden macht.
    BoxTls          = $true
    BoxTlsPort      = 49443
    BoxFingerabdruck = ''

    # Schwellwerte fuer die Bewertung. Wer andere Massstaebe anlegen
    # moechte, aendert sie in den Einstellungen des Panels.
    StoerabstandGut     = 10      # dB
    StoerabstandKnapp   = 6       # dB
    MeshFunkGut         = 700     # Mbit/s
    MeshFunkKnapp       = 300     # Mbit/s
    SignalGut           = 60      # Prozent
    SignalKnapp         = 40      # Prozent
    LatenzGut           = 1       # ms
    LatenzKnapp         = 4       # ms
    CrcFehlerGrenze     = 10000
    NeusyncGrenze       = 5

    # Anzeige
    Farbschema      = 'automatisch'   # automatisch | hell | dunkel
    StartAnsicht    = 'uebersicht'
}

function Initialize-Konfig {
    if (-not (Test-Path $script:KonfigOrdner)) {
        New-Item -ItemType Directory -Path $script:KonfigOrdner -Force | Out-Null
    }
}

function Get-Konfig {
    Initialize-Konfig
    $k = [ordered]@{}
    foreach ($s in $script:Standard.Keys) { $k[$s] = $script:Standard[$s] }

    if (Test-Path $script:KonfigDatei) {
        try {
            $gespeichert = Get-Content $script:KonfigDatei -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($e in $gespeichert.PSObject.Properties) {
                if ($k.Contains($e.Name)) { $k[$e.Name] = $e.Value }
            }
        } catch {
            Write-Warning "Einstellungen konnten nicht gelesen werden, es gelten die Vorgaben."
        }
    }
    [pscustomobject]$k
}

function Save-Konfig {
    param([Parameter(Mandatory)] $Konfig)
    Initialize-Konfig

    # Nur bekannte Schluessel uebernehmen - fremde Felder werden verworfen.
    $sauber = [ordered]@{}
    foreach ($s in $script:Standard.Keys) {
        $wert = $Konfig.$s
        if ($null -eq $wert) { $wert = $script:Standard[$s] }
        if ($script:Standard[$s] -is [bool]) {
            $wert = [bool]$wert
        }
        elseif ($script:Standard[$s] -is [int]) {
            $zahl = 0
            if ([int]::TryParse([string]$wert, [ref]$zahl)) { $wert = $zahl }
            else { $wert = $script:Standard[$s] }
        }
        $sauber[$s] = $wert
    }
    ([pscustomobject]$sauber) | ConvertTo-Json -Depth 4 |
        Set-Content -Path $script:KonfigDatei -Encoding UTF8
    [pscustomobject]$sauber
}

function Get-KonfigPfad { $script:KonfigDatei }
function Get-CredPfad   { $script:CredDatei }

function Test-ZugangVorhanden { Test-Path $script:CredDatei }

function Get-Zugang {
    if (-not (Test-Path $script:CredDatei)) {
        throw "Keine Zugangsdaten hinterlegt. Zuerst 'netzpanel einrichten' ausführen."
    }
    Import-Clixml -Path $script:CredDatei
}

function Save-Zugang {
    param([Parameter(Mandatory)][System.Management.Automation.PSCredential] $Zugang)
    Initialize-Konfig
    # Export-Clixml verschluesselt das Passwort mit der Windows-Datenschutz-API.
    # Nur dasselbe Windows-Konto auf demselben Rechner kann es wieder lesen.
    $Zugang | Export-Clixml -Path $script:CredDatei
}

function Remove-Zugang {
    if (Test-Path $script:CredDatei) { Remove-Item $script:CredDatei -Force }
}
