# demo.ps1
# Beispieldaten fuer den Schalter -Demo.
#
# Alle Werte sind frei erfunden: generische Geraetenamen, lokal administrierte
# MAC-Adressen (Praefix 02:, nie an Hersteller vergeben) und das AVM-Standardnetz
# 192.168.178.0/24. Hier stehen keine Daten aus einem echten Haushalt.
#
# Das Beispielnetz ist absichtlich so gewaehlt, dass die Bewertung etwas zu
# bemaengeln findet: ein altes Geraet im 2,4-GHz-Netz, zwei veraltete Repeater,
# eine schwache Funkstrecke und aktive Portfreigaben.

function Get-DemoHosts {
    @(
        @{ Name='Arbeitsplatz-PC';    IP='192.168.178.20';  MAC='02:1A:2B:00:00:01'; Aktiv=$true;  Art='Ethernet'; Port='LAN 1'; Speed='1000'; Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='';                       Hersteller='';        Fest=$true;  Quelle='Static' }
        @{ Name='Repeater Erdgeschoss'; IP='192.168.178.21'; MAC='02:1A:2B:00:00:02'; Aktiv=$true; Art='Ethernet'; Port='LAN 2'; Speed='1000'; Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='FRITZ!Repeater 3000 AX'; Hersteller='AVM';     Fest=$true;  Quelle='Static' }
        @{ Name='Repeater Obergeschoss'; IP='192.168.178.22'; MAC='02:1A:2B:00:00:03'; Aktiv=$true; Art='802.11';  Port='';      Speed='433';  Gast=$false; Gesperrt=$false; UpdateVerf=$true;  Modell='FRITZ!Repeater 1750E';   Hersteller='AVM';     Fest=$true;  Quelle='Static' }
        @{ Name='Repeater Keller';    IP='192.168.178.23';  MAC='02:1A:2B:00:00:04'; Aktiv=$true;  Art='802.11';   Port='';      Speed='325';  Gast=$false; Gesperrt=$false; UpdateVerf=$true;  Modell='FRITZ!Repeater 1750E';   Hersteller='AVM';     Fest=$true;  Quelle='Static' }
        @{ Name='Smartphone';         IP='192.168.178.30';  MAC='02:1A:2B:00:00:05'; Aktiv=$true;  Art='802.11';   Port='';      Speed='866';  Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='Smartphone';             Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Notebook';           IP='192.168.178.31';  MAC='02:1A:2B:00:00:06'; Aktiv=$true;  Art='802.11';   Port='';      Speed='390';  Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='';                       Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Tablet';             IP='192.168.178.32';  MAC='02:1A:2B:00:00:07'; Aktiv=$true;  Art='802.11';   Port='';      Speed='217';  Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='Tablet';                 Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Wohnzimmer-Fernseher'; IP='192.168.178.40'; MAC='02:1A:2B:00:00:08'; Aktiv=$true; Art='802.11';   Port='';      Speed='195';  Gast=$true;  Gesperrt=$false; UpdateVerf=$false; Modell='Smart-TV';               Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Streaming-Box';      IP='192.168.178.41';  MAC='02:1A:2B:00:00:09'; Aktiv=$true;  Art='802.11';   Port='';      Speed='217';  Gast=$true;  Gesperrt=$false; UpdateVerf=$false; Modell='';                       Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Sprachassistent';    IP='192.168.178.42';  MAC='02:1A:2B:00:00:0A'; Aktiv=$true;  Art='802.11';   Port='';      Speed='72';   Gast=$true;  Gesperrt=$false; UpdateVerf=$false; Modell='';                       Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Altes Tablet';       IP='192.168.178.50';  MAC='02:1A:2B:00:00:0B'; Aktiv=$true;  Art='802.11';   Port='';      Speed='72';   Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='Tablet';                 Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
        @{ Name='Netzwerkdrucker';    IP='192.168.178.60';  MAC='02:1A:2B:00:00:0C'; Aktiv=$false; Art='';         Port='';      Speed='0';    Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='Drucker';                Hersteller='Beispiel'; Fest=$true;  Quelle='Static' }
        @{ Name='Heimserver';         IP='192.168.178.70';  MAC='02:1A:2B:00:00:0D'; Aktiv=$true;  Art='Ethernet'; Port='LAN 3'; Speed='1000'; Gast=$false; Gesperrt=$false; UpdateVerf=$false; Modell='';                       Hersteller='';        Fest=$true;  Quelle='Static' }
        @{ Name='Ausgemustertes Gerät'; IP='192.168.178.80'; MAC='02:1A:2B:00:00:0E'; Aktiv=$false; Art='';        Port='';      Speed='0';    Gast=$false; Gesperrt=$true;  UpdateVerf=$false; Modell='';                       Hersteller='Beispiel'; Fest=$false; Quelle='DHCP' }
    ) | ForEach-Object { [pscustomobject]$_ }
}

function Get-DemoFunkClients {
    @(
        @{ Band='5 GHz';    BandIndex=2; MAC='02:1A:2B:00:00:05'; IP='192.168.178.30'; Angemeldet=$true; SpeedMbit=866; Signal=84 }
        @{ Band='5 GHz';    BandIndex=2; MAC='02:1A:2B:00:00:06'; IP='192.168.178.31'; Angemeldet=$true; SpeedMbit=390; Signal=62 }
        @{ Band='5 GHz';    BandIndex=2; MAC='02:1A:2B:00:00:03'; IP='192.168.178.22'; Angemeldet=$true; SpeedMbit=433; Signal=68 }
        @{ Band='5 GHz';    BandIndex=2; MAC='02:1A:2B:00:00:04'; IP='192.168.178.23'; Angemeldet=$true; SpeedMbit=325; Signal=51 }
        @{ Band='5 GHz';    BandIndex=2; MAC='02:1A:2B:00:00:07'; IP='192.168.178.32'; Angemeldet=$true; SpeedMbit=217; Signal=44 }
        @{ Band='2,4 GHz';  BandIndex=1; MAC='02:1A:2B:00:00:0B'; IP='192.168.178.50'; Angemeldet=$true; SpeedMbit=72;  Signal=58 }
        @{ Band='Gastnetz'; BandIndex=3; MAC='02:1A:2B:00:00:08'; IP='192.168.178.40'; Angemeldet=$true; SpeedMbit=195; Signal=47 }
        @{ Band='Gastnetz'; BandIndex=3; MAC='02:1A:2B:00:00:09'; IP='192.168.178.41'; Angemeldet=$true; SpeedMbit=217; Signal=55 }
        @{ Band='Gastnetz'; BandIndex=3; MAC='02:1A:2B:00:00:0A'; IP='192.168.178.42'; Angemeldet=$true; SpeedMbit=72;  Signal=36 }
    ) | ForEach-Object { [pscustomobject]$_ }
}

function Get-DemoMeshRoh {
    [pscustomobject]@{
        Knoten = @(
            [pscustomobject]@{ Name='Router';               Modell='FRITZ!Box 7590 AX';      Firmware='8.02'; Rolle='master'; MAC='02:1A:2B:00:00:00'; Clients=5 }
            [pscustomobject]@{ Name='Repeater Erdgeschoss'; Modell='FRITZ!Repeater 3000 AX'; Firmware='8.02'; Rolle='slave';  MAC='02:1A:2B:00:00:02'; Clients=3 }
            [pscustomobject]@{ Name='Repeater Obergeschoss'; Modell='FRITZ!Repeater 1750E';  Firmware='7.31'; Rolle='slave';  MAC='02:1A:2B:00:00:03'; Clients=2 }
            [pscustomobject]@{ Name='Repeater Keller';      Modell='FRITZ!Repeater 1750E';   Firmware='7.31'; Rolle='slave';  MAC='02:1A:2B:00:00:04'; Clients=1 }
        )
        Verbindungen = @(
            [pscustomobject]@{ Von='Router'; Nach='Repeater Erdgeschoss';  Art='LAN';  Band='';          MaxRx=1000; MaxTx=1000; CurRx=1000; CurTx=1000 }
            [pscustomobject]@{ Von='Router'; Nach='Repeater Obergeschoss'; Art='WLAN'; Band='WLAN:5GHz'; MaxRx=433;  MaxTx=433;  CurRx=390;  CurTx=390 }
            [pscustomobject]@{ Von='Router'; Nach='Repeater Keller';       Art='WLAN'; Band='WLAN:5GHz'; MaxRx=325;  MaxTx=325;  CurRx=260;  CurTx=260 }
        )
    }
}

function Get-DemoVerlauf {
    param([double]$Basis, [double]$Streuung, [int]$Anzahl = 20)
    $r = @()
    for ($i = 0; $i -lt $Anzahl; $i++) {
        $r += [math]::Round([Math]::Max(0, $Basis + (Get-Random -Minimum (-$Streuung * 10) -Maximum ($Streuung * 10)) / 10), 2)
    }
    $r
}

function Get-DemoDurchsatz {
    $ds = Get-DemoVerlauf -Basis 42 -Streuung 38
    $us = Get-DemoVerlauf -Basis 7  -Streuung 6
    [pscustomobject]@{
        DownMbit    = $ds[0]
        UpMbit      = $us[0]
        VerlaufDown = $ds
        VerlaufUp   = $us
        MaxDownMbit = 190.4
        MaxUpMbit   = 42.0
    }
}

function Get-DemoDsl {
    [pscustomobject]@{
        Status           = 'Up'
        Betriebsart      = 'G.993.2 Annex B'
        DownAktuellKbit  = 190432
        UpAktuellKbit    = 42003
        DownMaxKbit      = 204800
        UpMaxKbit        = 46000
        DownStoerabstand = 9.4
        UpStoerabstand   = 11.2
        DownDaempfung    = 14.8
        UpDaempfung      = 8.1
        DownLeistung     = 13.7
        UpLeistung       = 6.2
    }
}

function Get-DemoDslFehler {
    [pscustomobject]@{
        Neusynchronisierungen = 7
        Startfehler           = 0
        Zeitueberschreitungen = 0
        RahmenVerloren        = 2
        FehlerSekunden        = 341
        SchwereFehlerSekunden = 4
        FecFehler             = 128744
        CrcFehler             = 2417
        HecFehler             = 88
    }
}

function Get-DemoWlan {
    @(
        [pscustomobject]@{ Index=1; Band='2,4 GHz';  SSID='Heimnetz';      An=$true; Kanal='1';  Schutz='11i'; Sichtbar=$true; Standard='n';  Clients=1 }
        [pscustomobject]@{ Index=2; Band='5 GHz';    SSID='Heimnetz';      An=$true; Kanal='52'; Schutz='11i'; Sichtbar=$true; Standard='ax'; Clients=5 }
        [pscustomobject]@{ Index=3; Band='Gastnetz'; SSID='Heimnetz-Gast'; An=$true; Kanal='52'; Schutz='11i'; Sichtbar=$true; Standard='ax'; Clients=3 }
    )
}

function Get-DemoWan {
    [pscustomobject]@{
        Zugangsart    = 'DSL'
        Verbindung    = 'Up'
        DownMbit      = 190.4
        UpMbit        = 42.0
        ExterneIP     = '203.0.113.42'
        OnlineSeitSek = 1391280
        Status        = 'Connected'
        LetzterFehler = 'ERROR_NONE'
    }
}

function Get-DemoSicherheitLage {
    [pscustomobject]@{
        Upnp        = [pscustomobject]@{ An = $true;  Medienserver = $true }
        Fernzugriff = [pscustomobject]@{ An = $false; Port = '443'; Benutzer = '' }
        MyFritz     = [pscustomobject]@{ An = $true;  Name = 'beispiel.myfritz.net' }
    }
}

function Get-DemoFirmware {
    [pscustomobject]@{ UpdateVerfuegbar = $true; NeueVersion = '8.03'; Infoseite = '' }
}

function Get-DemoLatenz {
    @(
        [pscustomobject]@{ Ziel='192.168.178.1';  Ms=0 }
        [pscustomobject]@{ Ziel='192.168.178.21'; Ms=0 }
        [pscustomobject]@{ Ziel='192.168.178.22'; Ms=2 }
        [pscustomobject]@{ Ziel='192.168.178.23'; Ms=9 }
    )
}

function Get-DemoSmartHomeGeraete {
    @(
        [pscustomobject]@{ AIN='00000 0000001'; Name='Arbeitsplatz'; Produkt='FRITZ!DECT 210'; Hersteller='AVM'
                           Firmware='04.25'; Erreichbar=$true; HatSchalter=$true; SchalterAn=$true; Gesperrt=$false
                           LeistungWatt=143.7; EnergieWh=284119; TempCelsius=23.5; HatThermostat=$false; SollTemp=$null }
        [pscustomobject]@{ AIN='00000 0000002'; Name='Wohnzimmer'; Produkt='FRITZ!DECT 301'; Hersteller='AVM'
                           Firmware='05.16'; Erreichbar=$true; HatSchalter=$false; SchalterAn=$false; Gesperrt=$false
                           LeistungWatt=$null; EnergieWh=$null; TempCelsius=21.0; HatThermostat=$true; SollTemp=20.5 }
    )
}

function Get-DemoProtokollEintraege {
    $heute = (Get-Date).ToString('dd.MM.yy')
    @(
        [pscustomobject]@{ Datum=$heute; Zeit='11:14:02'; Art='info';     Text='WLAN-Gerät angemeldet: Smartphone (5 GHz).' }
        [pscustomobject]@{ Datum=$heute; Zeit='09:38:41'; Art='warnung';  Text='WLAN-Gerät hat sich abgemeldet: Tablet. Verbindung verloren.' }
        [pscustomobject]@{ Datum=$heute; Zeit='08:02:19'; Art='gut';      Text='Internetverbindung wurde erfolgreich hergestellt.' }
        [pscustomobject]@{ Datum=$heute; Zeit='08:02:11'; Art='warnung';  Text='DSL-Synchronisierung beginnt (Training).' }
        [pscustomobject]@{ Datum=$heute; Zeit='08:01:58'; Art='warnung';  Text='Internetverbindung getrennt.' }
        [pscustomobject]@{ Datum=$heute; Zeit='07:41:03'; Art='kritisch'; Text='Anmeldung an der Benutzeroberfläche fehlgeschlagen.' }
        [pscustomobject]@{ Datum=$heute; Zeit='06:15:00'; Art='info';     Text='Zeitsynchronisierung erfolgreich.' }
    )
}

function Get-DemoAnrufe {
    @(
        [pscustomobject]@{ Art='verpasst';  Datum='28.08.26 10:12'; Name='';         Nummer='+49 30 000000'; Eigene='Festnetz'; Dauer='0:00'; Geraet='' }
        [pscustomobject]@{ Art='eingehend'; Datum='27.08.26 18:44'; Name='Beispiel'; Nummer='+49 30 000000'; Eigene='Festnetz'; Dauer='0:12'; Geraet='DECT 1' }
        [pscustomobject]@{ Art='ausgehend'; Datum='27.08.26 14:02'; Name='';         Nummer='+49 30 000000'; Eigene='Festnetz'; Dauer='0:03'; Geraet='DECT 1' }
    )
}

function Get-DemoPortfreigaben {
    @(
        [pscustomobject]@{ Beschreibung='Streaming-Box'; Protokoll='TCP'; AussenPort='5001'; Ziel='192.168.178.41'; ZielPort='5001'; Aktiv=$true }
        [pscustomobject]@{ Beschreibung='UPnP: Anwendung'; Protokoll='TCP'; AussenPort='51413'; Ziel='192.168.178.20'; ZielPort='51413'; Aktiv=$true }
    )
}

function Get-DemoBox {
    [pscustomobject]@{ Modell='FRITZ!Box 7590 AX'; Firmware='8.02'; Seriennr='BEISPIEL'; LaufzeitSek=1391400 }
}
