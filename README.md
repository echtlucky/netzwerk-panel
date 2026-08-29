# Netzwerk-Panel

Eine lokale Weboberfläche für FRITZ!Box-Heimnetze. Zeigt, was im Netz los ist,
sagt von sich aus, wo Leistung verloren geht, und rechnet Umbauten durch,
bevor man sie macht.

Läuft ausschließlich auf `127.0.0.1`. Kein Cloud-Dienst, kein Konto, keine
Datenübertragung nach außen — die Daten kommen per TR-064 direkt aus der Box
im eigenen Netz.

## Installieren

In PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/BENUTZER/netzwerk-panel/main/install.ps1 | iex
```

Installiert nach `%LOCALAPPDATA%\netzpanel`. Keine Administratorrechte nötig,
nichts wird an Windows verändert. Deinstallieren heißt: den Ordner löschen.

Alternativ das Repository herunterladen und `netzpanel.ps1` direkt aufrufen.

## Einrichten

**1. Schnittstelle in der FRITZ!Box freigeben**

> Heimnetz → Netzwerk → Netzwerkeinstellungen
> Haken bei **„Zugriff für Anwendungen zulassen"**

**2. Eigenen Benutzer anlegen** — nicht das Hauptkonto verwenden

> System → FRITZ!Box-Benutzer → Benutzer hinzufügen

| Berechtigung | wofür |
|---|---|
| **FRITZ!Box Einstellungen** | Pflicht |
| Smart Home | nur für die Smart-Home-Ansicht |
| Sprach-/Faxnachrichten und Anrufliste | nur für die Telefonie-Ansicht |

„Zugang auch aus dem Internet erlaubt" bleibt **aus**.

**3. Zugangsdaten hinterlegen**

```powershell
.\netzpanel.ps1 einrichten
```

Das Passwort wird beim Eintippen nicht angezeigt und mit der Windows-Datenschutz-API
(DPAPI) verschlüsselt unter `%APPDATA%\netzpanel\zugang.xml` abgelegt. Nur dasselbe
Windows-Konto auf demselben Rechner kann es wieder entschlüsseln — kopiert auf einen
anderen Rechner ist die Datei wertlos.

## Benutzen

```powershell
.\netzpanel.ps1 start     # Panel starten und im Browser öffnen
.\netzpanel.ps1 demo      # Oberfläche mit Beispieldaten ansehen
.\netzpanel.ps1 status    # Verbindung und alle Datenquellen prüfen
.\netzpanel.ps1 einrichten
.\netzpanel.ps1 zuruecksetzen
```

Zusätze: `-Port 8089` für einen anderen Port, `-KeinBrowser` zum Unterdrücken
des Browserstarts.

## Was das Panel kann

### Optimierung — findet von selbst, was bremst

In einem Funkband sendet immer nur ein Gerät gleichzeitig. Für dieselbe
Datenmenge braucht ein Gerät mit 72 Mbit/s zwölfmal so lange wie eines mit
866 Mbit/s — und blockiert das Band solange für alle anderen. **Ein Netz wird
durch sein langsamstes Gerät gebremst, nicht durch sein schnellstes.**

Das Panel rechnet die Sendezeitverteilung je Band aus, benennt das Gerät, das
am meisten davon verbraucht, und schlägt konkrete Umbauten vor — sortiert nach
tatsächlicher Wirkung, jeweils mit durchgerechnetem Prozentwert.

### Simulator — durchrechnen statt ausprobieren

Vier Szenarien je Gerät, ohne dass etwas geschaltet wird:

- ans Netzwerkkabel anschließen
- in ein anderes Funknetz umziehen
- besseres Signal geben (näherer Repeater)
- abschalten

Das Ergebnis zeigt beide Seiten: was das Gerät selbst gewinnt, und was das
Netz insgesamt gewinnt oder verliert. Ein langsames Gerät ins schnelle Band zu
holen macht es schneller — und alle anderen dort langsamer. Der Simulator sagt
das, statt es zu verschweigen.

### Geräteberatung — aus dem eigenen Netz, nicht aus einer Bestenliste

Vergleicht den gemessenen Zustand mit einer gepflegten Gerätedatenbank und
schlägt vor, was sich lohnt — mit Begründung aus den eigenen Messwerten,
Dringlichkeit und Preisspanne. Wenn nichts anzuschaffen ist, steht das dort auch.

### Weitere Ansichten

| Ansicht | Inhalt |
|---|---|
| **Übersicht** | Kennzahlen, offene Punkte mit Sprung zur zuständigen Ansicht |
| **Mesh** | Topologie als Diagramm, Strecken nach Datenrate bewertet |
| **Geräte** | Alle Geräte mit Anbindung, Tempo, Signal; sperren, freigeben, per Weckruf starten |
| **Funk** | Bänder einzeln schaltbar, Clients mit Signalstärke, Gastschlüssel |
| **Mobilgeräte** | Was der Verbindung von Handys und Tablets im Weg steht, in Klartext |
| **Leitung** | DSL-Diagnose: Störabstand, Dämpfung, CRC- und FEC-Fehler, Neusynchronisierungen |
| **Sicherheit** | UPnP, Fernzugriff, MyFRITZ, Firmware, Portfreigaben; dazu Firewall und SMB des PCs |
| **Protokoll** | Ereignisprotokoll der Box, nach Schwere eingefärbt |
| **Smart Home** | DECT-Steckdosen schalten, Leistung, Verbrauch, Thermostate |
| **Telefonie** | Anrufliste, angemeldete DECT-Telefone |
| **Dieser PC** | Netzwerkkarten, Freigaben, offene Sitzungen |
| **Einstellungen** | Verbindung und die Schwellen, ab denen gewarnt wird |

## Voraussetzungen

- Windows mit PowerShell 5.1 oder neuer (bei Windows 10 und 11 dabei)
- Eine FRITZ!Box mit FRITZ!OS 7 oder neuer
- Ein Browser

Nicht jede Box bietet jeden Dienst an. Fehlt einer, bleibt nur die betroffene
Karte leer und meldet das — der Rest läuft weiter.

## Datenschutz

- Der Webserver lauscht auf `127.0.0.1` und ist aus dem Netz nicht erreichbar
- Zugangsdaten liegen DPAPI-verschlüsselt unter `%APPDATA%\netzpanel`, außerhalb
  des Programmordners und damit außerhalb jedes Repositorys
- Es gibt keine Telemetrie, keine externen Aufrufe, keine Konten
- Die einzige Verbindung nach außen ist der Schriftartendienst von Google Fonts
  für die Oberfläche; ohne Internetzugang greift die Systemschrift

Die Beispieldaten (`netzpanel demo`) sind vollständig erfunden: generische
Gerätenamen und lokal administrierte MAC-Adressen, die nie an Hersteller
vergeben wurden.

## Aufbau

```
netzpanel.ps1        Einstiegspunkt mit allen Befehlen
install.ps1          Installer für den PowerShell-Einzeiler
src/
  konfig.ps1         Einstellungen und Zugangsdaten (%APPDATA%)
  tr064.ps1          TR-064-Client: alle Abfragen und Schaltbefehle
  analyse.ps1        Sendezeit-Modell, Simulator, Vorschläge, Mobilanalyse
  hardware.ps1       Kaufberatung aus dem gemessenen Zustand
  server.ps1         Webserver, Datenquellen, Bewertung, Ansichten
  demo.ps1           erfundene Beispieldaten
data/
  hardware.json      Gerätedatenbank — hier pflegen, nicht im Code
www/
  index.html         Oberfläche
```

Die Gerätedatenbank in `data/hardware.json` ist bewusst getrennt: Neue Modelle
trägt man dort ein, ohne Programmcode anzufassen.

## Grenzen

Die Rechnungen des Simulators und der Optimierung sind **Modellrechnungen** aus
den ausgehandelten Datenraten, keine Messungen. Sie zeigen Größenordnung und
Rangfolge zuverlässig, ersetzen aber keinen echten Durchsatztest. Wände,
Störquellen und das Verhalten einzelner Geräte gehen nicht ein.

## Lizenz

MIT — siehe [LICENSE](LICENSE).

FRITZ!Box, FRITZ!OS, FRITZ!Repeater und AVM sind Marken der AVM GmbH. Dieses
Projekt steht in keiner Verbindung zu AVM.
