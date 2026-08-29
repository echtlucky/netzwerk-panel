# server.ps1
# Der lokale Webserver und die Ansichten.
#
# Lauscht ausschliesslich auf 127.0.0.1. Aus dem Netz ist das Panel nicht
# erreichbar - die Steuerung des Routers bleibt auf diesem Rechner.

# ================================================================ DATENQUELLE
# Jede Datenart steht genau einmal hier: wie sie echt geholt wird, wie die
# Beispielfassung aussieht, und wie lange sie zwischengespeichert werden darf.
# Die Ansichten weiter unten rufen nur noch Hole('name') auf.

$script:Cache = @{}
$script:Cred  = $null
$script:Demo  = $false

function Get-Quellen {
    @{
        box       = @{ Sek=120; Echt={ Get-FritzGeraeteInfo      -Credential $script:Cred }; Demo={ Get-DemoBox } }
        firmware  = @{ Sek=600; Echt={ Get-FritzFirmwareStand    -Credential $script:Cred }; Demo={ Get-DemoFirmware } }
        wan       = @{ Sek=20;  Echt={ Get-FritzWanStatus        -Credential $script:Cred }; Demo={ Get-DemoWan } }
        dsl       = @{ Sek=30;  Echt={ Get-FritzDslInfo          -Credential $script:Cred }; Demo={ Get-DemoDsl } }
        dslfehler = @{ Sek=90;  Echt={ Get-FritzDslFehler        -Credential $script:Cred }; Demo={ Get-DemoDslFehler } }
        lan       = @{ Sek=60;  Echt={ Get-FritzLanStatistik     -Credential $script:Cred }; Demo={ [pscustomobject]@{ Status='Up'; MacAdresse='02:1A:2B:00:00:00'; PaketeGesendet=884213377; PaketeEmpfangen=4127884991 } } }
        wlan      = @{ Sek=25;  Echt={ Get-FritzWlan             -Credential $script:Cred }; Demo={ Get-DemoWlan } }
        funk      = @{ Sek=30;  Echt={ Get-FritzWlanClients      -Credential $script:Cred }; Demo={ Get-DemoFunkClients } }
        gast      = @{ Sek=120; Echt={ Get-FritzGastZugang       -Credential $script:Cred }; Demo={ [pscustomobject]@{ SSID='Heimnetz-Gast'; An=$true; Schluessel='BeispielSchluessel1234'; Schutz='11i' } } }
        hosts     = @{ Sek=8;   Echt={ Get-FritzHosts            -Credential $script:Cred }; Demo={ Get-DemoHosts } }
        mesh      = @{ Sek=20;  Echt={ ConvertTo-MeshUebersicht -Mesh (Get-FritzMesh -Credential $script:Cred) }; Demo={ Get-DemoMeshRoh } }
        sicher    = @{ Sek=120; Echt={ Get-FritzSicherheitslage  -Credential $script:Cred }; Demo={ Get-DemoSicherheitLage } }
        ports     = @{ Sek=120; Echt={ Get-FritzPortfreigaben    -Credential $script:Cred }; Demo={ Get-DemoPortfreigaben } }
        protokoll = @{ Sek=30;  Echt={ Get-FritzProtokoll        -Credential $script:Cred }; Demo={ Get-DemoProtokollEintraege } }
        smart     = @{ Sek=20;  Echt={ Get-FritzSmartHome        -Credential $script:Cred }; Demo={ Get-DemoSmartHomeGeraete } }
        anrufe    = @{ Sek=60;  Echt={ Get-FritzAnrufe           -Credential $script:Cred }; Demo={ Get-DemoAnrufe } }
        dect      = @{ Sek=120; Echt={ Get-FritzDect             -Credential $script:Cred }; Demo={ @([pscustomobject]@{ Name='DECT 1'; Erreichbar=$true; Modell='FRITZ!Fon C6'; Akku='0'; Update=$false }) } }
        zeit      = @{ Sek=600; Echt={ Get-FritzZeit             -Credential $script:Cred }; Demo={ [pscustomobject]@{ NtpServer1='ntp.fritz.box'; NtpServer2='' } } }
        durchsatz = @{ Sek=0;   Echt={ Get-FritzDurchsatz        -Credential $script:Cred }; Demo={ Get-DemoDurchsatz } }
        lokal     = @{ Sek=20;  Echt={ Get-LokaleLage }; Demo={ Get-LokaleLage } }
    }
}

