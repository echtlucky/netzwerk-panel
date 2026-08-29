' netzpanel-still.vbs
' Startet das Panel vollstaendig unsichtbar - ohne Konsolenfenster, das
' aufblitzt, und ohne Browser.
'
' PowerShell mit -WindowStyle Hidden zeigt beim Start trotzdem kurz ein
' schwarzes Fenster. Der Umweg ueber den Windows Script Host vermeidet das:
' der letzte Parameter 0 bedeutet "kein Fenster", der letzte False heisst
' "nicht auf das Ende warten".

Option Explicit

Dim shell, fso, ordner, befehl
Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

ordner = fso.GetParentFolderName(WScript.ScriptFullName)

befehl = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & _
         ordner & "\netzpanel.ps1"" start -KeinBrowser"

shell.Run befehl, 0, False
