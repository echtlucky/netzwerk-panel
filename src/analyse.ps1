# analyse.ps1
# Bewertet das Netz und rechnet Umbauten durch, bevor man sie macht.
#
# Grundlage ist das Sendezeit-Modell (Airtime): Alle Geraete eines Funkbandes
# teilen sich dasselbe Medium. Fuer dieselbe Datenmenge braucht ein Geraet mit
# 144 Mbit/s sechsmal so lange wie eines mit 866 Mbit/s - und blockiert das Band
# waehrenddessen fuer alle anderen. Deshalb bremst ein einziges langsames Geraet
# das gesamte Band.
#
# Der nutzbare Gesamtdurchsatz eines Bandes bei gleichmaessiger Auslastung ist
# das harmonische Mittel der Einzelraten, multipliziert mit der Geraetezahl:
#
#     gesamt = n / summe(1 / rate_i)
#
# Alle Werte hier sind Modellrechnungen aus den gemessenen Aushandlungsraten,
# keine Messungen. Sie zeigen Groessenordnungen und Rangfolgen zuverlaessig -
# nicht die exakte Geschwindigkeit im Einzelfall.

# Hilfsfunktion: liefert immer eine Zeichenkette, nie $null.
# PowerShell 5.1 kennt den ??-Operator nicht.
function Txt { param($Wert) if ($null -eq $Wert) { '' } else { [string]$Wert } }

# ============================================================ Sendezeit

function Get-AirtimeAnalyse {
    param(
        [Parameter(Mandatory)] $FunkClients,
        $Geraete
    )

    $namen = @{}
    foreach ($g in @($Geraete)) {
        if ($g.MAC) { $namen[$g.MAC.ToUpper()] = $g.Name }
    }

    $baender = @{}
    foreach ($c in @($FunkClients)) {
        $rate = [double]$c.SpeedMbit
        if ($rate -le 0) { continue }
        if (-not $baender.ContainsKey($c.Band)) { $baender[$c.Band] = @() }
        $baender[$c.Band] += [pscustomobject]@{
            Band   = $c.Band
            MAC    = $c.MAC
            IP     = $c.IP
            Name   = $namen[(Txt $c.MAC).ToUpper()]
            Rate   = $rate
            Signal = [int]$c.Signal
        }
    }

    $ergebnis = @()
    foreach ($band in $baender.Keys) {
        $liste = $baender[$band]
        $n = $liste.Count
        if ($n -eq 0) { continue }

        # Sendezeitbedarf je Geraet fuer dieselbe Datenmenge: 1 / Rate
        $summeKehrwerte = 0.0
        foreach ($g in $liste) { $summeKehrwerte += (1.0 / $g.Rate) }

        $nutzbar     = $n / $summeKehrwerte          # harmonisches Mittel * n
        $proGeraet   = $nutzbar / $n
        $bestenfalls = ($liste | Measure-Object -Property Rate -Maximum).Maximum

        $mitAnteil = @()
        foreach ($g in $liste) {
            $anteil = ((1.0 / $g.Rate) / $summeKehrwerte) * 100
            $fair   = 100.0 / $n
            $mitAnteil += [pscustomobject]@{
                Name          = $g.Name
                IP            = $g.IP
                MAC           = $g.MAC
                Rate          = [math]::Round($g.Rate)
                Signal        = $g.Signal
                AirtimeAnteil = [math]::Round($anteil, 1)
                FairAnteil    = [math]::Round($fair, 1)
                # Faktor > 1 heisst: dieses Geraet verbraucht mehr Sendezeit,
                # als ihm bei gleicher Datenmenge zustuende.
                Last          = [math]::Round($anteil / $fair, 2)
            }
        }
        $mitAnteil = $mitAnteil | Sort-Object AirtimeAnteil -Descending

        # Was braechte es, das langsamste Geraet aus dem Band zu nehmen?
        $ohneBremse = $null
        $bremse = $mitAnteil[0]
        if ($n -gt 1) {
            $rest = 0.0
            foreach ($g in $liste) { if ($g.MAC -ne $bremse.MAC) { $rest += (1.0 / $g.Rate) } }
            $ohneBremse = [math]::Round((($n - 1) / $rest), 0)
        }

        $ergebnis += [pscustomobject]@{
            Band          = $band
            Anzahl        = $n
            NutzbarMbit   = [math]::Round($nutzbar)
            ProGeraetMbit = [math]::Round($proGeraet)
            SchnellstMbit = [math]::Round($bestenfalls)
            # Wie viel Leistung geht durch das Zusammenspiel verloren?
            VerlustProzent = [math]::Round((1 - ($nutzbar / ($bestenfalls * 1.0))) * 100)
            Bremse        = $bremse
            OhneBremseMbit = $ohneBremse
            Geraete       = $mitAnteil
        }
    }

    $ergebnis | Sort-Object Anzahl -Descending
}