# Holt eine Datenart. Bei Fehlern kommt ein Objekt mit dem Feld 'fehler' zurueck,
# statt eine Ausnahme zu werfen - so faellt nie die ganze Ansicht aus, wenn ein
# einzelner Dienst der Box nicht antwortet.
function Hole {
    param([Parameter(Mandatory)][string] $Name, [switch] $Frisch)

    $q = (Get-Quellen)[$Name]
    if (-not $q) { return [pscustomobject]@{ fehler = "Unbekannte Datenquelle: $Name" } }

    if (-not $Frisch -and $q.Sek -gt 0) {
        $e = $script:Cache[$Name]
        if ($e -and ((Get-Date) - $e.Zeit).TotalSeconds -lt $q.Sek) { return $e.Wert }
    }

    $wert = $null
    try {
        if ($script:Demo) { $wert = & $q.Demo } else { $wert = & $q.Echt }
    } catch {
        $wert = [pscustomobject]@{ fehler = $_.Exception.Message }
    }
    if ($q.Sek -gt 0) { $script:Cache[$Name] = @{ Zeit = (Get-Date); Wert = $wert } }
    $wert
}

function Leere-Cache { param([string[]]$Namen)
    if (-not $Namen) { $script:Cache.Clear(); return }
    foreach ($n in $Namen) { $script:Cache.Remove($n) }
}

function IstFehler { param($o) return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains 'fehler')) }
function OhneFehler { param($o, $Ersatz = @()) if (IstFehler $o) { return $Ersatz } if ($null -eq $o) { return $Ersatz } return $o }

# ------------------------------------------------------- Mesh aufbereiten
function ConvertTo-MeshUebersicht {
    param($Mesh)

    $knoten = @{}
    foreach ($n in $Mesh.nodes) { $knoten[$n.uid] = $n }

    $verbindungen = @()
    $gesehen      = @{}

    foreach ($n in $Mesh.nodes) {
        if (-not $n.is_meshed) { continue }
        foreach ($ni in $n.node_interfaces) {
            foreach ($nl in $ni.node_links) {
                if ($nl.state -ne 'CONNECTED') { continue }
                if ($gesehen[$nl.uid]) { continue }

                $gegenUid = $nl.node_2_uid
                if ($gegenUid -eq $n.uid) { $gegenUid = $nl.node_1_uid }
                $gegen = $knoten[$gegenUid]
                if (-not $gegen) { continue }
                if (-not $gegen.is_meshed) { continue }

                $gesehen[$nl.uid] = $true
                $band = ''
                if ($ni.type -eq 'WLAN') { $band = $ni.name }

                $verbindungen += [pscustomobject]@{
                    Von   = $n.device_name
                    Nach  = $gegen.device_name
                    Art   = $ni.type
                    Band  = $band
                    MaxRx = [math]::Round([double]$nl.max_data_rate_rx / 1000, 0)
                    MaxTx = [math]::Round([double]$nl.max_data_rate_tx / 1000, 0)
                    CurRx = [math]::Round([double]$nl.cur_data_rate_rx / 1000, 0)
                    CurTx = [math]::Round([double]$nl.cur_data_rate_tx / 1000, 0)
                }
            }
        }
    }

    $geraete = @()
    foreach ($n in $Mesh.nodes) {
        if (-not $n.is_meshed) { continue }
        $clients = 0
        foreach ($k in $Mesh.nodes) {
            if ($k.is_meshed) { continue }
            foreach ($ki in $k.node_interfaces) {
                foreach ($kl in $ki.node_links) {
                    if ($kl.state -ne 'CONNECTED') { continue }
                    if ($kl.node_1_uid -eq $n.uid -or $kl.node_2_uid -eq $n.uid) { $clients++ }
                }
            }
        }
        $geraete += [pscustomobject]@{
            Name = $n.device_name; Modell = $n.device_model; Firmware = $n.device_firmware_version
            Rolle = $n.mesh_role;  MAC = $n.device_mac_address; Clients = $clients
        }
    }

    [pscustomobject]@{ Knoten = $geraete; Verbindungen = $verbindungen }
}

