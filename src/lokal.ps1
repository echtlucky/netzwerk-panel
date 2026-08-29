# lokal.ps1
# Messungen, die ohne Zugang zur FRITZ!Box auskommen.
#
# Damit ist das Panel auch dann nuetzlich, wenn keine Zugangsdaten hinterlegt
# sind - oder wenn der Router gar keine TR-064-Schnittstelle anbietet. Alles
# hier stammt aus dem, was der eigene Rechner ueber das Netz sehen kann.

# Hersteller-Zuordnung ueber die ersten drei Bytes der MAC-Adresse (OUI).
# Bewusst eine kleine, gepflegte Auswahl statt einer Online-Abfrage - das
# Panel soll ohne Internetzugang funktionieren und nichts nach draussen melden.
$script:Hersteller = @{
    '3481C4' = 'AVM';        'D424DD' = 'AVM';        'DC392A' = 'AVM'
    'C80E14' = 'AVM';        'E0286D' = 'AVM';        '38108C' = 'AVM'
    '1C0EC2' = 'Apple';      'A483E7' = 'Apple';      'F0189E' = 'Apple'
    '3C2EF9' = 'Apple';      'D8BB2C' = 'Apple';      '8866A5' = 'Apple'
    '1CAF4A' = 'Samsung';    '5001BB' = 'Samsung';    'B0C090' = 'Samsung'
    '60CF84' = 'ASUSTek';    '2CFDA1' = 'ASUSTek';    '1C872C' = 'ASUSTek'
    'DC91BF' = 'Amazon';     '44650D' = 'Amazon';     'FC65DE' = 'Amazon'
    'A83B76' = 'Brother';    '008077' = 'Brother';    '30055C' = 'Brother'
    'E8B2FE' = 'Sky';        '000A2F' = 'Sky'
    '6C999D' = 'Sonos';      '949F3E' = 'Sonos'
    'B827EB' = 'Raspberry Pi'; 'DCA632' = 'Raspberry Pi'; 'E45F01' = 'Raspberry Pi'
    '001788' = 'Philips Hue'; 'ECB5FA' = 'Philips Hue'
    '50C7BF' = 'TP-Link';    'C46E1F' = 'TP-Link';    '9C5322' = 'TP-Link'
    '001A11' = 'Google';     'F4F5D8' = 'Google';     '3C286D' = 'Google'
    '8C1645' = 'Xiaomi';     '286C07' = 'Xiaomi'
    '000C29' = 'VMware';     '005056' = 'VMware';     '080027' = 'VirtualBox'
    '00155D' = 'Hyper-V';    '525400' = 'QEMU/KVM'
    '001132' = 'Synology';   '0011D8' = 'ASUS';       '24050F' = 'AVM'
    '3CD92B' = 'HP';         '9457A5' = 'HP';         '001B78' = 'HP'
    '00034F' = 'Canon';      '2C9EFC' = 'Canon'
    '001E8F' = 'Canon';      '0026AB' = 'Seiko Epson'
    '001CC4' = 'HP';         '0017C8' = 'Kyocera'
    '74DA88' = 'TP-Link';    'B0BE76' = 'TP-Link'
    'D8D775' = 'Nintendo';   '0017AB' = 'Nintendo'
    '000D4B' = 'Roku';       'B83E59' = 'Roku'
    '001DD8' = 'Microsoft';  '7C1E52' = 'Microsoft'
    '18B430' = 'Nest';       '641666' = 'Nest'
    '000FEA' = 'Giga-Byte';  '1C1B0D' = 'Giga-Byte'
    '001E06' = 'WIBRAIN';    '000E58' = 'Sonos'
}

function Get-MacHersteller {
    param([string]$MAC)
    if (-not $MAC) { return '' }
    $oui = ($MAC -replace '[^0-9A-Fa-f]', '').ToUpper()
    if ($oui.Length -lt 6) { return '' }
    $treffer = $script:Hersteller[$oui.Substring(0, 6)]
    if ($treffer) { return $treffer }

    # Lokal administrierte Adressen: zweites Bit im ersten Byte gesetzt.
    # Solche Adressen vergeben Geraete selbst - typisch fuer Handys mit
    # zufaelliger MAC pro Netz.
    $erstes = [Convert]::ToInt32($oui.Substring(0, 2), 16)
    if ($erstes -band 2) { return 'zufällige Adresse' }
    ''
}

