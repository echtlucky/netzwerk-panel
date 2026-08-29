# lib-fritz.ps1
# TR-064-Client fuer AVM-Geraete. Wird von start-panel.ps1 geladen.
# Kein eigenstaendiger Aufruf noetig.
#
# Jede Abfragefunktion wirft bei Fehlern eine Ausnahme. Der Server faengt sie
# einzeln ab, damit ein Dienst, den die Box nicht anbietet, nie das ganze
# Panel lahmlegt.

# Adresse und Port kommen aus den Einstellungen (siehe konfig.ps1).
$script:FritzHost    = 'fritz.box'
$script:FritzPort    = 49000
$script:FritzTls     = $false
$script:FritzTlsPort = 49443
$script:FritzFinger  = ''      # erwarteter Zertifikat-Fingerabdruck

function Set-FritzVerbindung {
    param([string]$Adresse, [int]$Port, [bool]$Tls, [int]$TlsPort, [string]$Fingerabdruck)
    if ($Adresse)       { $script:FritzHost    = $Adresse }
    if ($Port)          { $script:FritzPort    = $Port }
    if ($TlsPort)       { $script:FritzTlsPort = $TlsPort }
    if ($PSBoundParameters.ContainsKey('Tls')) { $script:FritzTls = $Tls }
    if ($null -ne $Fingerabdruck) { $script:FritzFinger = $Fingerabdruck }
}
function Get-FritzHostAdresse { $script:FritzHost }
function Get-FritzTlsAktiv    { $script:FritzTls }

# ------------------------------------------------------------ Verschluesselung
#
# Die FRITZ!Box bietet TR-064 auch ueber TLS an (Port 49443). Ohne TLS gingen
# Anmeldung und uebertragene Werte - etwa ein neuer WLAN-Schluessel - im
# Klartext durch das eigene Netz.
#
# Das Zertifikat der Box ist selbst ausgestellt und deshalb nicht ueber eine
# Zertifizierungsstelle pruefbar. Statt die Pruefung einfach abzuschalten,
# merkt sich das Panel bei der Einrichtung den Fingerabdruck und vergleicht ihn
# bei jeder Verbindung - dasselbe Verfahren, das SSH beim ersten Verbinden nutzt.
# Aendert er sich, wird die Verbindung abgelehnt: entweder wurde die Box
# zurueckgesetzt, oder es antwortet nicht mehr die Box.

$script:LetzterFinger = ''

function Initialize-FritzTlsPruefung {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
        param($absender, $zertifikat, $kette, $fehler)
        if (-not $zertifikat) { return $false }
        $finger = $zertifikat.GetCertHashString()
        $script:LetzterFinger = $finger
        # Ohne hinterlegten Fingerabdruck wird der erste akzeptiert und gemerkt.
        if (-not $script:FritzFinger) { return $true }
        return ($finger -eq $script:FritzFinger)
    }
}

function Get-FritzZertifikatFingerabdruck {
    param([string]$Adresse, [int]$Port = 49443)
    if (-not $Adresse) { $Adresse = $script:FritzHost }

    $alterCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    $gemerkt = ''
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
            param($a, $z, $k, $f)
            if ($z) { $script:LetzterFinger = $z.GetCertHashString() }
            return $true
        }
        $req = [System.Net.HttpWebRequest]::Create("https://${Adresse}:$Port/tr64desc.xml")
        $req.Timeout = 8000
        $res = $req.GetResponse()
        $res.Close()
        $gemerkt = $script:LetzterFinger
    }
    catch { throw "TLS-Verbindung zu ${Adresse}:$Port fehlgeschlagen: $($_.Exception.Message)" }
    finally { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $alterCallback }
    $gemerkt
}

# Baut die Basisadresse - je nach Einstellung verschluesselt oder nicht.
function Get-FritzBasis {
    if ($script:FritzTls) { return "https://$($script:FritzHost):$($script:FritzTlsPort)" }
    "http://$($script:FritzHost):$($script:FritzPort)"
}

# Wird von konfig.ps1 bereitgestellt. Der Umweg ueber eine eigene Funktion
# haelt den TR-064-Client unabhaengig davon, woher die Zugangsdaten stammen.
function Get-FritzCredential { Get-Zugang }