# --------------------------------------------------------- Lokale Messung
function Get-LokaleLage {
    $adapter = @()
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $cfg = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
        $ip  = '-'
        if ($cfg -and $cfg.IPv4Address) { $ip = $cfg.IPv4Address[0].IPAddress }
        $adapter += [pscustomobject]@{
            Name = $_.Name; Karte = $_.InterfaceDescription
            LinkSpeed = $_.LinkSpeed; IP = $ip; MAC = $_.MacAddress
        }
    }

    $freigaben = @()
    Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*$' } | ForEach-Object {
        $freigaben += [pscustomobject]@{ Name = $_.Name; Pfad = $_.Path; Verschluesselt = $_.EncryptData }
    }

    $sitzungen = @()
    try {
        Get-SmbSession -ErrorAction SilentlyContinue | ForEach-Object {
            $sitzungen += [pscustomobject]@{ Benutzer = $_.ClientUserName; Rechner = $_.ClientComputerName }
        }
    } catch { }

    $firewall = @()
    Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
        $firewall += [pscustomobject]@{ Profil = $_.Name; An = [bool]$_.Enabled }
    }

    $smb = $null
    try {
        $c = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
        $smb = [pscustomobject]@{ Smb1 = [bool]$c.EnableSMB1Protocol; Signatur = [bool]$c.RequireSecuritySignature }
    } catch { }

    [pscustomobject]@{
        Rechner = $env:COMPUTERNAME; Adapter = $adapter; Freigaben = $freigaben
        Sitzungen = $sitzungen; Firewall = $firewall; Smb = $smb
    }
}

function Measure-Latenz {
    param([string[]]$Ziele)
    $erg = @()
    foreach ($z in $Ziele) {
        $ms = $null
        try {
            $p = New-Object System.Net.NetworkInformation.Ping
            $a = $p.Send($z, 900)
            if ($a.Status -eq 'Success') { $ms = [int]$a.RoundtripTime }
        } catch { }
        $erg += [pscustomobject]@{ Ziel = $z; Ms = $ms }
    }
    $erg
}

function Send-MagicPacket {
    param([Parameter(Mandatory)][string]$MAC)
    $sauber = ($MAC -replace '[^0-9A-Fa-f]', '')
    if ($sauber.Length -ne 12) { throw "Ungültige MAC-Adresse: $MAC" }
    $bytes = for ($i = 0; $i -lt 12; $i += 2) { [Convert]::ToByte($sauber.Substring($i, 2), 16) }

    $paket = New-Object byte[] 102
    for ($i = 0; $i -lt 6; $i++) { $paket[$i] = 0xFF }
    for ($i = 6; $i -lt 102; $i += 6) { [Array]::Copy($bytes, 0, $paket, $i, 6) }

    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.EnableBroadcast = $true
    $udp.Send($paket, $paket.Length, '255.255.255.255', 9) | Out-Null
    $udp.Close()
}

function Get-MeshLatenz {
    # Im Beispielmodus wird nichts angepingt - sonst wuerde das Panel echte
    # Adressen im Netz des Nutzers ansprechen und auf Zeitueberschreitungen warten.
    if ($script:Demo) { return Get-DemoLatenz }

    $mesh  = Hole 'mesh'
    $hosts = Hole 'hosts'
    $ziele = @()
    if (-not (IstFehler $mesh) -and -not (IstFehler $hosts)) {
        foreach ($k in $mesh.Knoten) {
            foreach ($h in $hosts) {
                if ($h.MAC -and $k.MAC -and $h.MAC.ToUpper() -eq $k.MAC.ToUpper()) { $ziele += $h.IP; break }
            }
        }
    }
    if ($ziele.Count -eq 0) { $ziele = @((Get-FritzHostAdresse)) }

    $e = $script:Cache['latenz']
    if ($e -and ((Get-Date) - $e.Zeit).TotalSeconds -lt 12) { return $e.Wert }
    $w = Measure-Latenz -Ziele $ziele
    $script:Cache['latenz'] = @{ Zeit = (Get-Date); Wert = $w }
    $w
}

# ================================================================ BEWERTUNG