# Durchsucht das eigene Subnetz nach erreichbaren Geraeten.
# Alle Anfragen laufen gleichzeitig, sonst dauert ein /24-Netz eine Minute.
function Invoke-Netzscan {
    param(
        [string] $Netz,
        [int]    $TimeoutMs = 450
    )

    if (-not $Netz) {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
               Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
               Select-Object -First 1
        if (-not $cfg) { throw 'Keine aktive Netzwerkverbindung gefunden.' }
        $ip = $cfg.IPv4Address[0].IPAddress
        $Netz = ($ip -split '\.')[0..2] -join '.'
    }

    # Alle Adressen gleichzeitig anpingen
    $pings = @()
    foreach ($i in 1..254) {
        $p = New-Object System.Net.NetworkInformation.Ping
        $pings += [pscustomobject]@{
            IP   = "$Netz.$i"
            Ping = $p
            Task = $p.SendPingAsync("$Netz.$i", $TimeoutMs)
        }
    }
    try { [System.Threading.Tasks.Task]::WaitAll(($pings.Task), ($TimeoutMs + 1500)) | Out-Null } catch { }

    # ARP-Tabelle liefert die MAC-Adressen zu den Antwortenden
    $arp = @{}
    Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.State -notin @('Unreachable', 'Incomplete') } |
        ForEach-Object { $arp[$_.IPAddress] = $_.LinkLayerAddress }

    $eigeneIps = @()
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        ForEach-Object { $eigeneIps += $_.IPAddress }

    $gateways = @()
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.IPv4DefaultGateway) { $gateways += $_.IPv4DefaultGateway.NextHop }
    }

    # Erst feststellen, wer ueberhaupt da ist ...
    $treffer = @()
    foreach ($e in $pings) {
        $antwort = $null
        try { if ($e.Task.IsCompleted) { $antwort = $e.Task.Result } } catch { }
        $erreichbar = ($antwort -and $antwort.Status -eq 'Success')
        $mac = $arp[$e.IP]
        if (-not $erreichbar -and -not $mac) { try { $e.Ping.Dispose() } catch { }; continue }
        $treffer += [pscustomobject]@{
            IP = $e.IP; Erreichbar = $erreichbar; MAC = $mac
            Ms = $(if ($erreichbar) { [int]$antwort.RoundtripTime } else { $null })
        }
        try { $e.Ping.Dispose() } catch { }
    }

    # ... und dann alle Namen gleichzeitig aufloesen. Nacheinander dauert das
    # pro Geraet ohne PTR-Eintrag mehrere Sekunden und bestimmt die Gesamtzeit.
    $namen = @{}
    $dns = @{}
    foreach ($t in $treffer) {
        try { $dns[$t.IP] = [System.Net.Dns]::GetHostEntryAsync($t.IP) } catch { }
    }
    if ($dns.Count -gt 0) {
        try { [System.Threading.Tasks.Task]::WaitAll(([System.Threading.Tasks.Task[]]@($dns.Values)), 2500) | Out-Null } catch { }
        foreach ($ip in $dns.Keys) {
            try {
                if ($dns[$ip].Status -eq 'RanToCompletion') { $namen[$ip] = $dns[$ip].Result.HostName }
            } catch { }
        }
    }

    $gefunden = @()
    foreach ($e in $treffer) {
        $erreichbar = $e.Erreichbar
        $mac = $e.MAC

        $name = $namen[$e.IP]
        if (-not $name) { $name = '' }
        if ($name -match '^(.+?)\.') { $name = $Matches[1] }

        $rolle = ''
        if ($eigeneIps -contains $e.IP) { $rolle = 'dieser Rechner' }
        elseif ($gateways -contains $e.IP) { $rolle = 'Router' }

        $gefunden += [pscustomobject]@{
            IP         = $e.IP
            Sortier    = [int]($e.IP -split '\.')[3]
            Name       = $name
            MAC        = $mac
            Hersteller = (Get-MacHersteller -MAC $mac)
            Ms         = $e.Ms
            Erreichbar = $erreichbar
            Rolle      = $rolle
        }
    }

    [pscustomobject]@{
        Netz     = "$Netz.0/24"
        Gefunden = ($gefunden | Sort-Object Sortier)
        Anzahl   = $gefunden.Count
        Zeit     = (Get-Date).ToString('HH:mm:ss')
    }
}