# --------------------------------------------------------------- SOAP-Aufruf
function Invoke-Tr064 {
    param(
        [Parameter(Mandatory)][string] $Control,
        [Parameter(Mandatory)][string] $Service,
        [Parameter(Mandatory)][string] $Action,
        [System.Collections.IDictionary] $Arguments = @{},
        [System.Management.Automation.PSCredential] $Credential,
        [string] $TargetHost,
        [int]    $TimeoutMs = 12000
    )

    if (-not $Credential) { $Credential = Get-FritzCredential }
    if (-not $TargetHost) { $TargetHost = $script:FritzHost }

    $argXml = ''
    foreach ($k in $Arguments.Keys) {
        $v = [System.Security.SecurityElement]::Escape([string]$Arguments[$k])
        $argXml += "<$k>$v</$k>"
    }

    $body = '<?xml version="1.0" encoding="utf-8"?>' +
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ' +
            's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>' +
            "<u:$Action xmlns:u=`"$Service`">$argXml</u:$Action>" +
            '</s:Body></s:Envelope>'

    $basis = Get-FritzBasis
    if ($TargetHost -ne $script:FritzHost) { $basis = "http://${TargetHost}:$($script:FritzPort)" }
    $uri = "$basis$Control"

    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method      = 'POST'
    $req.ContentType = 'text/xml; charset="utf-8"'
    $req.Headers.Add('SOAPAction', "$Service#$Action")
    $req.Timeout     = $TimeoutMs

    # Digest-Authentifizierung: das Passwort geht als Hash ueber die Leitung, nie im Klartext.
    $cache = New-Object System.Net.CredentialCache
    $cache.Add((New-Object Uri($uri)), 'Digest', $Credential.GetNetworkCredential())
    $req.Credentials     = $cache
    $req.PreAuthenticate = $true

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $req.ContentLength = $bytes.Length
    $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()

    try {
        $res = $req.GetResponse()
        $rd  = New-Object System.IO.StreamReader($res.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $xml = [xml]$rd.ReadToEnd()
        $rd.Close(); $res.Close()
        return $xml.Envelope.Body.FirstChild
    }
    catch [System.Net.WebException] {
        $r = $_.Exception.Response
        if ($r) {
            $rd  = New-Object System.IO.StreamReader($r.GetResponseStream())
            $txt = $rd.ReadToEnd(); $rd.Close()
            if ($txt -match '<errorCode>(\d+)</errorCode>') {
                $c = $Matches[1]
                $klar = @{
                    '401' = 'nicht berechtigt'
                    '402' = 'ungültiger Parameter'
                    '501' = 'Aktion fehlgeschlagen'
                    '606' = 'Aktion nicht erlaubt - dem Benutzer fehlt die Berechtigung'
                    '713' = 'Index außerhalb des Bereichs'
                    '714' = 'kein Eintrag vorhanden'
                }[$c]
                if (-not $klar) { $klar = "Fehler $c" }
                throw "TR-064: $klar (bei $Action)"
            }
            if ([int]$r.StatusCode -eq 401) {
                throw "Anmeldung abgelehnt. Benutzer oder Passwort falsch, oder TR-064 ist in der FRITZ!Box nicht freigegeben."
            }
            if ([int]$r.StatusCode -eq 500) {
                throw "Die Box lehnt '$Action' ab - dieser Dienst wird hier nicht angeboten."
            }
        }
        throw "Verbindung zu $TargetHost fehlgeschlagen: $($_.Exception.Message)"
    }
}

# Laedt eine Datei, deren Pfad ueber TR-064 mitgeteilt wurde (Hostliste, Mesh, Anrufliste).
function Get-FritzDatei {
    param([Parameter(Mandatory)][string]$Pfad, [string]$TargetHost)
    if (-not $TargetHost) { $TargetHost = $script:FritzHost }
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    if ($Pfad -match '^https?://') { return $wc.DownloadString($Pfad) }
    $basis = Get-FritzBasis
    if ($TargetHost -ne $script:FritzHost) { $basis = "http://${TargetHost}:$($script:FritzPort)" }
    $wc.DownloadString("$basis$Pfad")
}

# ===================================================================== BASIS

function Get-FritzGeraeteInfo {
    param($Credential, [string]$TargetHost)
    $r = Invoke-Tr064 -Control '/upnp/control/deviceinfo' `
                      -Service 'urn:dslforum-org:service:DeviceInfo:1' `
                      -Action  'GetInfo' -Credential $Credential -TargetHost $TargetHost
    [pscustomobject]@{
        Modell      = $r.NewModelName
        Firmware    = $r.NewSoftwareVersion
        Seriennr    = $r.NewSerialNumber
        LaufzeitSek = [int]$r.NewUpTime
    }
}

function Get-FritzFirmwareStand {
    param($Credential)
    $r = Invoke-Tr064 -Control '/upnp/control/userif' `
                      -Service 'urn:dslforum-org:service:UserInterface:1' `
                      -Action  'GetInfo' -Credential $Credential
    [pscustomobject]@{
        UpdateVerfuegbar = ($r.NewUpgradeAvailable -eq '1')
        NeueVersion      = $r.'NewX_AVM-DE_Version'
        Infoseite        = $r.'NewX_AVM-DE_InfoURL'
    }
}

function Get-FritzZeit {
    param($Credential)
    $r = Invoke-Tr064 -Control '/upnp/control/time' `
                      -Service 'urn:dslforum-org:service:Time:1' `
                      -Action  'GetInfo' -Credential $Credential
    [pscustomobject]@{ NtpServer1 = $r.NewNTPServer1; NtpServer2 = $r.NewNTPServer2 }
}

# ================================================================== WAN / DSL

function Get-FritzWanStatus {
    param($Credential)
    $link = Invoke-Tr064 -Control '/upnp/control/wancommonifconfig1' `
                         -Service 'urn:dslforum-org:service:WANCommonInterfaceConfig:1' `
                         -Action  'GetCommonLinkProperties' -Credential $Credential
    $conn = $null
    foreach ($v in @(
        @{ c = '/upnp/control/wanpppconn1';     s = 'urn:dslforum-org:service:WANPPPConnection:1' },
        @{ c = '/upnp/control/wanipconnection1'; s = 'urn:dslforum-org:service:WANIPConnection:1' })) {
        if ($conn) { continue }
        try { $conn = Invoke-Tr064 -Control $v.c -Service $v.s -Action 'GetInfo' -Credential $Credential }
        catch { }
    }

    $ip = '-'; $seit = 0; $status = 'unbekannt'; $fehler = ''
    if ($conn) {
        $ip     = $conn.NewExternalIPAddress
        $seit   = [int]$conn.NewUptime
        $status = $conn.NewConnectionStatus
        $fehler = $conn.NewLastConnectionError
    }

    [pscustomobject]@{
        Zugangsart    = $link.NewWANAccessType
        Verbindung    = $link.NewPhysicalLinkStatus
        DownMbit      = [math]::Round([double]$link.NewLayer1DownstreamMaxBitRate / 1e6, 1)
        UpMbit        = [math]::Round([double]$link.NewLayer1UpstreamMaxBitRate   / 1e6, 1)
        ExterneIP     = $ip
        OnlineSeitSek = $seit
        Status        = $status
        LetzterFehler = $fehler
    }
}

# Momentaner Durchsatz. Die Box liefert eine Reihe der letzten Messwerte -
# daraus baut das Panel den Verlaufsgraphen.
function Get-FritzDurchsatz {
    param($Credential)
    $r = Invoke-Tr064 -Control '/upnp/control/wancommonifconfig1' `
                      -Service 'urn:dslforum-org:service:WANCommonInterfaceConfig:1' `
                      -Action  'X_AVM-DE_GetOnlineMonitor' `
                      -Arguments @{ NewSyncGroupIndex = 0 } -Credential $Credential

    $reihe = {
        param($text)
        if (-not $text) { return @() }
        ($text -split ',') | ForEach-Object { [math]::Round(([double]$_ * 8) / 1e6, 2) }
    }
    $ds = & $reihe $r.'Newds_current_bps'
    $us = & $reihe $r.'Newus_current_bps'

    [pscustomobject]@{
        DownMbit      = if ($ds.Count) { $ds[0] } else { 0 }
        UpMbit        = if ($us.Count) { $us[0] } else { 0 }
        VerlaufDown   = $ds
        VerlaufUp     = $us
        MaxDownMbit   = [math]::Round([double]$r.'Newmax_ds' * 8 / 1e6, 1)
        MaxUpMbit     = [math]::Round([double]$r.'Newmax_us' * 8 / 1e6, 1)
    }
}

