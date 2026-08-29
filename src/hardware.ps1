# hardware.ps1
# Geraetedatenbank und Kaufberatung.
#
# Die Daten stehen in data/hardware.json und lassen sich dort pflegen, ohne
# den Programmcode anzufassen. Die Empfehlungen entstehen aus dem Vergleich
# der Datenbank mit dem, was im Netz tatsaechlich gemessen wurde - nicht aus
# einer festen Rangliste.

function Get-HardwareDaten {
    $pfad = Join-Path (Split-Path $PSScriptRoot -Parent) 'data\hardware.json'
    if (-not (Test-Path $pfad)) { throw "Gerätedatenbank nicht gefunden: $pfad" }
    Get-Content $pfad -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Erkennt anhand des Modellnamens, ob ein Geraet in der Datenbank veraltet ist,
# und liefert den vorgesehenen Nachfolger.
# Modellnamen vergleichbar machen. Die Box meldet "FRITZ!WLAN Repeater 1750E",
# im Handel und in der Datenbank heisst dasselbe Geraet "FRITZ!Repeater 1750E".
# Ohne Normalisierung findet kein Vergleich die beiden zusammen.
function ConvertTo-Modellschluessel {
    param([string]$Name)
    if (-not $Name) { return '' }
    (($Name -replace '[^a-zA-Z0-9]', '') -replace '(?i)wlan', '').ToLower()
}

# Sucht das Geraet selbst in der Datenbank, um seinen Stand zu beurteilen.
function Get-GeraetInDb {
    param([string]$Modell, $Daten)
    if (-not $Modell) { return $null }
    $suche = ConvertTo-Modellschluessel -Name $Modell
    foreach ($g in $Daten.geraete) {
        $kandidat = ConvertTo-Modellschluessel -Name $g.name
        if (-not $kandidat) { continue }
        if ($suche -eq $kandidat -or $suche -like "*$kandidat*" -or $kandidat -like "*$suche*") { return $g }
    }
    $null
}

function Get-Nachfolger {
    param([string]$Modell, $Daten)
    if (-not $Modell) { return $null }
    $suche = ConvertTo-Modellschluessel -Name $Modell
    foreach ($g in $Daten.geraete) {
        foreach ($alt in @($g.ersetzt)) {
            if (-not $alt) { continue }
            $k = ConvertTo-Modellschluessel -Name $alt
            if ($k -and ($suche -eq $k -or $suche -like "*$k*")) { return $g }
        }
    }
    $null
}

function Get-HardwareEmpfehlungen {
    param(
        $Mesh,
        $FunkClients,
        $Geraete,
        $Wan,
        $LokaleAdapter,
        $Netze
    )

    $daten = Get-HardwareDaten
    $vorschlaege = @()

    $finde = {
        param($id)
        foreach ($g in $daten.geraete) { if ($g.id -eq $id) { return $g } }
        $null
    }

    # ---------------------------------------------------------- 1. Switch
    # Die haeufigste ungenutzte Reserve: Netzwerkkarte kann 2,5 Gbit/s,
    # der Router nur 1 Gbit/s.
    $karteKann25 = $false
    foreach ($a in @($LokaleAdapter)) {
        if (($a.Karte -match 'I226|I225|2\.5G|2\.5 G|AQC10') -and ($a.LinkSpeed -eq '1 Gbps')) {
            $karteKann25 = $true
        }
    }
    if ($karteKann25) {
        $g = & $finde 'sw-25g-8'
        $vorschlaege += [pscustomobject]@{
            Rang    = 1
            Anlass  = 'Deine Netzwerkkarte läuft unter ihrem Können'
            Grund   = 'Die Karte im PC beherrscht 2,5 Gbit/s, verhandelt aber 1 Gbit/s — weil die FRITZ!Box nur Gigabit-Anschlüsse hat. Ein Switch dazwischen hebt die Grenze für alles auf, was am Kabel hängt.'
            Wirkung = 'Dateiübertragung im Haus rund 2,5-mal schneller. Am Internetzugang ändert sich nichts.'
            Geraet  = $g
        }
    }

    # ------------------------------------------------- 2. Alte Mesh-Knoten
    # Der Router wird weiter unten gesondert behandelt, sonst steht er doppelt da.
    foreach ($k in @($Mesh.Knoten)) {
        if ($k.Rolle -eq 'master') { continue }
        $nachfolger = Get-Nachfolger -Modell $k.Modell -Daten $daten
        if (-not $nachfolger) { continue }

        $selbst = Get-GeraetInDb -Modell $k.Modell -Daten $daten
        $istAlt = $false
        if ($selbst) { $istAlt = ($selbst.veraltet -eq $true -or $selbst.wlan -eq 'Wi-Fi 5') }

        # Wie ist dieser Knoten angebunden?
        $strecke = $null
        foreach ($v in @($Mesh.Verbindungen)) {
            if ($v.Von -eq $k.Name -or $v.Nach -eq $k.Name) { $strecke = $v; break }
        }
        $perFunk = ($strecke -and $strecke.Art -eq 'WLAN')
        $rate = if ($strecke) { [Math]::Max($strecke.MaxRx, $strecke.MaxTx) } else { 0 }

        $altStandard = if ($selbst) { $selbst.wlan } else { 'die verbaute Technik' }
        $altJahr     = if ($selbst) { $selbst.jahr } else { $null }

        $wirkung = "Ersetzt $altStandard durch $($nachfolger.wlan). Geräte, die sich mit diesem Knoten verbinden, sind nicht mehr auf den alten Stand begrenzt."
        if ($perFunk -and $rate -gt 0) {
            $wirkung += " Die Funkstrecke zum Router liegt heute bei $rate Mbit/s."
        }

        if ($istAlt) {
            $grund = "$($k.Modell)"
            if ($altJahr) { $grund += " stammt aus $altJahr und" }
            $grund += " funkt mit $altStandard. Jedes Gerät, das sich damit verbindet, wird auf diesen Stand gebremst."
            $vorschlaege += [pscustomobject]@{
                Rang    = 2
                Anlass  = "$($k.Name) ist veraltet"
                Grund   = $grund
                Wirkung = $wirkung
                Geraet  = $nachfolger
            }
        } else {
            $vorschlaege += [pscustomobject]@{
                Rang    = 5
                Anlass  = "$($k.Name) hat einen Nachfolger — dringend ist das nicht"
                Grund   = "$($k.Modell) mit $altStandard ist weiterhin ein gutes Gerät. Ein Wechsel lohnt nur, wenn im Haus ohnehin auf $($nachfolger.wlan) umgestellt wird."
                Wirkung = $wirkung
                Geraet  = $nachfolger
            }
        }
    }

    # ------------------------------------- 3. Repeater mit Funk-Anbindung
    # Ein Repeater kann ueber mehrere Baender gleichzeitig angebunden sein.
    # Bewertet wird seine beste Strecke, sonst stuende er mehrfach in der Liste.
    $besteStrecke = @{}
    foreach ($v in @($Mesh.Verbindungen)) {
        if ($v.Art -ne 'WLAN') { continue }
        $rate = [Math]::Max($v.MaxRx, $v.MaxTx)
        if ($rate -le 0) { continue }
        foreach ($ziel in @($v.Von, $v.Nach)) {
            $istRepeater = $false
            foreach ($k in @($Mesh.Knoten)) {
                if ($k.Name -eq $ziel -and $k.Rolle -ne 'master') { $istRepeater = $true }
            }
            if (-not $istRepeater) { continue }
            if (-not $besteStrecke.ContainsKey($ziel) -or $besteStrecke[$ziel] -lt $rate) {
                $besteStrecke[$ziel] = $rate
            }
        }
    }
    foreach ($ziel in $besteStrecke.Keys) {
        $rate = $besteStrecke[$ziel]
        if ($rate -ge 700) { continue }
        $g = & $finde 'rep-6000'
        $vorschlaege += [pscustomobject]@{
            Rang    = 3
            Anlass  = "Schwache Funkstrecke zu $ziel"
            Grund   = "Die beste Funkstrecke dieses Repeaters liegt bei $rate Mbit/s. Sie teilt sich die Sendezeit mit allen Geräten, die über ihn laufen — jedes Datenpaket geht zweimal durch die Luft, einmal zum Gerät und einmal weiter zum Router."
            Wirkung = 'Ein Netzwerkkabel zum Router löst das vollständig und kostet nichts außer dem Kabel. Geht das nicht, hat ein Tri-Band-Gerät ein eigenes Funkmodul nur für diese Strecke.'
            Geraet  = $g
        }
    }

    # ---------------------------------------- 4. Dauerhaft schwache Ecken
    $schwach = @()
    foreach ($c in @($FunkClients)) {
        if ([int]$c.Signal -lt 40) { $schwach += $c }
    }
    if ($schwach.Count -ge 2) {
        $g = & $finde 'rep-1700'
        $vorschlaege += [pscustomobject]@{
            Rang    = 4
            Anlass  = "$($schwach.Count) Geräte mit schwachem Signal"
            Grund   = 'Mehrere Geräte funken unter 40 % Signalstärke. Das kostet nicht nur diese Geräte Geschwindigkeit — sie belegen bei niedriger Rate überproportional viel Sendezeit und bremsen dadurch alle anderen mit.'
            Wirkung = 'Ein zusätzlicher Repeater in der Nähe dieser Geräte hebt ihre Aushandlungsrate und gibt dem ganzen Band Sendezeit zurück.'
            Geraet  = $g
        }
    }

    # -------------------------------------------------- 5. Router-Wechsel
    $boxModell = ''
    foreach ($k in @($Mesh.Knoten)) { if ($k.Rolle -eq 'master') { $boxModell = $k.Modell } }
    if ($boxModell -match '7590') {
        $g = & $finde 'fb-7690'
        $vorschlaege += [pscustomobject]@{
            Rang    = 6
            Anlass  = 'Router könnte moderner sein — muss aber nicht'
            Grund   = "$boxModell funkt mit Wi-Fi 6 und hat nur Gigabit-Anschlüsse. Der Nachfolger bringt Wi-Fi 7 und einen 2,5-Gbit-Anschluss."
            Wirkung = 'Ehrlich betrachtet: Bei einer DSL-Leitung unter 300 Mbit/s bringt ein neuer Router am Internetzugang nichts. Nur wenn im Haus große Dateien geschoben werden, lohnt der Wechsel — und dafür ist ein Switch für ein Drittel des Preises meist die bessere Wahl.'
            Geraet  = $g
        }
    }

    [pscustomobject]@{
        Stand       = $daten.stand
        Hinweis     = $daten.hinweis
        Vorschlaege = ($vorschlaege | Sort-Object Rang)
        Katalog     = $daten.geraete
    }
}