# Der Weg ins Internet, Sprung fuer Sprung. Zeigt, ob die erste Station
# (der eigene Router) sauber antwortet und wo die Verzoegerung entsteht.
function Get-Wegverfolgung {
    param([string]$Ziel = '9.9.9.9', [int]$MaxSpruenge = 12)

    # Alle Sprungweiten gleichzeitig anfragen. Nacheinander wartet man bei
    # jedem stummen Zwischenstueck das volle Zeitlimit ab - bei zwoelf
    # Sprüngen sind das schnell zehn Sekunden.
    $daten = [System.Text.Encoding]::ASCII.GetBytes('netzpanel')
    $anfragen = @()
    foreach ($ttl in 1..$MaxSpruenge) {
        $p = New-Object System.Net.NetworkInformation.Ping
        $opt = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
        $anfragen += [pscustomobject]@{
            Ttl = $ttl; Ping = $p; Task = $p.SendPingAsync($Ziel, 1500, $daten, $opt)
        }
    }
    try { [System.Threading.Tasks.Task]::WaitAll(($anfragen.Task), 3000) | Out-Null } catch { }

    # Antworten einsammeln, danach die Namen wieder gemeinsam aufloesen
    $roh = @()
    foreach ($a in $anfragen) {
        $antwort = $null
        try { if ($a.Task.IsCompleted) { $antwort = $a.Task.Result } } catch { }
        $adresse = ''
        if ($antwort -and $antwort.Address) { $adresse = $antwort.Address.ToString() }
        $roh += [pscustomobject]@{
            Ttl     = $a.Ttl
            Adresse = $adresse
            Ms      = $(if ($antwort -and $antwort.Status -in @('Success','TtlExpired')) { [int]$antwort.RoundtripTime } else { $null })
            Ende    = ($antwort -and $antwort.Status -eq 'Success')
        }
        try { $a.Ping.Dispose() } catch { }
    }

    $dns = @{}
    foreach ($r in $roh) {
        if ($r.Adresse -and $r.Adresse -ne '0.0.0.0' -and -not $dns.ContainsKey($r.Adresse)) {
            try { $dns[$r.Adresse] = [System.Net.Dns]::GetHostEntryAsync($r.Adresse) } catch { }
        }
    }
    if ($dns.Count -gt 0) {
        try { [System.Threading.Tasks.Task]::WaitAll(([System.Threading.Tasks.Task[]]@($dns.Values)), 2000) | Out-Null } catch { }
    }
    $namen = @{}
    foreach ($ip in $dns.Keys) {
        try { if ($dns[$ip].Status -eq 'RanToCompletion') { $namen[$ip] = $dns[$ip].Result.HostName } } catch { }
    }

    $spruenge = @()
    foreach ($r in ($roh | Sort-Object Ttl)) {
        $hatAdresse = ($r.Adresse -and $r.Adresse -ne '0.0.0.0')
        $spruenge += [pscustomobject]@{
            Sprung = $r.Ttl
            IP     = $(if ($hatAdresse) { $r.Adresse } else { '*' })
            Name   = $(if ($hatAdresse -and $namen[$r.Adresse]) { $namen[$r.Adresse] } else { '' })
            Ms     = $r.Ms
            Privat = ($r.Adresse -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)')
        }
        # Hinter dem Ziel gibt es nichts mehr zu zeigen
        if ($r.Ende) { break }
    }
    $spruenge
}