function Get-Warnungen {
    param($Konfig)

    $w = @()
    $melde = {
        param($stufe, $titel, $text, $ansicht)
        $script:sammler += [pscustomobject]@{ Stufe=$stufe; Titel=$titel; Text=$text; Ansicht=$ansicht }
    }
    $script:sammler = @()

    $fw     = Hole 'firmware'
    $sicher = Hole 'sicher'
    $dsl    = Hole 'dsl'
    $dslf   = Hole 'dslfehler'
    $mesh   = Hole 'mesh'
    $hosts  = Hole 'hosts'
    $funk   = Hole 'funk'
    $lat    = Get-MeshLatenz

    if (-not (IstFehler $fw) -and $fw.UpdateVerfuegbar) {
        & $melde 'warn' 'Firmware-Update verfügbar' "Für die Box steht Version $($fw.NeueVersion) bereit." 'sicherheit'
    }
    if (-not (IstFehler $sicher)) {
        if ($sicher.Upnp -and $sicher.Upnp.An) {
            & $melde 'kritisch' 'Selbstständige Portfreigaben aktiv' 'Jede Anwendung im Haus darf sich eigenmächtig einen Port ins Internet öffnen — ohne Rückfrage.' 'sicherheit'
        }
        if ($sicher.Fernzugriff -and $sicher.Fernzugriff.An) {
            & $melde 'warn' 'Fernzugriff aus dem Internet aktiv' "Die Box ist über Port $($sicher.Fernzugriff.Port) von außen erreichbar." 'sicherheit'
        }
    }
    if (-not (IstFehler $dsl)) {
        if ($dsl.DownStoerabstand -lt $Konfig.StoerabstandKnapp) {
            & $melde 'kritisch' 'Störabstand zu gering' "$($dsl.DownStoerabstand) dB im Empfang. Unter $($Konfig.StoerabstandKnapp) dB wird die Leitung instabil." 'leitung'
        } elseif ($dsl.DownStoerabstand -lt $Konfig.StoerabstandGut) {
            & $melde 'warn' 'Störabstand knapp' "$($dsl.DownStoerabstand) dB im Empfang — wenig Reserve gegen Störungen." 'leitung'
        }
    }
    if (-not (IstFehler $dslf)) {
        if ($dslf.Neusynchronisierungen -gt $Konfig.NeusyncGrenze) {
            & $melde 'warn' 'Leitung synchronisiert häufig neu' "$($dslf.Neusynchronisierungen) Neusynchronisierungen — jede davon trennt kurz alles." 'leitung'
        }
        if ($dslf.CrcFehler -gt $Konfig.CrcFehlerGrenze) {
            & $melde 'warn' 'Viele Übertragungsfehler' "$($dslf.CrcFehler) nicht korrigierbare Fehler seit dem letzten Synchronisieren." 'leitung'
        }
    }
    if (-not (IstFehler $mesh)) {
        foreach ($v in $mesh.Verbindungen) {
            $max = [Math]::Max($v.MaxRx, $v.MaxTx)
            if ($v.Art -eq 'WLAN' -and $max -lt $Konfig.MeshFunkKnapp -and $max -gt 0) {
                & $melde 'warn' "Schwache Mesh-Strecke: $($v.Nach)" "Nur $max Mbit/s per Funk. Jedes Datenpaket geht zweimal durch die Luft." 'mesh'
            }
        }
    }
    if (-not (IstFehler $funk)) {
        foreach ($c in $funk) {
            if ($c.Signal -gt 0 -and $c.Signal -lt $Konfig.SignalKnapp) {
                & $melde 'info' 'Schwaches Funksignal' "$($c.IP) hat nur $($c.Signal) % Signal im $($c.Band)-Netz." 'funk'
            }
        }
    }
    foreach ($l in $lat) {
        if ($null -eq $l.Ms) { & $melde 'warn' 'Knoten antwortet nicht' "$($l.Ziel) ist nicht erreichbar." 'mesh' }
        elseif ($l.Ms -gt ($Konfig.LatenzKnapp * 2)) { & $melde 'warn' 'Knoten antwortet träge' "$($l.Ziel) braucht $($l.Ms) ms." 'mesh' }
    }
    if (-not (IstFehler $hosts)) {
        foreach ($g in $hosts) {
            if ($g.Aktiv -and $g.UpdateVerf) {
                & $melde 'info' 'Gerät mit offenem Update' "$($g.Name) meldet ein verfügbares Update." 'geraete'
            }
        }
    }

    $script:sammler
}

# ================================================================ ANSICHTEN