# Leitungsqualitaet. Stoerabstand und Daempfung sagen mehr ueber die Anschluss-
# guete aus als jede Geschwindigkeitsmessung.
function Get-FritzDslInfo {
    param($Credential)
    $r = Invoke-Tr064 -Control '/upnp/control/wandslifconfig1' `
                      -Service 'urn:dslforum-org:service:WANDSLInterfaceConfig:1' `
                      -Action  'GetInfo' -Credential $Credential
    [pscustomobject]@{
        Status          = $r.NewStatus
        Betriebsart     = $r.NewModulationType
        DownAktuellKbit = [int]$r.NewDownstreamCurrRate
        UpAktuellKbit   = [int]$r.NewUpstreamCurrRate
        DownMaxKbit     = [int]$r.NewDownstreamMaxRate
        UpMaxKbit       = [int]$r.NewUpstreamMaxRate
        DownStoerabstand = [math]::Round([double]$r.NewDownstreamNoiseMargin / 10, 1)
        UpStoerabstand   = [math]::Round([double]$r.NewUpstreamNoiseMargin   / 10, 1)
        DownDaempfung    = [math]::Round([double]$r.NewDownstreamAttenuation / 10, 1)
        UpDaempfung      = [math]::Round([double]$r.NewUpstreamAttenuation   / 10, 1)
        DownLeistung     = [math]::Round([double]$r.NewDownstreamPower / 10, 1)
        UpLeistung       = [math]::Round([double]$r.NewUpstreamPower   / 10, 1)
    }
}

# Fehlerzaehler seit dem letzten Synchronisieren. Steigende CRC-Fehler oder
# haeufige Neusynchronisierungen sind der Beweis fuer eine schlechte Leitung.
function Get-FritzDslFehler {
    param($Credential)
    $r = Invoke-Tr064 -Control '/upnp/control/wandslifconfig1' `
                      -Service 'urn:dslforum-org:service:WANDSLInterfaceConfig:1' `
                      -Action  'GetStatisticsTotal' -Credential $Credential
    [pscustomobject]@{
        Neusynchronisierungen = [int]$r.NewLinkRetrain
        Startfehler           = [int]$r.NewInitErrors
        Zeitueberschreitungen = [int]$r.NewInitTimeouts
        RahmenVerloren        = [int]$r.NewLossOfFraming
        FehlerSekunden        = [int]$r.NewErroredSecs
        SchwereFehlerSekunden = [int]$r.NewSeverelyErroredSecs
        FecFehler             = [int]$r.NewFECErrors
        CrcFehler             = [int]$r.NewCRCErrors
        HecFehler             = [int]$r.NewHECErrors
    }
}