# ============================================================ Simulation

# Schaetzt, welche Rate ein Geraet nach einem Bandwechsel aushandeln wuerde.
# 5 GHz traegt deutlich mehr Daten, reicht aber weniger weit - das Signal faellt.
function Get-GeschaetzteRate {
    param(
        [Parameter(Mandatory)][string] $VonBand,
        [Parameter(Mandatory)][string] $NachBand,
        [Parameter(Mandatory)][double] $Rate,
        [int] $Signal = 60
    )

    if ($VonBand -eq $NachBand) { return [pscustomobject]@{ Rate = $Rate; Signal = $Signal } }

    $ist24  = $VonBand  -match '2,4|2\.4'
    $soll24 = $NachBand -match '2,4|2\.4'

    if ($ist24 -and -not $soll24) {
        # 2,4 -> 5 GHz: mehr Kanalbreite, aber hoehere Daempfung durch Waende.
        $neuesSignal = [Math]::Max(5, $Signal - 15)
        $faktor = 4.0 * ($neuesSignal / [Math]::Max($Signal, 1))
        $faktor = [Math]::Max(1.0, [Math]::Min($faktor, 6.0))
        return [pscustomobject]@{
            Rate   = [math]::Round([Math]::Min($Rate * $faktor, 1200))
            Signal = $neuesSignal
        }
    }
    if (-not $ist24 -and $soll24) {
        # 5 -> 2,4 GHz: stabiler und weiter, aber deutlich langsamer.
        $neuesSignal = [Math]::Min(100, $Signal + 15)
        return [pscustomobject]@{
            Rate   = [math]::Round([Math]::Min($Rate / 3.5, 300))
            Signal = $neuesSignal
        }
    }
    [pscustomobject]@{ Rate = $Rate; Signal = $Signal }
}