function Get-AnsichtUebersicht {
    param($Konfig)
    $hosts = Hole 'hosts'
    $zaehler = $null
    if (-not (IstFehler $hosts)) {
        $zaehler = [pscustomobject]@{
            Gesamt   = @($hosts).Count
            Online   = @($hosts | Where-Object { $_.Aktiv }).Count
            Kabel    = @($hosts | Where-Object { $_.Aktiv -and $_.Art -eq 'Ethernet' }).Count
            Funk     = @($hosts | Where-Object { $_.Aktiv -and $_.Art -eq '802.11' }).Count
            Gast     = @($hosts | Where-Object { $_.Gast }).Count
            Gesperrt = @($hosts | Where-Object { $_.Gesperrt }).Count
        }
    }
    [pscustomobject]@{
        Zeit      = (Get-Date).ToString('HH:mm:ss')
        Box       = Hole 'box'
        Firmware  = Hole 'firmware'
        Wan       = Hole 'wan'
        Dsl       = Hole 'dsl'
        Durchsatz = Hole 'durchsatz'
        Wlan      = Hole 'wlan'
        Mesh      = Hole 'mesh'
        Zaehler   = $zaehler
        Latenz    = Get-MeshLatenz
        Lokal     = Hole 'lokal'
        Warnungen = Get-Warnungen -Konfig $Konfig
    }
}

function Get-AnsichtOptimierung {
    $funk  = OhneFehler (Hole 'funk')
    $hosts = OhneFehler (Hole 'hosts')
    $mesh  = Hole 'mesh'
    $meshOk = if (IstFehler $mesh) { $null } else { $mesh }

    [pscustomobject]@{
        Zeit        = (Get-Date).ToString('HH:mm:ss')
        Airtime     = Get-AirtimeAnalyse -FunkClients $funk -Geraete $hosts
        Vorschlaege = Get-Optimierungsvorschlaege -FunkClients $funk -Geraete $hosts -Mesh $meshOk
    }
}

function Get-AnsichtSimulator {
    [pscustomobject]@{
        Zeit    = (Get-Date).ToString('HH:mm:ss')
        Funk    = OhneFehler (Hole 'funk')
        Geraete = OhneFehler (Hole 'hosts')
        Netze   = OhneFehler (Hole 'wlan')
        Basis   = Get-AirtimeAnalyse -FunkClients (OhneFehler (Hole 'funk')) -Geraete (OhneFehler (Hole 'hosts'))
    }
}

function Get-AnsichtMobil {
    [pscustomobject]@{
        Zeit   = (Get-Date).ToString('HH:mm:ss')
        Analyse = Get-MobilAnalyse -Geraete (OhneFehler (Hole 'hosts')) `
                                   -FunkClients (OhneFehler (Hole 'funk')) `
                                   -Netze (OhneFehler (Hole 'wlan'))
    }
}