function Get-FritzLanStatistik {
    param($Credential)
    $i = Invoke-Tr064 -Control '/upnp/control/lanethernetifcfg' `
                      -Service 'urn:dslforum-org:service:LANEthernetInterfaceConfig:1' `
                      -Action  'GetInfo' -Credential $Credential
    $s = Invoke-Tr064 -Control '/upnp/control/lanethernetifcfg' `
                      -Service 'urn:dslforum-org:service:LANEthernetInterfaceConfig:1' `
                      -Action  'GetStatistics' -Credential $Credential
    [pscustomobject]@{
        Status        = $i.NewStatus
        MacAdresse    = $i.NewMACAddress
        PaketeGesendet  = [int64]$s.NewBytesSent
        PaketeEmpfangen = [int64]$s.NewBytesReceived
    }
}

# ==================================================================== GERAETE

function Get-FritzHosts {
    param($Credential)
    if (-not $Credential) { $Credential = Get-FritzCredential }
    $r = Invoke-Tr064 -Control '/upnp/control/hosts' `
                      -Service 'urn:dslforum-org:service:Hosts:1' `
                      -Action  'X_AVM-DE_GetHostListPath' -Credential $Credential
    $xml = [xml](Get-FritzDatei -Pfad $r.'NewX_AVM-DE_HostListPath')

    $xml.List.Item | ForEach-Object {
        [pscustomobject]@{
            Name       = $_.HostName
            IP         = $_.IPAddress
            MAC        = $_.MACAddress
            Aktiv      = ($_.Active -eq '1')
            Art        = $_.InterfaceType
            Port       = $_.'X_AVM-DE_Port'
            Speed      = $_.'X_AVM-DE_Speed'
            Gast       = ($_.'X_AVM-DE_Guest' -eq '1')
            Gesperrt   = ($_.'X_AVM-DE_Disallow' -eq '1')
            UpdateVerf = ($_.'X_AVM-DE_UpdateAvailable' -eq '1')
            Modell     = $_.'X_AVM-DE_Model'
            Hersteller = $_.'X_AVM-DE_VendorName'
            Fest       = ($_.AddressSource -eq 'Static')
            Quelle     = $_.AddressSource
        }
    }
}

function Get-FritzMesh {
    param($Credential)
    if (-not $Credential) { $Credential = Get-FritzCredential }
    $r = Invoke-Tr064 -Control '/upnp/control/hosts' `
                      -Service 'urn:dslforum-org:service:Hosts:1' `
                      -Action  'X_AVM-DE_GetMeshListPath' -Credential $Credential
    Get-FritzDatei -Pfad $r.'NewX_AVM-DE_MeshListPath' | ConvertFrom-Json
}

function Set-FritzGeraetSperre {
    param([Parameter(Mandatory)][string]$MAC, [Parameter(Mandatory)][bool]$Sperren, $Credential)
    $wert = '0'; if ($Sperren) { $wert = '1' }
    # Bevorzugt der eigene Filterdienst, sonst der Hosts-Weg.
    try {
        Invoke-Tr064 -Control '/upnp/control/x_hostfilter' `
                     -Service 'urn:dslforum-org:service:X_AVM-DE_HostFilter:1' `
                     -Action  'Disallow' `
                     -Arguments @{ 'NewMACAddress' = $MAC; 'NewDisallow' = $wert } `
                     -Credential $Credential | Out-Null
    } catch {
        Invoke-Tr064 -Control '/upnp/control/hosts' `
                     -Service 'urn:dslforum-org:service:Hosts:1' `
                     -Action  'X_AVM-DE_SetInternetAccessDisallowed' `
                     -Arguments @{ 'NewMACAddress' = $MAC; 'NewDisallow' = $wert } `
                     -Credential $Credential | Out-Null
    }
}

