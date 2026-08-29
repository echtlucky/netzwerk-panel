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
# Lokal-Modus: keine Zugangsdaten hinterlegt. Das Panel laeuft trotzdem und
# zeigt alles, was der eigene Rechner ohne die Box messen kann.
$script:Lokal = $false

function Get-Quellen {
    @{
        box       = @{ Sek=120; Echt={ Get-FritzGeraeteInfo      -Credential $script:Cred }; Demo={ Get-DemoBox } }
        firmware  = @{ Sek=600; Echt={ Get-FritzFirmwareStand    -Credential $script:Cred }; Demo={ Get-DemoFirmware } }
        wan       = @{ Sek=20;  Echt={ Get-FritzWanStatus        -Credential $script:Cred }; Demo={ Get-DemoWan } }
        dsl       = @{ Sek=30;  Echt={ Get-FritzDslInfo          -Credential $script:Cred }; Demo={ Get-DemoDsl } }
        dslfehler = @{ Sek=90;  Echt={ Get-FritzDslFehler        -Credential $script:Cred }; Demo={ Get-DemoDslFehler } }
        lan       = @{ Sek=60;  Echt={ Get-FritzLanStatistik     -Credential $script:Cred }; Demo={ [pscustomobject]@{ Status='Up'; MacAdresse='02:1A:2B:00:00:00'; PaketeGesendet=884213377; PaketeEmpfangen=4127884991 } } }
        wlan      = @{ Sek=25;  Echt={ Get-FritzWlan             -Credential $script:Cred }; Demo={ Get-DemoWlan } }
        funk      = @{ Sek=30;  Echt={ Get-FritzWlanClients -Mesh (Hole 'meshroh') }; Demo={ Get-DemoFunkClients } }
        gast      = @{ Sek=120; Echt={ Get-FritzGastZugang       -Credential $script:Cred }; Demo={ [pscustomobject]@{ SSID='Heimnetz-Gast'; An=$true; Schluessel='BeispielSchluessel1234'; Schutz='11i' } } }
        hosts     = @{ Sek=8;   Echt={ Get-FritzHosts            -Credential $script:Cred }; Demo={ Get-DemoHosts } }
        # Die rohe Mesh-Liste ist die teuerste Abfrage der Box. Topologie und
        # Funk-Clients bauen beide darauf auf und teilen sich deshalb den Abruf.
        meshroh   = @{ Sek=20;  Echt={ Get-FritzMesh -Credential $script:Cred }; Demo={ $null } }
        mesh      = @{ Sek=20;  Echt={ ConvertTo-MeshUebersicht -Mesh (Hole 'meshroh') }; Demo={ Get-DemoMeshRoh } }
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
    if ($script:Lokal -and $Name -ne 'lokal') {
        # Ohne Zugangsdaten macht ein Aufruf an die Box keinen Sinn.
        $wert = [pscustomobject]@{ fehler = 'Keine Zugangsdaten hinterlegt — dieser Bereich braucht Zugriff auf die FRITZ!Box.' }
    } else {
        try {
            if ($script:Demo) { $wert = & $q.Demo } else { $wert = & $q.Echt }
        } catch {
            $wert = [pscustomobject]@{ fehler = $_.Exception.Message }
        }
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
                    Von      = $n.device_name
                    Nach     = $gegen.device_name
                    # true heisst: ueber diese Strecke erreicht "Von" den Router
                    VonUplink = [bool]$ni.is_upstream
                    Art      = $ni.type
                    Band  = $band
                    MaxRx = [math]::Round([double]$nl.max_data_rate_rx / 1000, 0)
                    MaxTx = [math]::Round([double]$nl.max_data_rate_tx / 1000, 0)
                    CurRx = [math]::Round([double]$nl.cur_data_rate_rx / 1000, 0)
                    CurTx = [math]::Round([double]$nl.cur_data_rate_tx / 1000, 0)
                }
            }
        }
    }

    # Wie viele Funkstrecken liegen zwischen einem Knoten und dem Router?
    # Repeater koennen sich hintereinander schalten - dann geht der Verkehr
    # eines Geraets mehrfach durch die Luft, und jeder Sprung kostet grob die
    # Haelfte des Durchsatzes.
    #
    # Ausgewertet werden die Interface-Namen der Rohdaten: AVM benennt die
    # Richtung zum Router mit "UPLINK:..." und die zu den Geraeten mit "AP:...".
    # Das Feld is_upstream waere naheliegender, ist aber nicht in jeder
    # Firmware gesetzt. Die aufbereitete Verbindungsliste taugt ebenfalls nicht,
    # weil sie jede Strecke nur einmal fuehrt und offenlaesst, aus wessen Sicht.
    $uplinkZiel = @{}
    $uplinkArt  = @{}
    foreach ($n in $Mesh.nodes) {
        if (-not $n.is_meshed) { continue }
        foreach ($ni in $n.node_interfaces) {
            $istUplink = $false
            if ($ni.is_upstream) { $istUplink = $true }
            elseif ($ni.name -match '^(?i)uplink') { $istUplink = $true }
            if (-not $istUplink) { continue }
            foreach ($nl in $ni.node_links) {
                if ($nl.state -ne 'CONNECTED') { continue }
                $gegenUid = $nl.node_2_uid
                if ($gegenUid -eq $n.uid) { $gegenUid = $nl.node_1_uid }
                $gegen = $knoten[$gegenUid]
                if (-not $gegen -or -not $gegen.is_meshed) { continue }
                # Bei mehreren Uplinks zaehlt der erste gefundene
                if (-not $uplinkZiel.ContainsKey($n.device_name)) {
                    $uplinkZiel[$n.device_name] = $gegen.device_name
                    $uplinkArt[$n.device_name]  = $ni.type
                }
            }
        }
    }

    # Vom Knoten aus dem Weg nach oben folgen und die Funkstrecken zaehlen.
    # Wer keinen Uplink meldet, haengt am Kabel oder ist der Router selbst.
    $tiefe = @{}
    foreach ($n in $Mesh.nodes) {
        if (-not $n.is_meshed) { continue }
        $name = $n.device_name
        $zaehler = 0
        $aktuell = $name
        $besucht = @{}
        while ($uplinkZiel.ContainsKey($aktuell) -and -not $besucht[$aktuell]) {
            $besucht[$aktuell] = $true
            if ($uplinkArt[$aktuell] -eq 'WLAN') { $zaehler++ }
            $aktuell = $uplinkZiel[$aktuell]
            if ($besucht.Count -gt 10) { break }
        }
        $tiefe[$name] = $zaehler
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
        $funksprunge = $null
        if ($tiefe.ContainsKey($n.device_name)) { $funksprunge = $tiefe[$n.device_name] }
        # Ueber welchen Knoten laeuft der Weg zum Router?
        $ueber = ''
        if ($funksprunge -gt 0 -and $uplinkZiel.ContainsKey($n.device_name)) {
            $ueber = $uplinkZiel[$n.device_name]
        }

        $geraete += [pscustomobject]@{
            Name = $n.device_name; Modell = $n.device_model; Firmware = $n.device_firmware_version
            Rolle = $n.mesh_role;  MAC = $n.device_mac_address; Clients = $clients
            Funksprunge = $funksprunge; Ueber = $ueber
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
        # Ein Repeater kann ueber mehrere Baender angebunden sein. Gemeldet wird
        # je Knoten nur seine beste Strecke - sonst stuende derselbe Repeater
        # mehrfach in der Liste.
        $besteJeKnoten = @{}
        foreach ($v in $mesh.Verbindungen) {
            if ($v.Art -ne 'WLAN') { continue }
            $max = [Math]::Max($v.MaxRx, $v.MaxTx)
            if ($max -le 0) { continue }
            foreach ($ziel in @($v.Von, $v.Nach)) {
                $istKnoten = $false
                foreach ($k in $mesh.Knoten) { if ($k.Name -eq $ziel -and $k.Rolle -ne 'master') { $istKnoten = $true } }
                if (-not $istKnoten) { continue }
                if (-not $besteJeKnoten.ContainsKey($ziel) -or $besteJeKnoten[$ziel] -lt $max) {
                    $besteJeKnoten[$ziel] = $max
                }
            }
        }
        foreach ($k in $mesh.Knoten) {
            if ($k.Rolle -eq 'master') { continue }
            if ($null -eq $k.Funksprunge) {
                & $melde 'warn' "$($k.Name) hängt nicht am Mesh" "Für diesen Repeater ist keine Verbindung zum Router erkennbar." 'mesh'
            }
            elseif ($k.Funksprunge -ge 2) {
                $ueber = $k.Ueber
                $zusatz = ''
                if ($ueber) { $zusatz = " Der Weg läuft über $ueber." }
                & $melde 'warn' "$($k.Name) hängt in zweiter Reihe" "Zwischen diesem Repeater und dem Router liegen $($k.Funksprunge) Funkstrecken.$zusatz Alles, was hier angeschlossen ist, geht dreimal durch die Luft — jeder Sprung kostet grob die Hälfte der Geschwindigkeit. Ein Netzwerkkabel zum Router oder ein besserer Standort löst das." 'mesh'
            }
        }

        foreach ($ziel in $besteJeKnoten.Keys) {
            $max = $besteJeKnoten[$ziel]
            if ($max -lt $Konfig.MeshFunkKnapp) {
                & $melde 'warn' "Schwache Mesh-Strecke: $ziel" "Beste Funkstrecke zum Router: $max Mbit/s. Alles, was über diesen Repeater läuft, geht zweimal durch die Luft — einmal zum Gerät, einmal zum Router." 'mesh'
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
        Vorschlaege = Get-Optimierungsvorschlaege -FunkClients $funk -Geraete $hosts -Mesh $meshOk -Netze (OhneFehler (Hole 'wlan'))
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

function Get-AnsichtLokalnetz {
    param([switch] $MitScan)
    $scan = $null
    if ($MitScan) {
        # Der Scan dauert einige Sekunden und laeuft nur auf ausdrueckliche
        # Anforderung, nicht bei jedem Aktualisieren.
        try { $scan = Invoke-Netzscan } catch { $scan = [pscustomobject]@{ fehler = $_.Exception.Message } }
        $script:Cache['scan'] = @{ Zeit = (Get-Date); Wert = $scan }
    } else {
        $e = $script:Cache['scan']
        if ($e) { $scan = $e.Wert }
    }

    [pscustomobject]@{
        Zeit      = (Get-Date).ToString('HH:mm:ss')
        Scan      = $scan
        ScanAlter = $(if ($script:Cache['scan']) { [int]((Get-Date) - $script:Cache['scan'].Zeit).TotalSeconds } else { $null })
        Anbindung = Zwischen-Lokal 'anbindung' 30 { Get-EigeneAnbindung }
        Internet  = Zwischen-Lokal 'internetguete' 45 { Measure-Internetguete }
        Weg       = Zwischen-Lokal 'weg' 120 { Get-Wegverfolgung }
        Dienste   = Zwischen-Lokal 'dienste' 60 { Get-OffeneDienste }
    }
}

# Eigener kleiner Zwischenspeicher fuer die lokalen Messungen - sie gehen
# nicht ueber Get-Quellen, weil sie keine Box-Entsprechung haben.
function Zwischen-Lokal {
    param([string]$Schluessel, [int]$Sekunden, [scriptblock]$Abruf)
    $e = $script:Cache["lok_$Schluessel"]
    if ($e -and ((Get-Date) - $e.Zeit).TotalSeconds -lt $Sekunden) { return $e.Wert }
    $w = $null
    try { $w = & $Abruf } catch { $w = [pscustomobject]@{ fehler = $_.Exception.Message } }
    $script:Cache["lok_$Schluessel"] = @{ Zeit = (Get-Date); Wert = $w }
    $w
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

# ========================================================== AENDERUNGEN
#
# Jede Aenderung an der Box laeuft hier durch. Der Rueckgabewert sagt in
# Klartext, was geschehen ist - das Panel zeigt ihn unveraendert an.

function Invoke-Aenderung {
    param([Parameter(Mandatory)][string]$Was, $Daten)

    $c = $script:Cred
    switch ($Was) {

        'upnp' {
            Set-FritzUpnp -An ([bool]$Daten.an) -Credential $c
            Leere-Cache @('sicher')
            $z = if ($Daten.an) { 'eingeschaltet' } else { 'abgeschaltet' }
            return [pscustomobject]@{ ok = $true; text = "Selbstständige Portfreigaben $z." }
        }

        'fernzugriff' {
            Set-FritzFernzugriff -An ([bool]$Daten.an) -Credential $c
            Leere-Cache @('sicher')
            $z = if ($Daten.an) { 'eingeschaltet' } else { 'abgeschaltet' }
            return [pscustomobject]@{ ok = $true; text = "Fernzugriff aus dem Internet $z." }
        }

        'wlanname' {
            Set-FritzWlanName -Index ([int]$Daten.index) -Name ([string]$Daten.wert) -Credential $c
            Leere-Cache @('wlan','gast')
            return [pscustomobject]@{ ok = $true
                text = "Netzname geändert. Geräte, die das alte Netz kennen, müssen sich neu verbinden." }
        }

        'wlanschluessel' {
            Set-FritzWlanSchluessel -Index ([int]$Daten.index) -Schluessel ([string]$Daten.wert) -Credential $c
            Leere-Cache @('gast')
            return [pscustomobject]@{ ok = $true
                text = "Schlüssel geändert. Alle verbundenen Geräte müssen sich mit dem neuen Schlüssel neu anmelden." }
        }

        'wlankanal' {
            $index = [int]$Daten.index
            $ziel  = [int]$Daten.wert
            Set-FritzWlanKanal -Index $index -Kanal $ziel -Credential $c
            Leere-Cache @('wlan','funk')

            if ($ziel -eq 0) {
                return [pscustomobject]@{ ok = $true; text = 'Kanalwahl wieder der Box überlassen.' }
            }

            # Nachsehen, ob die Box den Kanal wirklich uebernommen hat. Ist die
            # automatische Kanalwahl aktiv, nimmt sie den Befehl an und setzt
            # ihn sofort wieder zurueck - ohne einen Fehler zu melden.
            Start-Sleep -Seconds 4
            $jetzt = 0
            try {
                $netze = Get-FritzWlan -Credential $c
                foreach ($n in $netze) { if ($n.Index -eq $index) { $jetzt = [int]$n.Kanal } }
            } catch { }

            if ($jetzt -eq $ziel) {
                return [pscustomobject]@{ ok = $true
                    text = "Kanal $ziel gesetzt. Das Funknetz war dabei kurz unterbrochen." }
            }

            $hinweis = 'Die Box hat Kanal ' + $ziel + ' angenommen, funkt aber weiter auf ' + $jetzt +
                       '. Das heisst: die automatische Kanalwahl ist aktiv und ueberschreibt jede ' +
                       'Vorgabe. Abschalten laesst sie sich nur in der Weboberflaeche der Box: ' +
                       'WLAN, dann Funkkanal, dann Funkkanal-Einstellungen anpassen und den Kanal ' +
                       'manuell festlegen.'
            return [pscustomobject]@{ ok = $false; text = $hinweis }        }

        'wlansichtbar' {
            Set-FritzWlanSichtbar -Index ([int]$Daten.index) -Sichtbar ([bool]$Daten.an) -Credential $c
            Leere-Cache @('wlan')
            $z = if ($Daten.an) { 'wird wieder angezeigt' } else { 'ist verborgen' }
            return [pscustomobject]@{ ok = $true
                text = "Der Netzname $z. Verbergen erhöht die Sicherheit übrigens nicht — es macht das Netz nur unbequemer." }
        }

        'portfreigabe' {
            Remove-FritzPortfreigabe -Protokoll ([string]$Daten.protokoll) `
                                     -AussenPort ([int]$Daten.port) -Credential $c
            Leere-Cache @('ports')
            return [pscustomobject]@{ ok = $true; text = "Portfreigabe $($Daten.protokoll) $($Daten.port) entfernt." }
        }

        'neustart' {
            Restart-FritzBox -Credential $c
            Leere-Cache
            return [pscustomobject]@{ ok = $true
                text = 'Die Box startet neu. Das dauert ein bis zwei Minuten, in denen nichts erreichbar ist.' }
        }

        default { throw "Unbekannte Änderung: $Was" }
    }
}

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
    Set-FritzVerbindung -Adresse $konfig.BoxAdresse -Port $konfig.BoxPort `
                        -Tls ([bool]$konfig.BoxTls) -TlsPort $konfig.BoxTlsPort `
                        -Fingerabdruck $konfig.BoxFingerabdruck
    if ($konfig.BoxTls) { Initialize-FritzTlsPruefung }

    if (-not $script:Demo) {
        try { $script:Cred = Get-Zugang }
        catch {
            # Ohne Zugangsdaten wird nicht abgebrochen. Das Panel startet im
            # Lokal-Modus und zeigt alles, was ohne die Box messbar ist.
            $script:Lokal = $true
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
    if ($script:Demo) {
        Write-Host "  BEISPIELMODUS — keine echten Daten, nichts wird geschaltet" -ForegroundColor Yellow
    } elseif ($script:Lokal) {
        Write-Host "  LOKAL-MODUS — keine Zugangsdaten hinterlegt" -ForegroundColor Yellow
        Write-Host "  Netzwerk-Scan, Leitungsgüte und PC-Daten funktionieren." -ForegroundColor DarkGray
        Write-Host "  Für Mesh, Funk, Smart Home und Sicherheit: netzpanel einrichten" -ForegroundColor DarkGray
    } else {
        Write-Host "  verbunden mit $($konfig.BoxAdresse)" -ForegroundColor DarkGray
    }
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
                    '^/api/lokalnetz$'   { Send-Json $strom (Get-AnsichtLokalnetz);   break }
                    '^/api/scan$'        { Send-Json $strom (Get-AnsichtLokalnetz -MitScan); break }

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
                                Lokal       = $script:Lokal
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

                    # Alle Aenderungen an der Box laufen ueber einen Weg. Das haelt
                    # die Berechtigungspruefung und die Fehlerbehandlung an einer Stelle.
                    '^/api/aendern$' {
                        try {
                            if ($script:Demo)  { throw 'Beispielmodus — es wird nichts geändert.' }
                            if ($script:Lokal) { throw 'Ohne Zugangsdaten kann nichts an der Box geändert werden.' }
                            $d = $anf.Body | ConvertFrom-Json
                            $antwort = Invoke-Aenderung -Was $d.was -Daten $d
                            Send-Json $strom $antwort
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