function Get-AnsichtHardware {
    $mesh = Hole 'mesh'
    $meshOk = if (IstFehler $mesh) { [pscustomobject]@{ Knoten=@(); Verbindungen=@() } } else { $mesh }
    $lokal = Hole 'lokal'
    $adapter = if (IstFehler $lokal) { @() } else { $lokal.Adapter }

    [pscustomobject]@{
        Zeit      = (Get-Date).ToString('HH:mm:ss')
        Beratung  = Get-HardwareEmpfehlungen -Mesh $meshOk `
                        -FunkClients (OhneFehler (Hole 'funk')) `
                        -Geraete (OhneFehler (Hole 'hosts')) `
                        -Wan (Hole 'wan') -LokaleAdapter $adapter -Netze (OhneFehler (Hole 'wlan'))
    }
}

function Get-AnsichtGeraete {
    [pscustomobject]@{
        Zeit    = (Get-Date).ToString('HH:mm:ss')
        Geraete = Hole 'hosts'
        Funk    = Hole 'funk'
    }
}

function Get-AnsichtMesh {
    [pscustomobject]@{
        Zeit    = (Get-Date).ToString('HH:mm:ss')
        Mesh    = Hole 'mesh'
        Geraete = Hole 'hosts'
        Latenz  = Get-MeshLatenz
    }
}

function Get-AnsichtLeitung {
    [pscustomobject]@{
        Zeit      = (Get-Date).ToString('HH:mm:ss')
        Dsl       = Hole 'dsl'
        Fehler    = Hole 'dslfehler'
        Wan       = Hole 'wan'
        Durchsatz = Hole 'durchsatz'
        Lan       = Hole 'lan'
    }
}

function Get-AnsichtFunk {
    [pscustomobject]@{
        Zeit    = (Get-Date).ToString('HH:mm:ss')
        Netze   = Hole 'wlan'
        Clients = Hole 'funk'
        Gast    = Hole 'gast'
    }
}

function Get-AnsichtSicherheit {
    [pscustomobject]@{
        Zeit       = (Get-Date).ToString('HH:mm:ss')
        Lage       = Hole 'sicher'
        Freigaben  = Hole 'ports'
        Firmware   = Hole 'firmware'
        Zeitserver = Hole 'zeit'
        Lokal      = Hole 'lokal'
    }
}

function Get-AnsichtSmartHome { [pscustomobject]@{ Zeit=(Get-Date).ToString('HH:mm:ss'); Geraete = Hole 'smart' } }
function Get-AnsichtProtokoll { [pscustomobject]@{ Zeit=(Get-Date).ToString('HH:mm:ss'); Eintraege = Hole 'protokoll' } }
function Get-AnsichtTelefonie { [pscustomobject]@{ Zeit=(Get-Date).ToString('HH:mm:ss'); Anrufe = Hole 'anrufe'; Dect = Hole 'dect' } }
function Get-AnsichtPc        { [pscustomobject]@{ Zeit=(Get-Date).ToString('HH:mm:ss'); Lokal = Hole 'lokal' } }

# ============================================================= HTTP-SERVER

function Send-Antwort {
    param($Stream, [int]$Code, [string]$Typ, [byte[]]$Inhalt)
    $texte = @{ 200='OK'; 400='Bad Request'; 404='Not Found'; 500='Internal Server Error' }
    $t = $texte[$Code]; if (-not $t) { $t = 'OK' }
    $kopf = "HTTP/1.1 $Code $t`r`n" +
            "Content-Type: $Typ`r`n" +
            "Content-Length: $($Inhalt.Length)`r`n" +
            "Cache-Control: no-store`r`n" +
            "X-Content-Type-Options: nosniff`r`n" +
            "Referrer-Policy: no-referrer`r`n" +
            "Connection: close`r`n`r`n"
    $kb = [System.Text.Encoding]::ASCII.GetBytes($kopf)
    $Stream.Write($kb, 0, $kb.Length)
    if ($Inhalt.Length -gt 0) { $Stream.Write($Inhalt, 0, $Inhalt.Length) }
    $Stream.Flush()
}

function Send-Json {
    param($Stream, $Objekt, [int]$Code = 200)
    $j = $Objekt | ConvertTo-Json -Depth 12 -Compress
    Send-Antwort -Stream $Stream -Code $Code -Typ 'application/json; charset=utf-8' `
                 -Inhalt ([System.Text.Encoding]::UTF8.GetBytes($j))
}

function Read-Anfrage {
    param($Stream)
    $puffer = New-Object byte[] 8192
    $ms     = New-Object System.IO.MemoryStream
    $ende   = -1

    while ($ende -lt 0) {
        $n = $Stream.Read($puffer, 0, $puffer.Length)
        if ($n -le 0) { break }
        $ms.Write($puffer, 0, $n)
        $txt  = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())
        $ende = $txt.IndexOf("`r`n`r`n")
        if ($ms.Length -gt 262144) { break }
    }
    if ($ende -lt 0) { return $null }

    $alles  = $ms.ToArray()
    $kopfTx = [System.Text.Encoding]::ASCII.GetString($alles, 0, $ende)
    $zeilen = $kopfTx -split "`r`n"
    $teile  = $zeilen[0] -split ' '
    if ($teile.Count -lt 2) { return $null }

    $laenge = 0
    foreach ($z in $zeilen) { if ($z -match '^(?i)Content-Length:\s*(\d+)') { $laenge = [int]$Matches[1] } }

    $body = ''
    if ($laenge -gt 0) {
        $start = $ende + 4
        $da    = $alles.Length - $start
        $bms   = New-Object System.IO.MemoryStream
        if ($da -gt 0) { $bms.Write($alles, $start, [Math]::Min($da, $laenge)) }
        while ($bms.Length -lt $laenge) {
            $n = $Stream.Read($puffer, 0, [Math]::Min($puffer.Length, $laenge - $bms.Length))
            if ($n -le 0) { break }
            $bms.Write($puffer, 0, $n)
        }
        $body = [System.Text.Encoding]::UTF8.GetString($bms.ToArray())
    }

    [pscustomobject]@{ Methode = $teile[0]; Pfad = $teile[1]; Body = $body }
}