# Rechnet ein Szenario durch und liefert Vorher/Nachher je Band.
#
# Szenarien:
#   kabel      - Geraet (MAC) verlaesst das Funknetz und haengt am Kabel
#   bandwechse - Geraet (MAC) wechselt in ein anderes Band (Ziel)
#   entfernen  - Geraet (MAC) wird abgeschaltet
#   signal     - Geraet (MAC) bekommt besseres Signal (Ziel = neuer Prozentwert),
#                etwa durch einen naeher stehenden Repeater
function Invoke-Simulation {
    param(
        [Parameter(Mandatory)] $FunkClients,
        $Geraete,
        [Parameter(Mandatory)][string] $Szenario,
        [string] $MAC,
        [string] $Ziel
    )

    $vorher = Get-AirtimeAnalyse -FunkClients $FunkClients -Geraete $Geraete

    # Kopie der Clientliste anlegen und darauf das Szenario anwenden
    $neu = @()
    $betroffen = $null
    foreach ($c in @($FunkClients)) {
        $treffer = ($MAC -and $c.MAC -and ($c.MAC.ToUpper() -eq $MAC.ToUpper()))
        if ($treffer) { $betroffen = $c }

        switch ($Szenario) {
            'kabel' {
                if ($treffer) { continue }
                $neu += $c
            }
            'entfernen' {
                if ($treffer) { continue }
                $neu += $c
            }
            'bandwechsel' {
                if ($treffer) {
                    $s = Get-GeschaetzteRate -VonBand $c.Band -NachBand $Ziel `
                                             -Rate ([double]$c.SpeedMbit) -Signal ([int]$c.Signal)
                    $neu += [pscustomobject]@{
                        Band = $Ziel; BandIndex = $c.BandIndex; MAC = $c.MAC; IP = $c.IP
                        Angemeldet = $c.Angemeldet; SpeedMbit = $s.Rate; Signal = $s.Signal
                    }
                } else { $neu += $c }
            }
            'signal' {
                if ($treffer) {
                    $altSignal = [Math]::Max([int]$c.Signal, 1)
                    $neuSignal = [Math]::Max(1, [Math]::Min(100, [int]$Ziel))
                    # Rate waechst ungefaehr proportional zum Signal, mit Deckel
                    $faktor = [Math]::Min($neuSignal / $altSignal, 4.0)
                    $obergrenze = if ($c.Band -match '2,4|2\.4') { 300 } else { 1200 }
                    $neu += [pscustomobject]@{
                        Band = $c.Band; BandIndex = $c.BandIndex; MAC = $c.MAC; IP = $c.IP
                        Angemeldet = $c.Angemeldet
                        SpeedMbit = [math]::Round([Math]::Min([double]$c.SpeedMbit * $faktor, $obergrenze))
                        Signal = $neuSignal
                    }
                } else { $neu += $c }
            }
            default { $neu += $c }
        }
    }

    $nachher = Get-AirtimeAnalyse -FunkClients $neu -Geraete $Geraete

    # Bandweiser Vergleich
    $vergleich = @()
    $alleBaender = @()
    foreach ($b in $vorher) { if ($alleBaender -notcontains $b.Band) { $alleBaender += $b.Band } }
    foreach ($b in $nachher) { if ($alleBaender -notcontains $b.Band) { $alleBaender += $b.Band } }

    foreach ($band in $alleBaender) {
        $v = $vorher  | Where-Object { $_.Band -eq $band } | Select-Object -First 1
        $n = $nachher | Where-Object { $_.Band -eq $band } | Select-Object -First 1
        $vWert = if ($v) { $v.NutzbarMbit } else { 0 }
        $nWert = if ($n) { $n.NutzbarMbit } else { 0 }
        $vPro  = if ($v) { $v.ProGeraetMbit } else { 0 }
        $nPro  = if ($n) { $n.ProGeraetMbit } else { 0 }
        $vergleich += [pscustomobject]@{
            Band           = $band
            VorherMbit     = $vWert
            NachherMbit    = $nWert
            AenderungMbit  = $nWert - $vWert
            AenderungProz  = if ($vWert -gt 0) { [math]::Round((($nWert - $vWert) / $vWert) * 100) } else { 0 }
            VorherAnzahl   = if ($v) { $v.Anzahl } else { 0 }
            NachherAnzahl  = if ($n) { $n.Anzahl } else { 0 }
            VorherProGeraet  = $vPro
            NachherProGeraet = $nPro
        }
    }

    $name = if ($betroffen) { $betroffen.IP } else { $MAC }
    foreach ($g in @($Geraete)) {
        if ($g.MAC -and $MAC -and $g.MAC.ToUpper() -eq $MAC.ToUpper() -and $g.Name) { $name = $g.Name }
    }

    # Was passiert mit dem umgestellten Geraet selbst? Ohne diese Sicht wirkt
    # ein Bandwechsel wie eine Verschlechterung, obwohl das Geraet schneller wird.
    $gVorher = $null
    $gNachher = $null
    if ($betroffen) {
        $gVorher = [pscustomobject]@{
            Band = $betroffen.Band; Rate = [math]::Round([double]$betroffen.SpeedMbit); Signal = [int]$betroffen.Signal
        }
    }
    foreach ($c in $neu) {
        if ($MAC -and $c.MAC -and $c.MAC.ToUpper() -eq $MAC.ToUpper()) {
            $gNachher = [pscustomobject]@{
                Band = $c.Band; Rate = [math]::Round([double]$c.SpeedMbit); Signal = [int]$c.Signal
            }
        }
    }
    if ($Szenario -eq 'kabel')     { $gNachher = [pscustomobject]@{ Band = 'Kabel'; Rate = 1000; Signal = 100 } }
    if ($Szenario -eq 'entfernen') { $gNachher = $null }

    # Gesamtbilanz - die ehrliche Antwort auf "bringt das was?".
    # Ausgedrueckt als Rate, die im Mittel auf ein Funkgeraet entfaellt: eine
    # blosse Summe der Bandkapazitaeten waere irrefuehrend, weil ein fast leeres
    # Band eine hohe Kapazitaet ausweist, die niemand nutzt.
    $summeVorher  = 0; $summeNachher = 0
    $anzVorher    = 0; $anzNachher   = 0
    foreach ($v in $vergleich) {
        $summeVorher  += $v.VorherMbit;   $summeNachher += $v.NachherMbit
        $anzVorher    += $v.VorherAnzahl; $anzNachher   += $v.NachherAnzahl
    }
    $mittelVorher  = if ($anzVorher  -gt 0) { [math]::Round($summeVorher  / $anzVorher)  } else { 0 }
    $mittelNachher = if ($anzNachher -gt 0) { [math]::Round($summeNachher / $anzNachher) } else { 0 }
    $gesamtProz = 0
    if ($mittelVorher -gt 0) { $gesamtProz = [math]::Round((($mittelNachher - $mittelVorher) / $mittelVorher) * 100) }

    [pscustomobject]@{
        Szenario   = $Szenario
        Ziel       = $Ziel
        Geraet     = $name
        MAC        = $MAC
        Beschreibung = (Get-SzenarioText -Szenario $Szenario -Geraet $name -Ziel $Ziel)
        Vorher     = $vorher
        Nachher    = $nachher
        Vergleich  = $vergleich
        GeraetVorher  = $gVorher
        GeraetNachher = $gNachher
        Gesamt     = [pscustomobject]@{
            VorherMbit        = $summeVorher
            NachherMbit       = $summeNachher
            MittelVorherMbit  = $mittelVorher
            MittelNachherMbit = $mittelNachher
            AenderungProz     = $gesamtProz
        }
    }
}

function Get-SzenarioText {
    param([string]$Szenario, [string]$Geraet, [string]$Ziel)
    switch ($Szenario) {
        'kabel'       { "$Geraet per Netzwerkkabel anschließen" }
        'entfernen'   { "$Geraet abschalten oder aus dem Netz nehmen" }
        'bandwechsel' { "$Geraet in das $Ziel-Netz umziehen" }
        'signal'      { "$Geraet auf $Ziel % Signal bringen, etwa durch einen näher stehenden Repeater" }
        default       { "Unbekanntes Szenario" }
    }
}

# Schlaegt von sich aus die Umbauten vor, die am meisten braechten.
# Jeder Vorschlag wird durchgerechnet, sortiert wird nach tatsaechlichem Gewinn.
function Get-Optimierungsvorschlaege {
    param(
        [Parameter(Mandatory)] $FunkClients,
        $Geraete,
        $Mesh,
        [int] $Hoechstens = 6
    )

    $vorschlaege = @()
    $clients = @($FunkClients)
    if ($clients.Count -eq 0) { return $vorschlaege }

    $namen = @{}
    foreach ($g in @($Geraete)) { if ($g.MAC) { $namen[$g.MAC.ToUpper()] = $g.Name } }
    $nameVon = { param($mac) $n = $namen[(Txt $mac).ToUpper()]; if ($n) { $n } else { $mac } }

    # Die Namen der Mesh-Knoten - Repeater behandeln wir gesondert.
    $meshMacs = @()
    if ($Mesh -and $Mesh.Knoten) { foreach ($k in $Mesh.Knoten) { if ($k.MAC) { $meshMacs += $k.MAC.ToUpper() } } }

    # 1. Die langsamsten Geraete je Band ans Kabel holen
    $proBand = $clients | Group-Object Band
    foreach ($gruppe in $proBand) {
        if ($gruppe.Count -lt 2) { continue }
        $langsam = $gruppe.Group | Sort-Object { [double]$_.SpeedMbit } | Select-Object -First 1
        $sim = Invoke-Simulation -FunkClients $clients -Geraete $Geraete -Szenario 'kabel' -MAC $langsam.MAC
        $v = $sim.Vergleich | Where-Object { $_.Band -eq $gruppe.Name } | Select-Object -First 1
        if ($v -and $v.AenderungProz -ge 10) {
            $istRepeater = $meshMacs -contains (Txt $langsam.MAC).ToUpper()
            $vorschlaege += [pscustomobject]@{
                Art      = 'kabel'
                MAC      = $langsam.MAC
                Ziel     = ''
                Titel    = (& $nameVon $langsam.MAC) + ' ans Netzwerkkabel'
                Text     = "Mit $([math]::Round([double]$langsam.SpeedMbit)) Mbit/s ist das Gerät der langsamste Teilnehmer im $($gruppe.Name)-Netz und belegt dadurch $($sim.Vorher | Where-Object { $_.Band -eq $gruppe.Name } | ForEach-Object { $_.Bremse.AirtimeAnteil }) % der Sendezeit." +
                           $(if ($istRepeater) { " Es ist ein Repeater — ein Kabel zum Router entlastet zusätzlich alle Geräte dahinter." } else { "" })
                Gewinn   = $v.AenderungProz
                GewinnMbit = $v.AenderungMbit
                Band     = $gruppe.Name
            }
        }
    }

    # 2. Geraete aus dem 2,4-GHz-Netz ins 5-GHz-Netz umziehen
    $zweiVier = $clients | Where-Object { $_.Band -match '2,4|2\.4' }
    foreach ($c in $zweiVier) {
        if ([int]$c.Signal -lt 45) { continue }   # zu schwach, 5 GHz wuerde abreissen
        $sim = Invoke-Simulation -FunkClients $clients -Geraete $Geraete `
                                 -Szenario 'bandwechsel' -MAC $c.MAC -Ziel '5 GHz'
        if ($sim.Gesamt.MittelVorherMbit -le 0) { continue }
        $proz = $sim.Gesamt.AenderungProz
        $gesamtVorher  = $sim.Gesamt.MittelVorherMbit
        $gesamtNachher = $sim.Gesamt.MittelNachherMbit
        if ($proz -ge 8) {
            $vorschlaege += [pscustomobject]@{
                Art     = 'bandwechsel'
                MAC     = $c.MAC
                Ziel    = '5 GHz'
                Titel   = (& $nameVon $c.MAC) + ' ins 5-GHz-Netz holen'
                Text    = "Das Gerät funkt mit $([math]::Round([double]$c.SpeedMbit)) Mbit/s im 2,4-GHz-Netz bei $([int]$c.Signal) % Signal. Im 5-GHz-Netz wäre deutlich mehr möglich, und das langsamere Band wird frei."
                Gewinn  = $proz
                GewinnMbit = $gesamtNachher - $gesamtVorher
                Band    = $c.Band
            }
        }
    }

    # 3. Geraete mit schwachem Signal: naeher stehender Repeater
    foreach ($c in $clients) {
        if ([int]$c.Signal -ge 45) { continue }
        $sim = Invoke-Simulation -FunkClients $clients -Geraete $Geraete `
                                 -Szenario 'signal' -MAC $c.MAC -Ziel '75'
        $v = $sim.Vergleich | Where-Object { $_.Band -eq $c.Band } | Select-Object -First 1
        if ($v -and $v.AenderungProz -ge 10) {
            $vorschlaege += [pscustomobject]@{
                Art     = 'signal'
                MAC     = $c.MAC
                Ziel    = '75'
                Titel   = 'Besseres Signal für ' + (& $nameVon $c.MAC)
                Text    = "Nur $([int]$c.Signal) % Signal. Ein Repeater in der Nähe oder ein besserer Standort würde die Aushandlungsrate anheben — und damit die Sendezeit freigeben, die das Gerät heute allen anderen wegnimmt."
                Gewinn  = $v.AenderungProz
                GewinnMbit = $v.AenderungMbit
                Band    = $c.Band
            }
        }
    }

    # Doppelte Vorschlaege zum selben Geraet: nur den wirksamsten behalten
    $gesehen = @{}
    $sortiert = $vorschlaege | Sort-Object Gewinn -Descending
    $ergebnis = @()
    foreach ($v in $sortiert) {
        $s = (Txt $v.MAC) + '|' + $v.Art
        if ($gesehen[$s]) { continue }
        $gesehen[$s] = $true
        $ergebnis += $v
        if ($ergebnis.Count -ge $Hoechstens) { break }
    }
    $ergebnis
}

# ======================================================== Mobilgeraete

# Sucht Handys und Tablets heraus und prueft, was ihrer Verbindung im Weg steht.
function Get-MobilAnalyse {
    param($Geraete, $FunkClients, $Netze)

    $hinweise = @{
        Apple   = 'Apple'
        Samsung = 'Samsung'
        Google  = 'Google'
        Xiaomi  = 'Xiaomi'
        OnePlus = 'OnePlus'
        Huawei  = 'Huawei'
    }

    $mobil = @()
    foreach ($g in @($Geraete)) {
        $text = ((Txt $g.Name) + ' ' + (Txt $g.Modell) + ' ' + (Txt $g.Hersteller)).ToLower()
        $istMobil = $text -match 'iphone|ipad|handy|phone|galaxy|pixel|tablet|mobil|xiaomi|oneplus|huawei'
        if (-not $istMobil) { continue }

        $c = $null
        foreach ($k in @($FunkClients)) {
            if ($k.MAC -and $g.MAC -and $k.MAC.ToUpper() -eq $g.MAC.ToUpper()) { $c = $k; break }
        }

        $punkte = @()
        if (-not $c) {
            if ($g.Aktiv -and $g.Art -eq 'Ethernet') {
                $punkte += [pscustomobject]@{ Stufe='gut'; Text='Hängt am Kabel — schneller geht es nicht.' }
            } else {
                $punkte += [pscustomobject]@{ Stufe='info'; Text='Gerade nicht im Funknetz angemeldet.' }
            }
        } else {
            if ($c.Band -match '2,4|2\.4') {
                $punkte += [pscustomobject]@{ Stufe='warn'
                    Text='Funkt im 2,4-GHz-Netz. Das ist das langsame, überfüllte Band. Bei mindestens 45 % Signal gehört das Gerät ins 5-GHz-Netz.' }
            } else {
                $punkte += [pscustomobject]@{ Stufe='gut'; Text="Funkt im $($c.Band)-Netz — richtig so." }
            }
            if ([int]$c.Signal -lt 40) {
                $punkte += [pscustomobject]@{ Stufe='warn'
                    Text="Nur $([int]$c.Signal) % Signal. Unter 40 % bricht die Rate stark ein und das Gerät belegt viel Sendezeit." }
            } elseif ([int]$c.Signal -lt 60) {
                $punkte += [pscustomobject]@{ Stufe='info'; Text="$([int]$c.Signal) % Signal — brauchbar, aber mit wenig Reserve." }
            } else {
                $punkte += [pscustomobject]@{ Stufe='gut'; Text="$([int]$c.Signal) % Signal — sehr gut." }
            }
            if ($c.Band -match 'Gast') {
                $punkte += [pscustomobject]@{ Stufe='warn'
                    Text='Hängt im Gastnetz. Von dort ist kein Zugriff auf Drucker, Dateifreigaben oder andere Geräte im Haus möglich.' }
            }
        }

        $mobil += [pscustomobject]@{
            Name    = $g.Name
            IP      = $g.IP
            MAC     = $g.MAC
            Aktiv   = $g.Aktiv
            Band    = if ($c) { $c.Band } else { '' }
            Rate    = if ($c) { [math]::Round([double]$c.SpeedMbit) } else { 0 }
            Signal  = if ($c) { [int]$c.Signal } else { 0 }
            Punkte  = $punkte
        }
    }

    # Allgemeine Einstellungen, die jedem Mobilgeraet helfen
    $allgemein = @()
    $hat24 = $false; $hat5 = $false; $gleicherName = $false
    $n24 = $null; $n5 = $null
    foreach ($n in @($Netze)) {
        if ($n.Band -match '2,4|2\.4') { $hat24 = $n.An; $n24 = $n }
        if ($n.Band -eq '5 GHz')       { $hat5  = $n.An; $n5  = $n }
    }
    if ($n24 -and $n5 -and $n24.SSID -eq $n5.SSID) { $gleicherName = $true }

    if ($hat24 -and $hat5 -and $gleicherName) {
        $allgemein += [pscustomobject]@{ Stufe='gut'
            Titel='Beide Bänder heißen gleich'
            Text='Damit kann die Box ein Gerät selbst ins passende Band schieben (Band Steering). Das ist die richtige Einstellung.' }
    } elseif ($hat24 -and $hat5 -and -not $gleicherName) {
        $allgemein += [pscustomobject]@{ Stufe='warn'
            Titel='Bänder haben verschiedene Namen'
            Text='Solange 2,4 und 5 GHz unterschiedlich heißen, kann die Box Geräte nicht selbst umschieben. Gleiche Namen vergeben und das Handy neu verbinden lassen.' }
    }
    if ($n5 -and $n5.An -and $n5.Kanal) {
        $kanal = [int]$n5.Kanal
        if ($kanal -ge 52 -and $kanal -le 144) {
            $allgemein += [pscustomobject]@{ Stufe='info'
                Titel="5-GHz-Netz auf Kanal $kanal"
                Text='Das ist ein Wetterradar-Kanal. Erkennt die Box ein Radarsignal, muss sie den Kanal sofort wechseln — die Verbindung reißt für ein bis zwei Minuten ab. Kanäle 36 bis 48 sind davon frei.' }
        }
    }
    if ($hat24 -and $n24.Kanal) {
        $k = [int]$n24.Kanal
        if ($k -ne 1 -and $k -ne 6 -and $k -ne 11) {
            $allgemein += [pscustomobject]@{ Stufe='info'
                Titel="2,4-GHz-Netz auf Kanal $k"
                Text='Im 2,4-GHz-Band überlappen sich benachbarte Kanäle. Nur 1, 6 und 11 stören einander nicht.' }
        }
    }

    [pscustomobject]@{ Geraete = $mobil; Allgemein = $allgemein }
}