# Misst Antwortzeit und Schwankung zu mehreren Zielen im Internet.
# Die Schwankung sagt mehr ueber die Guete der Leitung aus als der Mittelwert.
function Measure-Internetguete {
    param([int]$Anzahl = 8)

    $ziele = [ordered]@{
        'Quad9'      = '9.9.9.9'
        'Cloudflare' = '1.1.1.1'
        'Google'     = '8.8.8.8'
    }

    $erg = @()
    foreach ($name in $ziele.Keys) {
        $werte = @()
        $ping = New-Object System.Net.NetworkInformation.Ping
        for ($i = 0; $i -lt $Anzahl; $i++) {
            try {
                $a = $ping.Send($ziele[$name], 1500)
                if ($a.Status -eq 'Success') { $werte += [int]$a.RoundtripTime }
            } catch { }
        }
        $verlust = [math]::Round((1 - ($werte.Count / $Anzahl)) * 100)

        $min = $null; $schnitt = $null; $max = $null; $jitter = $null
        if ($werte.Count -gt 0) {
            $st = $werte | Measure-Object -Minimum -Maximum -Average
            $min = $st.Minimum; $max = $st.Maximum
            $schnitt = [math]::Round($st.Average, 1)
            if ($werte.Count -gt 1) {
                $d = @()
                for ($i = 1; $i -lt $werte.Count; $i++) { $d += [Math]::Abs($werte[$i] - $werte[$i-1]) }
                $jitter = [math]::Round(($d | Measure-Object -Average).Average, 1)
            } else { $jitter = 0 }
        }

        $erg += [pscustomobject]@{
            Ziel = $name; IP = $ziele[$name]
            Min = $min; Schnitt = $schnitt; Max = $max; Jitter = $jitter
            VerlustProzent = $verlust
        }
    }
    $erg
}

# Was horcht auf diesem Rechner nach aussen? Jeder Eintrag ist eine Tuer,
# die im Netz offensteht.
function Get-OffeneDienste {
    $erg = @()
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in @('0.0.0.0', '::') } |
        ForEach-Object {
            $prozess = ''
            try { $prozess = (Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName } catch { }
            $erg += [pscustomobject]@{ Port = $_.LocalPort; Prozess = $prozess }
        }

    $bekannt = @{
        135='Windows-RPC'; 139='NetBIOS'; 445='Dateifreigabe (SMB)'; 3389='Remotedesktop'
        22='SSH'; 80='Webserver'; 443='Webserver (TLS)'; 5357='Netzwerkerkennung'
        1900='UPnP'; 5040='Windows-Verbindungsdienst'; 7680='Windows-Übermittlungsoptimierung'
        8080='Webserver (alternativ)'; 3306='MySQL'; 5432='PostgreSQL'; 6379='Redis'
        27017='MongoDB'; 9100='Druckdienst'
    }
    $riskant = @(135, 139, 445, 3389, 5357, 1900)

    $erg | Sort-Object Port -Unique | ForEach-Object {
        [pscustomobject]@{
            Port      = $_.Port
            Prozess   = $_.Prozess
            Dienst    = $bekannt[[int]$_.Port]
            Beachten  = ($riskant -contains [int]$_.Port)
        }
    }
}

# Fasst zusammen, was der Rechner selbst ueber seine Anbindung weiss.
function Get-EigeneAnbindung {
    $erg = @()
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $ad = $_
        $cfg = Get-NetIPConfiguration -InterfaceIndex $ad.ifIndex -ErrorAction SilentlyContinue
        $ip = '-'; $gw = '-'; $dns = @()
        if ($cfg) {
            if ($cfg.IPv4Address)        { $ip  = $cfg.IPv4Address[0].IPAddress }
            if ($cfg.IPv4DefaultGateway) { $gw  = $cfg.IPv4DefaultGateway.NextHop }
            if ($cfg.DNSServer)          { $dns = @($cfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) }
        }

        # Kann die Karte mehr, als sie gerade aushandelt?
        $kannMehr = ''
        if ($ad.InterfaceDescription -match 'I226|I225|AQC10|2\.5G' -and $ad.LinkSpeed -eq '1 Gbps') {
            $kannMehr = '2,5 Gbit/s'
        }
        if ($ad.InterfaceDescription -match 'X550|10G' -and $ad.LinkSpeed -match '1 Gbps') {
            $kannMehr = '10 Gbit/s'
        }

        $erg += [pscustomobject]@{
            Name      = $ad.Name
            Karte     = $ad.InterfaceDescription
            LinkSpeed = $ad.LinkSpeed
            MAC       = $ad.MacAddress
            IP        = $ip
            Gateway   = $gw
            Dns       = $dns
            KannMehr  = $kannMehr
        }
    }
    $erg
}