function Start-Panel {
    param(
        [int] $Port,
        [switch] $Demo,
        [switch] $KeinBrowser
    )

    $script:Demo = [bool]$Demo
    $konfig = Get-Konfig
    if (-not $Port) { $Port = $konfig.PanelPort }
    Set-FritzVerbindung -Adresse $konfig.BoxAdresse -Port $konfig.BoxPort

    if (-not $script:Demo) {
        try { $script:Cred = Get-Zugang }
        catch {
            Write-Host ""
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Einrichten:              netzpanel einrichten" -ForegroundColor Yellow
            Write-Host "  Oberfläche ansehen:      netzpanel demo" -ForegroundColor Yellow
            Write-Host ""
            return
        }
    }

    $wwwPfad = Join-Path (Split-Path $PSScriptRoot -Parent) 'www'

    $lauscher = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    try { $lauscher.Start() }
    catch {
        Write-Host ""
        Write-Host "  Port $Port ist belegt. Anderen Port wählen:" -ForegroundColor Red
        Write-Host "    netzpanel start -Port 8089" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $adresse = "http://127.0.0.1:$Port"
    Write-Host ""
    Write-Host "  Netzwerk-Panel läuft" -ForegroundColor Green
    Write-Host "  $adresse" -ForegroundColor Cyan
    if ($script:Demo) { Write-Host "  BEISPIELMODUS — keine echten Daten, nichts wird geschaltet" -ForegroundColor Yellow }
    else { Write-Host "  verbunden mit $($konfig.BoxAdresse)" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  Beenden mit Strg+C" -ForegroundColor DarkGray
    Write-Host ""

    if (-not $KeinBrowser) { Start-Process $adresse }

    try {
        while ($true) {
            $klient = $lauscher.AcceptTcpClient()
            $strom  = $null
            try {
                $klient.ReceiveTimeout = 5000
                $klient.SendTimeout    = 30000
                $strom = $klient.GetStream()

                $anf = Read-Anfrage -Stream $strom
                if (-not $anf) { continue }
                $pfad = ($anf.Pfad -split '\?')[0]
                $konfig = Get-Konfig

                switch -Regex ($pfad) {

                    '^/$' {
                        $datei = Join-Path $wwwPfad 'index.html'
                        if (Test-Path $datei) {
                            Send-Antwort -Stream $strom -Code 200 -Typ 'text/html; charset=utf-8' `
                                         -Inhalt ([System.IO.File]::ReadAllBytes($datei))
                        } else {
                            Send-Antwort -Stream $strom -Code 404 -Typ 'text/plain; charset=utf-8' `
                                         -Inhalt ([System.Text.Encoding]::UTF8.GetBytes('www/index.html fehlt'))
                        }
                        break
                    }

                    '^/api/uebersicht$'  { Send-Json $strom (Get-AnsichtUebersicht -Konfig $konfig); break }
                    '^/api/optimierung$' { Send-Json $strom (Get-AnsichtOptimierung); break }
                    '^/api/simulator$'   { Send-Json $strom (Get-AnsichtSimulator);   break }
                    '^/api/mobil$'       { Send-Json $strom (Get-AnsichtMobil);       break }
                    '^/api/hardware$'    { Send-Json $strom (Get-AnsichtHardware);    break }
                    '^/api/geraete$'     { Send-Json $strom (Get-AnsichtGeraete);     break }
                    '^/api/mesh$'        { Send-Json $strom (Get-AnsichtMesh);        break }
                    '^/api/leitung$'     { Send-Json $strom (Get-AnsichtLeitung);     break }
                    '^/api/funk$'        { Send-Json $strom (Get-AnsichtFunk);        break }
                    '^/api/sicherheit$'  { Send-Json $strom (Get-AnsichtSicherheit);  break }
                    '^/api/smarthome$'   { Send-Json $strom (Get-AnsichtSmartHome);   break }
                    '^/api/protokoll$'   { Send-Json $strom (Get-AnsichtProtokoll);   break }
                    '^/api/telefonie$'   { Send-Json $strom (Get-AnsichtTelefonie);   break }
                    '^/api/pc$'          { Send-Json $strom (Get-AnsichtPc);          break }

                    '^/api/einstellungen$' {
                        if ($anf.Methode -eq 'POST') {
                            try {
                                $neu = $anf.Body | ConvertFrom-Json
                                $gespeichert = Save-Konfig -Konfig $neu
                                Set-FritzVerbindung -Adresse $gespeichert.BoxAdresse -Port $gespeichert.BoxPort
                                Leere-Cache
                                Send-Json $strom ([pscustomobject]@{ ok = $true; Konfig = $gespeichert })
                            } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        } else {
                            Send-Json $strom ([pscustomobject]@{
                                Konfig      = $konfig
                                Demo        = $script:Demo
                                ZugangDa    = (Test-ZugangVorhanden)
                                KonfigPfad  = (Get-KonfigPfad)
                            })
                        }
                        break
                    }

                    '^/api/simulieren$' {
                        try {
                            $d = $anf.Body | ConvertFrom-Json
                            $erg = Invoke-Simulation -FunkClients (OhneFehler (Hole 'funk')) `
                                                     -Geraete (OhneFehler (Hole 'hosts')) `
                                                     -Szenario $d.szenario -MAC $d.mac -Ziel ([string]$d.ziel)
                            Send-Json $strom $erg
                        } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        break
                    }

                    '^/api/sperre$' {
                        try {
                            if ($script:Demo) { throw 'Beispielmodus — es wird nichts geschaltet.' }
                            $d = $anf.Body | ConvertFrom-Json
                            Set-FritzGeraetSperre -MAC $d.mac -Sperren ([bool]$d.sperren) -Credential $script:Cred
                            Leere-Cache @('hosts')
                            Send-Json $strom ([pscustomobject]@{ ok = $true })
                        } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        break
                    }

                    '^/api/wlan$' {
                        try {
                            if ($script:Demo) { throw 'Beispielmodus — es wird nichts geschaltet.' }
                            $d = $anf.Body | ConvertFrom-Json
                            Set-FritzWlan -Index ([int]$d.index) -An ([bool]$d.an) -Credential $script:Cred
                            Leere-Cache @('wlan','funk')
                            Send-Json $strom ([pscustomobject]@{ ok = $true })
                        } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        break
                    }

                    '^/api/steckdose$' {
                        try {
                            if ($script:Demo) { throw 'Beispielmodus — es wird nichts geschaltet.' }
                            $d = $anf.Body | ConvertFrom-Json
                            Set-FritzSteckdose -AIN $d.ain -An ([bool]$d.an) -Credential $script:Cred
                            Leere-Cache @('smart')
                            Send-Json $strom ([pscustomobject]@{ ok = $true })
                        } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        break
                    }

                    '^/api/wecken$' {
                        try {
                            if ($script:Demo) { throw 'Beispielmodus — es wird nichts gesendet.' }
                            $d = $anf.Body | ConvertFrom-Json
                            try   { Invoke-FritzWakeOnLan -MAC $d.mac -Credential $script:Cred }
                            catch { Send-MagicPacket -MAC $d.mac }
                            Send-Json $strom ([pscustomobject]@{ ok = $true })
                        } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        break
                    }

                    '^/api/neuverbinden$' {
                        try {
                            if ($script:Demo) { throw 'Beispielmodus — es wird nichts geschaltet.' }
                            Invoke-FritzNeuverbinden -Credential $script:Cred
                            Leere-Cache
                            Send-Json $strom ([pscustomobject]@{ ok = $true })
                        } catch { Send-Json $strom ([pscustomobject]@{ fehler = $_.Exception.Message }) 400 }
                        break
                    }

                    '^/api/leeren$' { Leere-Cache; Send-Json $strom ([pscustomobject]@{ ok = $true }); break }

                    default {
                        Send-Antwort -Stream $strom -Code 404 -Typ 'text/plain; charset=utf-8' `
                                     -Inhalt ([System.Text.Encoding]::UTF8.GetBytes('nicht gefunden'))
                    }
                }
            }
            catch {
                Write-Host "  Anfrage fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
            finally {
                if ($strom)  { $strom.Close() }
                if ($klient) { $klient.Close() }
            }
        }
    }
    finally {
        $lauscher.Stop()
        Write-Host "`n  Panel beendet.`n" -ForegroundColor DarkGray
    }
}