function Invoke-FritzWakeOnLan {
    param([Parameter(Mandatory)][string]$MAC, $Credential)
    Invoke-Tr064 -Control '/upnp/control/hosts' `
                 -Service 'urn:dslforum-org:service:Hosts:1' `
                 -Action  'X_AVM-DE_WakeOnLANByMACAddress' `
                 -Arguments @{ 'NewMACAddress' = $MAC } -Credential $Credential | Out-Null
}

# ======================================================================= WLAN

function Get-FritzWlan {
    param($Credential)
    $namen = @{ 1 = '2,4 GHz'; 2 = '5 GHz'; 3 = 'Gastnetz' }
    $ergebnis = @()
    foreach ($i in 1..3) {
        try {
            $r = Invoke-Tr064 -Control "/upnp/control/wlanconfig$i" `
                              -Service "urn:dslforum-org:service:WLANConfiguration:$i" `
                              -Action  'GetInfo' -Credential $Credential

            $anzahl = 0
            try {
                $a = Invoke-Tr064 -Control "/upnp/control/wlanconfig$i" `
                                  -Service "urn:dslforum-org:service:WLANConfiguration:$i" `
                                  -Action  'GetTotalAssociations' -Credential $Credential
                $anzahl = [int]$a.NewTotalAssociations
            } catch { }

            $ergebnis += [pscustomobject]@{
                Index    = $i
                Band     = $namen[$i]
                SSID     = $r.NewSSID
                An       = ($r.NewEnable -eq '1')
                Kanal    = $r.NewChannel
                Schutz   = $r.NewBeaconType
                Sichtbar = ($r.NewSSIDAdvertisementEnabled -eq '1')
                Standard = $r.NewStandard
                Clients  = $anzahl
            }
        } catch { }
    }
    $ergebnis
}

# Alle Funk-Clients mit Signalstaerke und ausgehandelter Datenrate.
function Get-FritzWlanClients {
    param($Credential)
    $namen = @{ 1 = '2,4 GHz'; 2 = '5 GHz'; 3 = 'Gastnetz' }
    $liste = @()
    foreach ($i in 1..3) {
        $anzahl = 0
        try {
            $a = Invoke-Tr064 -Control "/upnp/control/wlanconfig$i" `
                              -Service "urn:dslforum-org:service:WLANConfiguration:$i" `
                              -Action  'GetTotalAssociations' -Credential $Credential
            $anzahl = [int]$a.NewTotalAssociations
        } catch { continue }

        for ($n = 0; $n -lt $anzahl; $n++) {
            try {
                $c = Invoke-Tr064 -Control "/upnp/control/wlanconfig$i" `
                                  -Service "urn:dslforum-org:service:WLANConfiguration:$i" `
                                  -Action  'GetGenericAssociatedDeviceInfo' `
                                  -Arguments @{ NewAssociatedDeviceIndex = $n } -Credential $Credential
                $liste += [pscustomobject]@{
                    Band       = $namen[$i]
                    BandIndex  = $i
                    MAC        = $c.NewAssociatedDeviceMACAddress
                    IP         = $c.NewAssociatedDeviceIPAddress
                    Angemeldet = ($c.NewAssociatedDeviceAuthState -eq '1')
                    SpeedMbit  = [int]$c.'NewX_AVM-DE_Speed'
                    Signal     = [int]$c.'NewX_AVM-DE_SignalStrength'
                }
            } catch { }
        }
    }
    $liste
}

function Set-FritzWlan {
    param([Parameter(Mandatory)][int]$Index, [Parameter(Mandatory)][bool]$An, $Credential)
    $wert = '0'; if ($An) { $wert = '1' }
    Invoke-Tr064 -Control "/upnp/control/wlanconfig$Index" `
                 -Service "urn:dslforum-org:service:WLANConfiguration:$Index" `
                 -Action  'SetEnable' -Arguments @{ NewEnable = $wert } -Credential $Credential | Out-Null
}

# Liefert SSID und Schluessel des Gastnetzes - daraus baut das Panel den QR-Code.
function Get-FritzGastZugang {
    param($Credential)
    $i = Invoke-Tr064 -Control '/upnp/control/wlanconfig3' `
                      -Service 'urn:dslforum-org:service:WLANConfiguration:3' `
                      -Action  'GetInfo' -Credential $Credential
    $k = Invoke-Tr064 -Control '/upnp/control/wlanconfig3' `
                      -Service 'urn:dslforum-org:service:WLANConfiguration:3' `
                      -Action  'GetSecurityKeys' -Credential $Credential
    [pscustomobject]@{
        SSID       = $i.NewSSID
        An         = ($i.NewEnable -eq '1')
        Schluessel = $k.NewKeyPassphrase
        Schutz     = $i.NewBeaconType
    }
}

# ================================================================= SICHERHEIT

function Get-FritzSicherheitslage {
    param($Credential)

    $upnp = $null
    try {
        $r = Invoke-Tr064 -Control '/upnp/control/x_upnp' `
                          -Service 'urn:dslforum-org:service:X_AVM-DE_UPnP:1' `
                          -Action  'GetInfo' -Credential $Credential
        $upnp = [pscustomobject]@{
            An          = ($r.NewEnable -eq '1')
            Medienserver = ($r.'NewX_AVM-DE_UPnPMediaServer' -eq '1')
        }
    } catch { }

    $fern = $null
    try {
        $r = Invoke-Tr064 -Control '/upnp/control/x_remote' `
                          -Service 'urn:dslforum-org:service:X_AVM-DE_RemoteAccess:1' `
                          -Action  'GetInfo' -Credential $Credential
        $fern = [pscustomobject]@{
            An       = ($r.NewEnabled -eq '1')
            Port     = $r.NewPort
            Benutzer = $r.NewUsername
        }
    } catch { }

    $myfritz = $null
    try {
        $r = Invoke-Tr064 -Control '/upnp/control/x_myfritz' `
                          -Service 'urn:dslforum-org:service:X_AVM-DE_MyFritz:1' `
                          -Action  'GetInfo' -Credential $Credential
        $myfritz = [pscustomobject]@{ An = ($r.NewEnabled -eq '1'); Name = $r.NewDynDNSName }
    } catch { }

    [pscustomobject]@{ Upnp = $upnp; Fernzugriff = $fern; MyFritz = $myfritz }
}

# Alle eingerichteten Portfreigaben - jede davon ist ein Loch in der Aussenwand.
function Get-FritzPortfreigaben {
    param($Credential)
    $dienste = @(
        @{ c = '/upnp/control/wanpppconn1';      s = 'urn:dslforum-org:service:WANPPPConnection:1' },
        @{ c = '/upnp/control/wanipconnection1'; s = 'urn:dslforum-org:service:WANIPConnection:1' }
    )
    foreach ($d in $dienste) {
        $anzahl = $null
        try {
            $r = Invoke-Tr064 -Control $d.c -Service $d.s `
                              -Action 'GetPortMappingNumberOfEntries' -Credential $Credential
            $anzahl = [int]$r.NewPortMappingNumberOfEntries
        } catch { continue }

        $liste = @()
        for ($i = 0; $i -lt $anzahl; $i++) {
            try {
                $e = Invoke-Tr064 -Control $d.c -Service $d.s `
                                  -Action 'GetGenericPortMappingEntry' `
                                  -Arguments @{ NewPortMappingIndex = $i } -Credential $Credential
                $liste += [pscustomobject]@{
                    Beschreibung = $e.NewPortMappingDescription
                    Protokoll    = $e.NewPortMappingProtocol
                    AussenPort   = $e.NewExternalPort
                    Ziel         = $e.NewInternalClient
                    ZielPort     = $e.NewInternalPort
                    Aktiv        = ($e.NewEnabled -eq '1')
                }
            } catch { }
        }
        return $liste
    }
    @()
}

# Das Ereignisprotokoll der Box. Hier stehen Neusynchronisierungen, Anmelde-
# versuche und Verbindungsabbrueche - die Belege, wenn etwas nicht stimmt.
function Get-FritzProtokoll {
    param($Credential, [int]$Zeilen = 120)
    $r = Invoke-Tr064 -Control '/upnp/control/deviceinfo' `
                      -Service 'urn:dslforum-org:service:DeviceInfo:1' `
                      -Action  'X_AVM-DE_GetDeviceLog' -Credential $Credential
    $roh = $r.'NewDeviceLog'
    if (-not $roh) { return @() }

    $erg = @()
    foreach ($z in ($roh -split "`n")) {
        $z = $z.Trim()
        if (-not $z) { continue }
        # Format: "28.08.26 11:15:03 Text"
        if ($z -match '^(\d{2}\.\d{2}\.\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(.*)$') {
            $text = $Matches[3]
            $art  = 'info'
            if ($text -match 'fehlgeschlagen|Fehler|abgelehnt|getrennt|verloren|nicht m|ung.ltig') { $art = 'warnung' }
            if ($text -match 'Anmeldung.*fehlgeschlagen|Kennwort|unerlaubt|abgewiesen')            { $art = 'kritisch' }
            if ($text -match 'hergestellt|erfolgreich|angemeldet|aktualisiert')                    { $art = 'gut' }
            $erg += [pscustomobject]@{ Datum = $Matches[1]; Zeit = $Matches[2]; Text = $text; Art = $art }
        }
        if ($erg.Count -ge $Zeilen) { break }
    }
    $erg
}

# ================================================================ SMART HOME

function Get-FritzSmartHome {
    param($Credential)
    $liste = @()
    for ($i = 0; $i -lt 32; $i++) {
        try {
            $d = Invoke-Tr064 -Control '/upnp/control/x_homeauto' `
                              -Service 'urn:dslforum-org:service:X_AVM-DE_Homeauto:1' `
                              -Action  'GetGenericDeviceInfos' `
                              -Arguments @{ NewIndex = $i } -Credential $Credential
        } catch { break }
        if (-not $d.NewAIN) { break }

        $tempIst = $null
        if ($d.NewTemperatureIsValid -eq 'VALID') {
            $tempIst = [math]::Round([double]$d.NewTemperatureCelsius / 10, 1)
        }
        $leistung = $null; $energie = $null
        if ($d.NewMultimeterIsValid -eq 'VALID') {
            $leistung = [math]::Round([double]$d.NewMultimeterPower / 100, 2)
            $energie  = [int]$d.NewMultimeterEnergy
        }
        $sollTemp = $null
        if ($d.NewHkrIsValid -eq 'VALID') {
            $sollTemp = [math]::Round([double]$d.NewHkrSetTemperature / 2, 1)
        }

        $liste += [pscustomobject]@{
            AIN          = $d.NewAIN
            Name         = $d.NewDeviceName
            Produkt      = $d.NewProductName
            Hersteller   = $d.NewManufacturer
            Firmware     = $d.NewFirmwareVersion
            Erreichbar   = ($d.NewPresent -eq 'CONNECTED')
            HatSchalter  = ($d.NewSwitchIsValid -eq 'VALID')
            SchalterAn   = ($d.NewSwitchState -eq 'ON')
            Gesperrt     = ($d.NewSwitchLock -eq '1')
            LeistungWatt = $leistung
            EnergieWh    = $energie
            TempCelsius  = $tempIst
            HatThermostat = ($d.NewHkrIsValid -eq 'VALID')
            SollTemp     = $sollTemp
        }
    }
    $liste
}

function Set-FritzSteckdose {
    param([Parameter(Mandatory)][string]$AIN, [Parameter(Mandatory)][bool]$An, $Credential)
    $wert = 'OFF'; if ($An) { $wert = 'ON' }
    Invoke-Tr064 -Control '/upnp/control/x_homeauto' `
                 -Service 'urn:dslforum-org:service:X_AVM-DE_Homeauto:1' `
                 -Action  'SetSwitch' `
                 -Arguments @{ NewAIN = $AIN; NewSwitchState = $wert } -Credential $Credential | Out-Null
}

# ================================================================= TELEFONIE

function Get-FritzAnrufe {
    param($Credential, [int]$Anzahl = 40)
    $r = Invoke-Tr064 -Control '/upnp/control/x_contact' `
                      -Service 'urn:dslforum-org:service:X_AVM-DE_OnTel:1' `
                      -Action  'GetCallList' -Credential $Credential
    if (-not $r.NewCallListURL) { return @() }

    $xml = [xml](Get-FritzDatei -Pfad ($r.NewCallListURL + "&max=$Anzahl"))
    $arten = @{ '1' = 'eingehend'; '2' = 'verpasst'; '3' = 'ausgehend'; '9' = 'aktiv'; '10' = 'abgelehnt' }

    $xml.root.Call | Select-Object -First $Anzahl | ForEach-Object {
        [pscustomobject]@{
            Art      = $arten[[string]$_.Type]
            Datum    = $_.Date
            Name     = $_.Name
            Nummer   = $_.Caller
            Eigene   = $_.CalledNumber
            Dauer    = $_.Duration
            Geraet   = $_.Device
        }
    }
}

function Get-FritzDect {
    param($Credential)
    $r = Invoke-Tr064 -Control '/upnp/control/x_dect' `
                      -Service 'urn:dslforum-org:service:X_AVM-DE_Dect:1' `
                      -Action  'GetNumberOfDectEntries' -Credential $Credential
    $anzahl = [int]$r.NewNumberOfEntries
    $liste = @()
    for ($i = 0; $i -lt $anzahl; $i++) {
        try {
            $d = Invoke-Tr064 -Control '/upnp/control/x_dect' `
                              -Service 'urn:dslforum-org:service:X_AVM-DE_Dect:1' `
                              -Action  'GetGenericDectEntry' `
                              -Arguments @{ NewIndex = $i } -Credential $Credential
            $liste += [pscustomobject]@{
                Name       = $d.NewID
                Erreichbar = ($d.NewActive -eq '1')
                Modell     = $d.NewModel
                Akku       = $d.NewLowBattery
                Update     = ($d.NewUpdateAvailable -eq '1')
            }
        } catch { }
    }
    $liste
}

# ================================================================== AKTIONEN

function Invoke-FritzNeuverbinden {
    param($Credential)
    foreach ($d in @(
        @{ c = '/upnp/control/wanpppconn1';      s = 'urn:dslforum-org:service:WANPPPConnection:1' },
        @{ c = '/upnp/control/wanipconnection1'; s = 'urn:dslforum-org:service:WANIPConnection:1' })) {
        try {
            Invoke-Tr064 -Control $d.c -Service $d.s -Action 'ForceTermination' -Credential $Credential | Out-Null
            return
        } catch { }
    }
    throw 'Neuverbinden wird von dieser Box nicht angeboten.'
}


# ============================================================== EINSTELLUNGEN
#
# Alles hier veraendert die FRITZ!Box. Jede Funktion tut genau eine Sache und
# meldet Fehler weiter, statt sie zu verschlucken - der Aufrufer entscheidet,
# wie er damit umgeht.

# Schaltet die selbststaendigen Portfreigaben ab (oder wieder an).
# Der Medienserver wird dabei mitgesendet, weil die Box beide Werte zusammen
# erwartet - sein aktueller Zustand wird vorher gelesen und beibehalten.
function Set-FritzUpnp {
    param([Parameter(Mandatory)][bool]$An, $Credential)

    $ist = Invoke-Tr064 -Control '/upnp/control/x_upnp' `
                        -Service 'urn:dslforum-org:service:X_AVM-DE_UPnP:1' `
                        -Action 'GetInfo' -Credential $Credential
    $medien = '0'
    if ($ist.'NewX_AVM-DE_UPnPMediaServer' -eq '1') { $medien = '1' }

    $wert = '0'; if ($An) { $wert = '1' }
    Invoke-Tr064 -Control '/upnp/control/x_upnp' `
                 -Service 'urn:dslforum-org:service:X_AVM-DE_UPnP:1' `
                 -Action 'SetConfig' `
                 -Arguments ([ordered]@{ NewEnable = $wert; NewUPnPMediaServer = $medien }) `
                 -Credential $Credential | Out-Null
}

function Set-FritzFernzugriff {
    param([Parameter(Mandatory)][bool]$An, $Credential)
    $wert = '0'; if ($An) { $wert = '1' }
    Invoke-Tr064 -Control '/upnp/control/x_remote' `
                 -Service 'urn:dslforum-org:service:X_AVM-DE_RemoteAccess:1' `
                 -Action 'SetEnable' -Arguments ([ordered]@{ NewEnabled = $wert }) `
                 -Credential $Credential | Out-Null
}

function Set-FritzWlanName {
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$Name,
        $Credential
    )
    if ($Name.Length -lt 1 -or $Name.Length -gt 32) {
        throw 'Ein WLAN-Name muss zwischen 1 und 32 Zeichen lang sein.'
    }
    Invoke-Tr064 -Control "/upnp/control/wlanconfig$Index" `
                 -Service "urn:dslforum-org:service:WLANConfiguration:$Index" `
                 -Action 'SetSSID' -Arguments ([ordered]@{ NewSSID = $Name }) `
                 -Credential $Credential | Out-Null
}

# Setzt den WLAN-Schluessel. Laeuft nur ueber eine verschluesselte Verbindung -
# sonst ginge der neue Schluessel im Klartext durch das eigene Netz.
function Set-FritzWlanSchluessel {
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$Schluessel,
        $Credential
    )
    if (-not (Get-FritzTlsAktiv)) {
        throw 'Ein WLAN-Schlüssel wird nur über eine verschlüsselte Verbindung gesetzt. In den Einstellungen „Verschlüsselte Verbindung" einschalten.'
    }
    if ($Schluessel.Length -lt 8 -or $Schluessel.Length -gt 63) {
        throw 'Ein WLAN-Schlüssel muss zwischen 8 und 63 Zeichen lang sein.'
    }
    Invoke-Tr064 -Control "/upnp/control/wlanconfig$Index" `
                 -Service "urn:dslforum-org:service:WLANConfiguration:$Index" `
                 -Action 'SetSecurityKeys' `
                 -Arguments ([ordered]@{
                     NewWEPKey0 = ''; NewWEPKey1 = ''; NewWEPKey2 = ''; NewWEPKey3 = ''
                     NewPreSharedKey = ''; NewKeyPassphrase = $Schluessel
                 }) -Credential $Credential | Out-Null
}

function Set-FritzWlanKanal {
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$Kanal,
        $Credential
    )
    # 0 bedeutet: die Box waehlt selbst
    Invoke-Tr064 -Control "/upnp/control/wlanconfig$Index" `
                 -Service "urn:dslforum-org:service:WLANConfiguration:$Index" `
                 -Action 'SetChannel' -Arguments ([ordered]@{ NewChannel = $Kanal }) `
                 -Credential $Credential | Out-Null
}

function Set-FritzWlanSichtbar {
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][bool]$Sichtbar,
        $Credential
    )
    $wert = '0'; if ($Sichtbar) { $wert = '1' }
    Invoke-Tr064 -Control "/upnp/control/wlanconfig$Index" `
                 -Service "urn:dslforum-org:service:WLANConfiguration:$Index" `
                 -Action 'SetBeaconAdvertisement' `
                 -Arguments ([ordered]@{ NewBeaconAdvertisementEnabled = $wert }) `
                 -Credential $Credential | Out-Null
}

function Remove-FritzPortfreigabe {
    param(
        [Parameter(Mandatory)][string]$Protokoll,
        [Parameter(Mandatory)][int]$AussenPort,
        [string]$Gegenstelle = '',
        $Credential
    )
    foreach ($v in @(
        @{ c = '/upnp/control/wanpppconn1';      s = 'urn:dslforum-org:service:WANPPPConnection:1' },
        @{ c = '/upnp/control/wanipconnection1'; s = 'urn:dslforum-org:service:WANIPConnection:1' })) {
        try {
            Invoke-Tr064 -Control $v.c -Service $v.s -Action 'DeletePortMapping' `
                         -Arguments ([ordered]@{
                             NewRemoteHost = $Gegenstelle
                             NewExternalPort = $AussenPort
                             NewProtocol = $Protokoll.ToUpper()
                         }) -Credential $Credential | Out-Null
            return
        } catch { }
    }
    throw 'Die Portfreigabe konnte nicht entfernt werden.'
}

function Restart-FritzBox {
    param($Credential)
    Invoke-Tr064 -Control '/upnp/control/deviceconfig' `
                 -Service 'urn:dslforum-org:service:DeviceConfig:1' `
                 -Action 'Reboot' -Credential $Credential | Out-Null
}