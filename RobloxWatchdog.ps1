#------------------------------------------------------------------------------------#
# Naam script          : RobloxWatchdog.ps1
# Omschrijving         : Settings window, then: launches main + alts through Roblox
#                        Account Manager, relaunches any account that crashes or loses
#                        its connection (read from the Roblox log file), tiles all
#                        windows (main in slot 0), relogs alts when they get old, and
#                        kills the largest alt when RAM is low.
# Naam ontwikkelaar    : Florian Groot
# Project              : Miniwar AFK
# Datum                : 18-09-2026
#------------------------------------------------------------------------------------#
# Aanpassing   Datum   Project Pgmr   Omschrijving
# 001          19-09-2026 Miniwar AFK FG  Password verplicht, fallback zonder LinkCode verwijderd, RAM-antwoord loggen, nieuw venster is de succescontrole, volledige private server link via JobId
# 002          21-09-2026 Miniwar AFK FG  Disconnect-detectie via Roblox-logbestanden, main wordt ook herstart en getegeld (slot 0)
# 003          22-09-2026 Miniwar AFK FG  Security: instellingen naar LOCALAPPDATA, wachtwoord versleuteld (DPAPI),
#                                         bestandsrechten dichtgezet, private-serverlink gevalideerd, PID-hergebruik afgevangen.
#                                         Robuustheid: fouten in de lus niet meer fataal, backoff na mislukte launches,
#                                         HTTP-timeout, logbestand, afgekapt logbestand afgevangen.
# 004          23-09-2026 Miniwar AFK FG  Framerate-cap tegen CPU-verbruik, anti-idle: venster naar voren en toetsaanslag
#                                         zodat Roblox de client na 20 minuten niet kickt.
# 005          25-09-2026 Miniwar AFK FG  Een client die wel start maar nooit in de game komt wordt herstart (er is geen
#                                         disconnectcode bij "failed to connect"), zwerfprocessen zonder venster worden
#                                         opgeruimd, fatale fouten gaan naar het logbestand in plaats van alleen de console.
# 006          26-09-2026 Miniwar AFK FG  Statusvenster in plaats van een console: de lus is nu een state machine die per
#                                         tick een stap zet, zodat het venster niet vastloopt tijdens een launch. Tray-icoon,
#                                         pauzeknop, accounts los herstarten en een zichtbare melding als rechten ontbreken.
#                                         De accounts worden nu naar schermoppervlak over alle monitoren verdeeld.
# 007          04-10-2026 Miniwar AFK FG  RAM weigert een launch met een tekst in het antwoord in plaats van met een
#                                         statuscode. Die tekst werd weggegooid, waardoor een geweigerde launch 90
#                                         seconden op een venster wachtte dat nooit kwam en daarna eindeloos opnieuw
#                                         probeerde zonder uitleg. Nu stopt de launch direct met de melding van RAM
#                                         erbij, en het statusvenster laat de laatste foutmelding per account zien.
# 008          04-10-2026 Miniwar AFK FG  Het spel teleporteert spelers tussen rondes: de client verlaat de server, logt
#                                         een disconnect en komt vijf seconden later op diezelfde server terug, in
#                                         hetzelfde proces. Dat werd als een drop gelezen en de gezonde client werd
#                                         gesloten en opnieuw gestart: 728 van de 785 disconnects in het logbestand.
#                                         Nu wordt gewacht of de client zelf terugkomt op dezelfde server, en wordt
#                                         alleen herstart als dat niet gebeurt. Een verdwenen proces is ook geen bewijs
#                                         meer: een warm gestarte sessie wordt overgenomen in plaats van herstart, en
#                                         anders wel geteld en gemeld. Een sessie zonder logbestand zoekt nu door tot
#                                         hij er een heeft, want zonder logbestand ziet de watchdog niets.
# 009          04-10-2026 Miniwar AFK FG  Roblox weigert soms een tweede client te starten door in zijn eigen
#                                         SingleInstanceGuard te crashen: de nieuwe starter kan het venster van de
#                                         draaiende client niet bereiken en stopt voordat er een venster is. RAM meldt
#                                         niets, want RAM heeft zijn deel gedaan. Dat werd 90 seconden afgewacht en
#                                         daarna eindeloos opnieuw geprobeerd, terwijl opnieuw proberen niets oplost.
#                                         Nu wordt de crash in het logbestand van de mislukte start herkend en worden
#                                         alle clients gesloten, main inbegrepen, want dat is het enige dat het
#                                         oplost. Daarna starten ze allemaal opnieuw, met hoogstens een reset per
#                                         tien minuten zodat het niet gaat stuiteren.
# 010          05-10-2026 Miniwar AFK FG  De private server verhuist af en toe naar een nieuwe instance en neemt alle
#                                         accounts mee. Dat werd gelezen als zes losse drops en alles werd opnieuw
#                                         gestart, terwijl er niets aan de hand was. Nu wordt een nieuw adres pas
#                                         beoordeeld aan het eind van de ronde: komen meerdere accounts op hetzelfde
#                                         nieuwe adres uit, dan is het een verhuizing en blijft alles staan. Staat een
#                                         account alleen op een adres waar niemand anders zit, dan is het wel weg.
#                                         Anti-idle: focus werd 22% van de keren geweigerd en dat kostte telkens een
#                                         minuut; er wordt nu meteen opnieuw om gevraagd. Daarnaast een instelling
#                                         voor agressieve anti-idle: dubbel zo vaak, met lopen, muisbeweging en twee
#                                         toetsaanslagen in plaats van een.
#                                         Een teleport laat het personage opnieuw spawnen, dus de setup is daarna
#                                         net zo goed nodig als na een herstart. Dat werd gemist sinds teleports
#                                         niet meer tot een herstart leiden, waardoor main bij spawn bleef staan
#                                         zonder raketten en zonder melding.
#                                         De watchdog kijkt nu ook of er een nieuwere versie uit is en zegt dat op
#                                         de strook bovenin, aanklikbaar naar de downloadpagina. Eens per zes uur,
#                                         op de achtergrond, en als het mislukt gebeurt er gewoon niets.
# 011          05-10-2026 Miniwar AFK FG  Roblox schrijft de rejoin en de disconnect vanuit verschillende threads, dus
#                                         de volgorde is niet zeker. Bij een teleport van zes accounts stond bij een
#                                         van hen de rejoin 20 ms voor de disconnect, en omdat er alleen erna werd
#                                         gekeken werd die client wel gesloten en herstart. De teleportmelding van
#                                         het spel zelf beslist het nu, die staat er bij een echte drop nooit.
#                                         Verder: de waarschuwing dat focus geweigerd wordt komt nog een keer in
#                                         plaats van elke minuut per account.
#                                         Een teleport is in de praktijk een relog: het personage spawnt opnieuw en
#                                         de inventaris staat weer in de hotbar, dus alles wat met de hand is
#                                         neergezet moet opnieuw. Dat wordt nu zo genoemd en gemeld, voor main altijd
#                                         en voor een groep van drie of meer tegelijk. De melding dat de setup weer
#                                         nodig is hing eerst aan het hebben van een stappenlijst, waardoor wie het
#                                         met de hand doet niets te horen kreeg.
#
#------------------------------------------------------------------------------------#

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

$processName = "RobloxPlayerBeta"
$minimumClientBytes = 500MB

# The window runs the show now: a timer ticks often and cheaply, launches advance one
# step per tick, and the heavier checks run on every 40th tick. Nothing blocks, so the
# window stays responsive even while six accounts are relaunching.
$tickMilliseconds = 250
$slowTicksPerCheck = 40                                                              # 40 x 250 ms = 10 s, as before
$uiTicksPerRefresh = 4                                                               # redraw once a second
$launchTimeoutSeconds = 90                                                           # no new client window by then = failed launch
$logTimeoutSeconds = 30                                                              # no log file by then = failed launch
$windowTimeoutSeconds = 60                                                           # no window by then = leave it untiled
$windowSettleSeconds = 5                                                             # let Roblox restore its own size before moving it
$manualMoveThreshold = 60                                                            # further than Roblox's own nudging, so only a real drag counts
$stepGapMilliseconds = 200                                                           # between steps with no explicit wait of their own
$stepRun = @{ Active = $false; Steps = @(); Index = 0; NextAt = $null; Reason = $null; HeldKey = $null }
$maximumLaunchFailures = 5                                                           # log loudly after this many failed launches in a row
$logFolder = Join-Path $env:LOCALAPPDATA "Roblox\logs"                              # Roblox client log files
$disconnectPattern = "Sending disconnect with reason: (\d+)"                         # logged on drop (277) and leave (285)
$ignoredDisconnectReasons = @()                                                      # never acted on at all; a teleport is recognised, not listed here
$joinMarker = "Connection accepted"                                                  # logged only once the client is really in the game
$joinAddressPattern = "Connection accepted from ([0-9.]+\|[0-9]+)"                   # the server it joined, so a rejoin can be compared with it
$teleportMarker = "SessionTransitionFSM] Teleported."                                # the game moving the player, which no real drop ever logs
$rejoinGraceSeconds = 30                                                             # a teleport is back in about 5 s, so this is plenty
$migrationWitnesses = 2                                                              # accounts landing on the same new server before it counts as a move
$relogWaveSize = 3                                                                   # accounts relogging together before it is worth saying so on its own
$logLivenessSeconds = 120                                                            # a log written more recently than this belongs to a live client
$watchdogVersion = "1.6.1"                                                           # the build stamps the exe with this too, and the exe wins at runtime
$releaseApiUrl = "https://api.github.com/repos/FloSoftwareDev/roblox-watchdog/releases/latest"
$releasePageUrl = "https://github.com/FloSoftwareDev/roblox-watchdog/releases/latest"
$versionCheckHours = 6                                                               # it runs for days at a time, so once at the start is not enough
$instanceGuardPattern = "SingleInstanceGuard"                                        # Roblox crashing in its own guard instead of starting a client
$instanceGuardCheckSeconds = 10                                                      # long enough for the failed starter to have written its log
$instanceGuardCooldownMinutes = 10                                                   # closing everything is drastic, so never thrash at it
$joinTimeoutSeconds = 150                                                            # no join by then means it is stuck on an error screen
$joinedMemoryBytes = 1GB                                                             # in-game clients sit on 3 GB, stuck ones on about 170 MB
$memoryKillCooldownSeconds = 120                                                     # long enough for a closed client to hand its memory back
$httpClient = New-Object System.Net.Http.HttpClient
$httpClient.Timeout = [TimeSpan]::FromSeconds(15)                                    # never let a hung RAM freeze the watchdog

# Windows refuses to let a normal process close or focus an elevated one, so if RAM is
# running as administrator its clients are too and half of this script is denied
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$elevationHintShown = $false

# Settings live in LOCALAPPDATA, not next to the script: when run as a .ps1 the old
# path resolved to the PowerShell install folder under System32
$scriptFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Environment]::GetCommandLineArgs()[0]) }
$settingsFolder = Join-Path $env:LOCALAPPDATA "RobloxWatchdog"
$settingsPath = Join-Path $settingsFolder "RobloxWatchdog.json"
$legacySettingsPath = Join-Path $scriptFolder "RobloxWatchdog.json"                  # pre-003 location, migrated on first run
$logFilePath = Join-Path $settingsFolder "RobloxWatchdog.log"
$positionsPath = Join-Path $settingsFolder "WindowPositions.json"                    # where you dragged each account's window
$restartsPath = Join-Path $settingsFolder "AutoRestarts.txt"                         # timestamps, for the crash-loop guard

# Relaunching itself after a crash is only safe with a limit: a fault that happens
# every time on startup would otherwise respawn for ever
$maximumAutoRestarts = 3
$autoRestartWindowMinutes = 10

# -autostart means this instance was started by the previous one after a crash, so it
# skips the settings dialog and uses what was saved
$startupArguments = @([Environment]::GetCommandLineArgs() | Select-Object -Skip 1)
$autoStarted = $startupArguments -contains "-autostart"

$recentLogLines = New-Object System.Collections.Generic.List[string]                  # what the Log window shows

function Write-Log($message)
{
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"

    # Deliberately no Write-Host: built with -noConsole, and ps2exe turns every
    # Write-Host into a message box, which a chatty log would bury the screen in
    $recentLogLines.Add($line)
    while ($recentLogLines.Count -gt 500) { $recentLogLines.RemoveAt(0) }

    try
    {
        if ((Test-Path $logFilePath) -and (Get-Item $logFilePath).Length -gt 5MB)
        {
            Move-Item $logFilePath "$logFilePath.old" -Force
        }
        Add-Content -Path $logFilePath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch
    {
        # console output is enough; logging must never take the watchdog down
    }
}

# ---- Discord ------------------------------------------------------------------------

$alertGreen = 3066993
$alertAmber = 16086298
$alertRed   = 15158332
$pendingWebhooks = New-Object System.Collections.Generic.List[object]

function Send-DiscordAlert($title, $message, $color, $ping)
{
    # Only the things worth waking up for. Ordinary disconnects are not sent: there were
    # 152 of them in four days, which would be noise rather than a notification.
    if (-not $discordWebhookUrl) { return }
    try
    {
        $body = @{
            embeds = @(@{
                title = $title
                description = $message
                color = $color
                footer = @{ text = "Roblox Watchdog on $env:COMPUTERNAME" }
                timestamp = (Get-Date).ToUniversalTime().ToString("o")
            })
        }

        if ($ping -and $discordPingId)
        {
            # Has to go in content, not in the embed: Discord does not raise a
            # notification for a mention that only appears inside an embed
            $body["content"] = "<@$discordPingId>"
            $body["allowed_mentions"] = @{ parse = @("users", "roles") }
        }

        $payload = $body | ConvertTo-Json -Depth 5 -Compress

        $content = New-Object System.Net.Http.StringContent($payload, [System.Text.Encoding]::UTF8, "application/json")
        # Posted without waiting: the window must never sit still because Discord is slow
        $pendingWebhooks.Add($httpClient.PostAsync($discordWebhookUrl, $content))
    }
    catch
    {
        Write-Log "WARNING: could not send the Discord alert: $($_.Exception.Message)"
    }
}

function Get-OwnVersion
{
    # Compiled, the exe carries the version the build stamped on it, and that is the one
    # that matters because that is what people downloaded.
    #
    # Run as a .ps1 the host is powershell.exe, which is also an .exe with a version of
    # its own, and taking that gave 10.0.26100.8457 as the watchdog's version. So the
    # product name has to match before the stamp is believed. Checking the name rather
    # than the file means a renamed copy still works, which matters because the one
    # pinned to a taskbar is often renamed.
    try
    {
        $exePath = [Environment]::GetCommandLineArgs()[0]
        if ($exePath -like "*.exe" -and (Test-Path $exePath))
        {
            $info = (Get-Item $exePath).VersionInfo
            if ($info.ProductName -eq "Roblox Watchdog" -and $info.FileVersion)
            {
                return ($info.FileVersion -replace "[^0-9.]", "")
            }
        }
    }
    catch { }
    return $watchdogVersion
}

function Start-VersionCheck
{
    # Asked for in the background and read on a later pass, so a slow or missing
    # connection never holds the window up. Failing is fine: not knowing whether there
    # is a newer version is not worth saying anything about.
    if ($script:versionCheckTask) { return }
    $script:lastVersionCheckAt = Get-Date
    try
    {
        $request = New-Object System.Net.Http.HttpRequestMessage("Get", $releaseApiUrl)
        $request.Headers.Add("User-Agent", "RobloxWatchdog")                          # GitHub refuses a request without one
        $request.Headers.Add("Accept", "application/vnd.github+json")
        $script:versionCheckTask = $httpClient.SendAsync($request)
    }
    catch
    {
        $script:versionCheckTask = $null
    }
}

function Complete-VersionCheck
{
    if (-not $script:versionCheckTask -or -not $script:versionCheckTask.IsCompleted) { return }
    $task = $script:versionCheckTask
    $script:versionCheckTask = $null
    try
    {
        $response = $task.Result
        if (-not $response.IsSuccessStatusCode) { return }
        $body = $response.Content.ReadAsStringAsync().Result

        # Read with a pattern rather than ConvertFrom-Json: the reply is a large object
        # and the tag is the only part of it that matters
        if ($body -notmatch '"tag_name"\s*:\s*"v?([0-9]+(?:\.[0-9]+){0,3})"') { return }
        $latest = $matches[1]
        $mine = Get-OwnVersion
        if ([version]$latest -gt [version]$mine)
        {
            if ($script:newerVersion -ne $latest)
            {
                $script:newerVersion = $latest
                Write-Log "a newer version is out: v$latest, this one is v$mine"
            }
        }
        else
        {
            $script:newerVersion = $null
        }
    }
    catch
    {
        # No connection, a rate limit, or a reply that does not look like a release.
        # None of those are worth a line in the log every six hours.
    }
}

function Complete-PendingWebhooks
{
    # Results are collected on a later tick, so a broken webhook shows up in the log
    # without anything having blocked on it
    for ($index = $pendingWebhooks.Count - 1; $index -ge 0; $index--)
    {
        $task = $pendingWebhooks[$index]
        if (-not $task.IsCompleted) { continue }
        $pendingWebhooks.RemoveAt($index)
        try
        {
            $response = $task.Result
            if (-not $response.IsSuccessStatusCode)
            {
                Write-Log "WARNING: Discord webhook replied $([int]$response.StatusCode) '$($response.ReasonPhrase)'"
            }
        }
        catch
        {
            Write-Log "WARNING: Discord webhook failed: $($_.Exception.GetBaseException().Message)"
        }
    }
}

function Request-SelfRestart
{
    # Reached only from the trap, so only after a fault. Pressing Exit does not come
    # through here, which is the point: a crash should come back, a deliberate stop
    # should stay stopped.
    $exePath = [Environment]::GetCommandLineArgs()[0]
    if ($exePath -notlike "*.exe")
    {
        Write-Log "not restarting automatically: running as a script, not the exe"
        return $false
    }

    $recentRestarts = @()
    try
    {
        if (Test-Path $restartsPath)
        {
            $cutoff = (Get-Date).AddMinutes(-$autoRestartWindowMinutes)
            $recentRestarts = @(Get-Content $restartsPath |
                Where-Object { $_ } |
                ForEach-Object { [datetime]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) } |
                Where-Object { $_ -gt $cutoff })
        }
    }
    catch
    {
        $recentRestarts = @()
    }

    if ($recentRestarts.Count -ge $maximumAutoRestarts)
    {
        Write-Log "ERROR: not restarting again, there have already been $($recentRestarts.Count) in the last $autoRestartWindowMinutes min"
        Send-DiscordAlert "Watchdog has given up" ("It has crashed and restarted $($recentRestarts.Count) times in " +
            "$autoRestartWindowMinutes minutes, so it is staying down. The accounts are not being watched.") $alertRed
        return $false
    }

    try
    {
        $recentRestarts += (Get-Date)
        Set-Content -Path $restartsPath -Value @($recentRestarts | ForEach-Object { $_.ToString("o") }) -Encoding UTF8
        Start-Process -FilePath $exePath -ArgumentList "-autostart"
        Write-Log "restarting itself (attempt $($recentRestarts.Count) of $maximumAutoRestarts in this window)"
        return $true
    }
    catch
    {
        Write-Log "ERROR: could not restart itself: $($_.Exception.Message)"
        return $false
    }
}

function Write-ElevationHint
{
    # Said once, not on every denial: the old version repeated the same failure every
    # ten seconds and buried everything else in the log
    if ($script:elevationHintShown -or $isElevated) { return }
    $script:elevationHintShown = $true
    Write-Log "HINT: that was denied because the watchdog is not running as administrator while the Roblox clients are."
    Write-Log "HINT: either run the exe as administrator, or stop running Roblox Account Manager as administrator (which also fixes autoclickers)."
    Send-DiscordAlert "Missing permissions" ("The watchdog is not running as administrator while the Roblox clients are, " +
        "so tiling, anti-idle and closing strays are all being denied.") $alertAmber
}

# Defined after Write-Log so a fatal error is written to the log file and not only to
# a console nobody is watching. It also no longer waits forever on Read-Host: the old
# version left the watchdog dead and silent until someone noticed the stuck window.
trap
{
    Write-Log "FATAL: $_"
    if ($_.InvocationInfo)
    {
        Write-Log "FATAL at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
    }
    $restarting = Request-SelfRestart

    # The whole point of the webhook: on 24-09 this died silently and the accounts sat
    # dead for 74 minutes before anyone noticed
    $alertText = "It hit an error:`n``$_``"
    if ($restarting) { $alertText += "`n`nIt is starting itself again." }
    else { $alertText += "`n`nIt has closed and the accounts are not being watched." }
    Send-DiscordAlert "Watchdog crashed" $alertText $alertRed
    Complete-PendingWebhooks                                                          # give the post a chance before the process goes

    # No message box when it is coming straight back, or an unattended crash would leave
    # a dialog sitting there waiting for a click that nobody is there to give
    if (-not $restarting)
    {
        [System.Windows.Forms.MessageBox]::Show(
            "$_`r`n`r`nThe watchdog has stopped. The details are in:`r`n$logFilePath",
            "Roblox Watchdog stopped", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    exit 1
}

# ---- Theme --------------------------------------------------------------------------

# Flat dark. No gradients anywhere: one background, one raised surface, one hairline
# border, two text weights, and colour used only where it carries meaning (the accent
# for the thing you are meant to read first, green/amber/grey for account state).
$themeBackground = [System.Drawing.Color]::FromArgb(27, 27, 31)
$themeSurface    = [System.Drawing.Color]::FromArgb(35, 35, 41)
$themeBorder     = [System.Drawing.Color]::FromArgb(52, 52, 61)
$themeText       = [System.Drawing.Color]::FromArgb(232, 232, 236)
$themeMuted      = [System.Drawing.Color]::FromArgb(138, 138, 149)
$themeAccent     = [System.Drawing.Color]::FromArgb(88, 159, 214)
$themeGreen      = [System.Drawing.Color]::FromArgb(76, 195, 138)
$themeAmber      = [System.Drawing.Color]::FromArgb(224, 164, 88)
$themeGrey       = [System.Drawing.Color]::FromArgb(110, 110, 122)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DarkFrame
{
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
"@

function Set-DarkTitleBar($form)
{
    # Without this the title bar stays light and the window looks half-themed. 20 is
    # DWMWA_USE_IMMERSIVE_DARK_MODE on Windows 10 2004 and later, 19 on the builds
    # before it; both are ignored harmlessly on anything older.
    try
    {
        $enabled = 1
        if ([DarkFrame]::DwmSetWindowAttribute($form.Handle, 20, [ref]$enabled, 4) -ne 0)
        {
            [void][DarkFrame]::DwmSetWindowAttribute($form.Handle, 19, [ref]$enabled, 4)
        }
    }
    catch
    {
        # an unthemed title bar is not worth failing over
    }
}

function Set-ThemedForm($form)
{
    $form.BackColor = $themeBackground
    $form.ForeColor = $themeText
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Add_Shown({ Set-DarkTitleBar $args[0] })
}

function Set-ThemedButton($button, $isPrimary)
{
    $button.FlatStyle = "Flat"
    $button.UseVisualStyleBackColor = $false
    $button.FlatAppearance.BorderSize = 1
    $button.Cursor = "Hand"
    if ($isPrimary)
    {
        $button.BackColor = $themeAccent
        $button.ForeColor = [System.Drawing.Color]::FromArgb(16, 20, 26)
        $button.FlatAppearance.BorderColor = $themeAccent
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(116, 178, 224)
    }
    else
    {
        $button.BackColor = $themeSurface
        $button.ForeColor = $themeText
        $button.FlatAppearance.BorderColor = $themeBorder
        $button.FlatAppearance.MouseOverBackColor = $themeBorder
    }
}

function Set-ThemedInput($control)
{
    $control.BackColor = $themeSurface
    $control.ForeColor = $themeText
    $control.BorderStyle = "FixedSingle"
}

# ---- Win32 -------------------------------------------------------------------------

# Up here rather than down with the watchdog: the settings dialog runs long before
# that point, and its Pick button needs the cursor and key-state calls. Defined
# later, clicking Pick threw "Get-WindowRectangle is not recognized".

Add-Type -Namespace Win32 -Name Window -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool altTab);
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
[DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint param, ref uint value, uint update);
"@

# Separate block because it needs a struct, which -MemberDefinition cannot declare.
# Used to read a window back after moving it: MoveWindow can report success while the
# window has not actually budged.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public struct POINT { public int X; public int Y; }
public class WinPos
{
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    // Lives here rather than in the member-definition block above, which compiles on its
    // own and cannot see a struct declared in a different Add-Type call
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
}
"@

function Get-WindowRectangle($handle)
{
    $rect = New-Object RECT
    if (-not [WinPos]::GetWindowRect($handle, [ref]$rect)) { return $null }
    return [pscustomobject]@{ X = $rect.Left; Y = $rect.Top
                              Width = ($rect.Right - $rect.Left); Height = ($rect.Bottom - $rect.Top) }
}

# ---- Step list parsing -------------------------------------------------------------

# Up here because Test-Settings validates the step list, and that runs as soon as you
# press Start, long before the watchdog functions below are defined.

function Get-StepKeyCode($keyName, $lineNumber)
{
    if ($keyName.Length -eq 1 -and $keyName -match '[A-Za-z0-9]')
    {
        return [byte][char]([string]$keyName).ToUpper()
    }
    # The ones worth naming: movement and camera keys people actually hold down
    $named = @{ space = 0x20; shift = 0x10; ctrl = 0x11; alt = 0x12; tab = 0x09; enter = 0x0D
                esc = 0x1B; up = 0x26; down = 0x28; left = 0x25; right = 0x27 }
    if ($named.ContainsKey($keyName.ToLower())) { return [byte]$named[$keyName.ToLower()] }
    throw "line $lineNumber : '$keyName' is not a letter, a digit, or one of $(($named.Keys | Sort-Object) -join ', ')"
}

function Get-StepList($stepText)
{
    # One step per line. Anything unrecognised is reported rather than ignored, so a
    # typo does not quietly turn into a sequence that clicks the wrong things.
    $steps = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0
    foreach ($line in ($stepText -split "`r?`n"))
    {
        $lineNumber++
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }

        if ($trimmed -match '^key\s+(\S+)$')
        {
            $steps.Add([pscustomobject]@{ Kind = "key"; Key = (Get-StepKeyCode $Matches[1] $lineNumber) })
        }
        elseif ($trimmed -match '^hold\s+(\S+)\s+(\d{1,6})$')
        {
            # Expanded here into down, wait, up. The runner then only ever deals with
            # instant steps, so a four second walk still costs one tick per step rather
            # than blocking for four seconds.
            $keyCode = Get-StepKeyCode $Matches[1] $lineNumber
            $steps.Add([pscustomobject]@{ Kind = "keydown"; Key = $keyCode })
            $steps.Add([pscustomobject]@{ Kind = "wait"; Milliseconds = [int]$Matches[2] })
            $steps.Add([pscustomobject]@{ Kind = "keyup"; Key = $keyCode })
        }
        elseif ($trimmed -match '^scroll\s+(-?\d{1,3})$')
        {
            $clicks = [int]$Matches[1]
            if ($clicks -eq 0 -or [math]::Abs($clicks) -gt 50)
            {
                throw "line $lineNumber : scroll needs a number of clicks between -50 and 50, not 0"
            }
            $steps.Add([pscustomobject]@{ Kind = "scroll"; Clicks = $clicks })
        }
        elseif ($trimmed -match '^click\s+([0-9]*\.?[0-9]+)\s*,\s*([0-9]*\.?[0-9]+)$')
        {
            $fractionX = [double]$Matches[1]
            $fractionY = [double]$Matches[2]
            if ($fractionX -lt 0 -or $fractionX -gt 1 -or $fractionY -lt 0 -or $fractionY -gt 1)
            {
                throw "line $lineNumber : click needs fractions of the window between 0 and 1"
            }
            $steps.Add([pscustomobject]@{ Kind = "click"; X = $fractionX; Y = $fractionY })
        }
        elseif ($trimmed -match '^wait\s+(\d{1,6})$')
        {
            $steps.Add([pscustomobject]@{ Kind = "wait"; Milliseconds = [int]$Matches[1] })
        }
        else
        {
            throw "line $lineNumber : '$trimmed' is not one of 'key X', 'hold X ms', 'click x,y', 'scroll n' or 'wait ms'"
        }
    }
    return $steps
}

# ---- Settings window ---------------------------------------------------------------

function Protect-Secret($plainText)
{
    # DPAPI: the ciphertext only decrypts for this Windows user on this machine
    if (-not $plainText) { return "" }
    return ConvertFrom-SecureString (ConvertTo-SecureString $plainText -AsPlainText -Force)
}

function Unprotect-Secret($protectedText)
{
    if (-not $protectedText) { return "" }
    try
    {
        $secure = ConvertTo-SecureString $protectedText
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try     { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
    catch
    {
        [System.Windows.Forms.MessageBox]::Show(
            "The saved RAM password could not be decrypted, so please type it again.",
            "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return ""
    }
}

function Get-DefaultSettings
{
    return @{
        MainAccount            = ""
        AltAccounts            = ""
        PlaceId                = ""
        PrivateServerLink      = ""
        AccountManagerPort     = "7963"
        AccountManagerPassword = ""
        MinimumFreeMegabytes   = "3000"
        RelaunchDelaySeconds   = "90"
        MaximumSessionMinutes  = "45"
        CloseOtherClients      = "True"
        FramerateCap           = "30"
        AntiIdleMinutes        = "15"
        AntiIdleKey            = "Space"
        AggressiveAntiIdle     = "False"
        ReapStrayMinutes       = "3"
        UseAllMonitors         = "True"
        DiscordWebhookUrl      = ""
        DiscordPingId          = ""
        DiscordSummaryMinutes  = "0"
        RememberWindowPositions = "True"
        StepList                = ""
        RunStepsOnRejoin        = "False"
    }
}

function Get-SavedSettings
{
    # Saved values are laid over the defaults, so a file written by an older version
    # keeps sensible defaults for keys it does not have yet
    $settings = Get-DefaultSettings

    $path = if (Test-Path $settingsPath) { $settingsPath }
            elseif (Test-Path $legacySettingsPath) { $legacySettingsPath }
            else { $null }
    if (-not $path) { return $settings }

    $json = Get-Content $path -Raw | ConvertFrom-Json
    foreach ($property in $json.PSObject.Properties)
    {
        $settings[$property.Name] = [string]$property.Value
    }

    if ($settings["AccountManagerPasswordProtected"])
    {
        $settings["AccountManagerPassword"] = Unprotect-Secret $settings["AccountManagerPasswordProtected"]
    }
    $settings.Remove("AccountManagerPasswordProtected")
    return $settings
}

function Protect-SettingsFile($path)
{
    # Owner only, inheritance off: the file holds the encrypted password
    try
    {
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            [Security.Principal.WindowsIdentity]::GetCurrent().User, "FullControl", "Allow")))
        Set-Acl -Path $path -AclObject $acl -ErrorAction Stop
    }
    catch
    {
        Write-Log "WARNING: could not restrict permissions on $path : $($_.Exception.Message)"
    }
}

function Save-Settings($settings)
{
    $toSave = @{}
    foreach ($key in $settings.Keys)
    {
        if ($key -eq "AccountManagerPassword") { continue }
        $toSave[$key] = $settings[$key]
    }
    $toSave["AccountManagerPasswordProtected"] = Protect-Secret $settings.AccountManagerPassword

    if (-not (Test-Path $settingsFolder))
    {
        New-Item -ItemType Directory -Path $settingsFolder -Force | Out-Null
    }
    $toSave | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
    Protect-SettingsFile $settingsPath

    # The old file kept the password in clear text, so it does not stay behind
    if ((Test-Path $legacySettingsPath) -and ($legacySettingsPath -ne $settingsPath))
    {
        Remove-Item $legacySettingsPath -Force -ErrorAction SilentlyContinue
        Write-Log "settings moved to $settingsPath, removed the old plain text $legacySettingsPath"
    }
}

function Show-SettingsWindow($saved)
{
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Roblox Watchdog"
    $form.Size = New-Object System.Drawing.Size(600, 800)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    # Scrolls rather than growing taller with every setting added, so it still fits on a
    # 1080p screen and there is room for more rows later
    $form.AutoScroll = $true
    Set-ThemedForm $form

    $inputs = @{}
    $rowTop = 15

    # $maskInput only decides whether the box shows dots instead of characters; it is
    # not a password itself. Named that way because an $isPassword parameter trips
    # PSScriptAnalyzer's PSAvoidUsingPlainTextForPassword rule on the name alone.
    function Add-Row($labelText, $key, $height, $maskInput)
    {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labelText
        $label.Location = New-Object System.Drawing.Point(15, $rowTop)
        # Generous width: the longest label needs ~160px at 100% scaling, and a label
        # that runs out of room wraps and gets clipped by its own height
        $label.Size = New-Object System.Drawing.Size(225, 20)
        # centred against the field, and top-aligned next to a multiline box
        $label.TextAlign = if ($height -gt 20) { "TopLeft" } else { "MiddleLeft" }
        $label.ForeColor = $themeMuted
        $form.Controls.Add($label)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(248, $rowTop)
        $textBox.Size = New-Object System.Drawing.Size(320, $height)
        Set-ThemedInput $textBox
        $textBox.Text = $saved[$key]
        if ($height -gt 20)
        {
            $textBox.Multiline = $true
            $textBox.AcceptsReturn = $true
            $textBox.ScrollBars = "Vertical"
        }
        if ($maskInput)
        {
            $textBox.UseSystemPasswordChar = $true
        }
        $form.Controls.Add($textBox)

        $inputs[$key] = $textBox
        Set-Variable -Name rowTop -Value ($rowTop + $height + 10) -Scope 1
    }

    Add-Row "Main username" "MainAccount" 20 $false
    Add-Row "Alt usernames (one per line)" "AltAccounts" 100 $false
    Add-Row "Place ID" "PlaceId" 20 $false
    Add-Row "Private server link (optional)" "PrivateServerLink" 20 $false
    Add-Row "RAM web server port" "AccountManagerPort" 20 $false
    Add-Row "RAM web server password" "AccountManagerPassword" 20 $true
    Add-Row "Kill an alt below free MB (0=off)" "MinimumFreeMegabytes" 20 $false
    Add-Row "Seconds between launches" "RelaunchDelaySeconds" 20 $false
    Add-Row "Relog alts after minutes" "MaximumSessionMinutes" 20 $false
    Add-Row "Frame rate cap (0=off)" "FramerateCap" 20 $false
    Add-Row "Anti-idle every min (0=off)" "AntiIdleMinutes" 20 $false
    Add-Row "Anti-idle key" "AntiIdleKey" 20 $false
    Add-Row "Close strays after min (0=off)" "ReapStrayMinutes" 20 $false
    Add-Row "Discord alerts every min (0=off)" "DiscordSummaryMinutes" 20 $false
    Add-Row "Discord id to ping for main" "DiscordPingId" 20 $false

    # Its own row rather than Add-Row, to leave space for the Test button beside it
    $webhookLabel = New-Object System.Windows.Forms.Label
    $webhookLabel.Text = "Discord webhook (optional)"
    $webhookLabel.Location = New-Object System.Drawing.Point(15, $rowTop)
    $webhookLabel.Size = New-Object System.Drawing.Size(225, 20)
    $webhookLabel.TextAlign = "MiddleLeft"
    $webhookLabel.ForeColor = $themeMuted
    $form.Controls.Add($webhookLabel)

    $webhookBox = New-Object System.Windows.Forms.TextBox
    $webhookBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $webhookBox.Size = New-Object System.Drawing.Size(252, 20)
    $webhookBox.Text = $saved["DiscordWebhookUrl"]
    Set-ThemedInput $webhookBox
    $form.Controls.Add($webhookBox)
    $inputs["DiscordWebhookUrl"] = $webhookBox

    $testButton = New-Object System.Windows.Forms.Button
    $testButton.Text = "Test"
    $testButton.Location = New-Object System.Drawing.Point(506, ($rowTop - 1))
    $testButton.Size = New-Object System.Drawing.Size(62, 23)
    Set-ThemedButton $testButton $false
    $testButton.Add_Click({
        # Sent straight away rather than through the queue, so the result can be shown
        $url = $webhookBox.Text.Trim()
        if ($url -notmatch '^https://(discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+$')
        {
            [System.Windows.Forms.MessageBox]::Show("That does not look like a Discord webhook url.",
                "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        try
        {
            $body = @{ embeds = @(@{ title = "Test message"
                                     description = "The webhook works. Alerts will arrive here."
                                     color = $alertGreen }) } | ConvertTo-Json -Depth 5 -Compress
            $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, "application/json")
            $response = $httpClient.PostAsync($url, $content).GetAwaiter().GetResult()
            if ($response.IsSuccessStatusCode)
            {
                [System.Windows.Forms.MessageBox]::Show("Sent. Check the channel.", "Roblox Watchdog",
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            else
            {
                [System.Windows.Forms.MessageBox]::Show("Discord replied $([int]$response.StatusCode) '$($response.ReasonPhrase)'.",
                    "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
        }
        catch
        {
            [System.Windows.Forms.MessageBox]::Show("Could not reach Discord: $($_.Exception.GetBaseException().Message)",
                "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    })
    $form.Controls.Add($testButton)
    $rowTop += 30

    # Closing other clients is destructive, so it is a deliberate choice
    $closeOthersBox = New-Object System.Windows.Forms.CheckBox
    $closeOthersBox.Text = "Close other Roblox windows on start"
    $closeOthersBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $closeOthersBox.Size = New-Object System.Drawing.Size(320, 20)
    $closeOthersBox.Checked = ($saved["CloseOtherClients"] -ne "False")
    $closeOthersBox.FlatStyle = "Flat"                                                # so the box itself follows the dark background
    $closeOthersBox.ForeColor = $themeText
    $form.Controls.Add($closeOthersBox)
    $rowTop += 26

    $allMonitorsBox = New-Object System.Windows.Forms.CheckBox
    $allMonitorsBox.Text = "Spread the windows over all monitors"
    $allMonitorsBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $allMonitorsBox.Size = New-Object System.Drawing.Size(320, 20)
    $allMonitorsBox.Checked = ($saved["UseAllMonitors"] -ne "False")
    $allMonitorsBox.FlatStyle = "Flat"
    $allMonitorsBox.ForeColor = $themeText
    $form.Controls.Add($allMonitorsBox)
    $rowTop += 26

    $aggressiveIdleBox = New-Object System.Windows.Forms.CheckBox
    $aggressiveIdleBox.Text = "Aggressive anti-idle (more input, twice as often)"
    $aggressiveIdleBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $aggressiveIdleBox.Size = New-Object System.Drawing.Size(320, 20)
    $aggressiveIdleBox.Checked = ($saved["AggressiveAntiIdle"] -eq "True")
    $aggressiveIdleBox.FlatStyle = "Flat"
    $aggressiveIdleBox.ForeColor = $themeText
    $form.Controls.Add($aggressiveIdleBox)
    $rowTop += 26

    $rememberPositionsBox = New-Object System.Windows.Forms.CheckBox
    $rememberPositionsBox.Text = "Put windows back where I dragged them"
    $rememberPositionsBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $rememberPositionsBox.Size = New-Object System.Drawing.Size(320, 20)
    $rememberPositionsBox.Checked = ($saved["RememberWindowPositions"] -ne "False")
    $rememberPositionsBox.FlatStyle = "Flat"
    $rememberPositionsBox.ForeColor = $themeText
    $form.Controls.Add($rememberPositionsBox)
    $rowTop += 30

    # Step list: its own multiline box with a Pick button, since a coordinate you have
    # to type is both miserable and wrong the moment a window moves
    $stepsLabel = New-Object System.Windows.Forms.Label
    $stepsLabel.Text = "Steps to run on main"
    $stepsLabel.Location = New-Object System.Drawing.Point(15, $rowTop)
    $stepsLabel.Size = New-Object System.Drawing.Size(225, 20)
    $stepsLabel.ForeColor = $themeMuted
    $form.Controls.Add($stepsLabel)

    $stepsHint = New-Object System.Windows.Forms.Label
    $stepsHint.Text = "key 2   hold w 4200" + [char]0x2003 + "scroll -6" + [char]0x2003 + "click 0.5,0.6   wait 7000"
    $stepsHint.Location = New-Object System.Drawing.Point(15, ($rowTop + 20))
    $stepsHint.Size = New-Object System.Drawing.Size(225, 34)
    $stepsHint.ForeColor = $themeMuted
    $form.Controls.Add($stepsHint)

    $stepsBox = New-Object System.Windows.Forms.TextBox
    $stepsBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $stepsBox.Size = New-Object System.Drawing.Size(252, 90)
    $stepsBox.Multiline = $true
    $stepsBox.AcceptsReturn = $true
    $stepsBox.ScrollBars = "Vertical"
    $stepsBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $stepsBox.Text = $saved["StepList"]
    Set-ThemedInput $stepsBox
    $form.Controls.Add($stepsBox)
    $inputs["StepList"] = $stepsBox

    $pickButton = New-Object System.Windows.Forms.Button
    $pickButton.Text = "Pick"
    $pickButton.Location = New-Object System.Drawing.Point(506, ($rowTop - 1))
    $pickButton.Size = New-Object System.Drawing.Size(62, 23)
    Set-ThemedButton $pickButton $false
    $pickButton.Add_Click({
        $mainProcess = $null
        foreach ($candidate in (Get-Process $processName -ErrorAction SilentlyContinue | Sort-Object StartTime))
        {
            $candidate.Refresh()
            if ($candidate.MainWindowHandle -ne [IntPtr]::Zero) { $mainProcess = $candidate; break }
        }
        if (-not $mainProcess)
        {
            [System.Windows.Forms.MessageBox]::Show("No Roblox window is open to pick a spot in.",
                "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $windowRect = Get-WindowRectangle $mainProcess.MainWindowHandle
        if (-not $windowRect) { return }

        [System.Windows.Forms.MessageBox]::Show(
            "Click the spot you want, inside the Roblox window.`r`n`r`nPress Escape to cancel.",
            "Pick a spot", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

        # Polled rather than hooked: a global mouse hook in a WinForms app this size is
        # far more trouble than reading the button state a few times a second
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline)
        {
            if ([Win32.Window]::GetAsyncKeyState(0x1B) -ne 0) { return }               # VK_ESCAPE
            if ([Win32.Window]::GetAsyncKeyState(0x01) -lt 0)                          # VK_LBUTTON, high bit = down
            {
                $point = New-Object POINT
                if (-not [WinPos]::GetCursorPos([ref]$point)) { return }
                $fractionX = [math]::Round((($point.X - $windowRect.X) / $windowRect.Width), 4)
                $fractionY = [math]::Round((($point.Y - $windowRect.Y) / $windowRect.Height), 4)
                if ($fractionX -lt 0 -or $fractionX -gt 1 -or $fractionY -lt 0 -or $fractionY -gt 1)
                {
                    [System.Windows.Forms.MessageBox]::Show("That click was outside the Roblox window.",
                        "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                    return
                }
                $newLine = "click $fractionX,$fractionY"
                if ($stepsBox.Text -and -not $stepsBox.Text.EndsWith("`n")) { $stepsBox.AppendText("`r`n") }
                $stepsBox.AppendText($newLine)
                while ([Win32.Window]::GetAsyncKeyState(0x01) -lt 0) { Start-Sleep -Milliseconds 50 }
                return
            }
            Start-Sleep -Milliseconds 40
        }
    })
    $form.Controls.Add($pickButton)
    $rowTop += 100

    $runOnRejoinBox = New-Object System.Windows.Forms.CheckBox
    $runOnRejoinBox.Text = "Run the steps by itself when main rejoins"
    $runOnRejoinBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $runOnRejoinBox.Size = New-Object System.Drawing.Size(320, 20)
    $runOnRejoinBox.Checked = ($saved["RunStepsOnRejoin"] -eq "True")
    $runOnRejoinBox.FlatStyle = "Flat"
    $runOnRejoinBox.ForeColor = $themeText
    $form.Controls.Add($runOnRejoinBox)
    $rowTop += 30

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "A running client is adopted as main; otherwise main is launched."
    $note.Location = New-Object System.Drawing.Point(15, $rowTop)
    $note.Size = New-Object System.Drawing.Size(553, 20)
    $note.ForeColor = $themeMuted
    $form.Controls.Add($note)

    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "Start"
    $startButton.Location = New-Object System.Drawing.Point(468, ($rowTop + 30))
    $startButton.Size = New-Object System.Drawing.Size(100, 30)
    $startButton.DialogResult = "OK"
    Set-ThemedButton $startButton $true
    $form.Controls.Add($startButton)
    $form.AcceptButton = $startButton

    # $null rather than exiting, so the status window can reopen this dialog later
    # and a cancel just means "never mind" instead of closing the whole app
    if ($form.ShowDialog() -ne "OK")
    {
        $form.Dispose()
        return $null
    }

    $result = @{}
    foreach ($key in $inputs.Keys)
    {
        $result[$key] = $inputs[$key].Text.Trim()
    }
    $result["CloseOtherClients"] = [string]$closeOthersBox.Checked
    $result["UseAllMonitors"] = [string]$allMonitorsBox.Checked
    $result["AggressiveAntiIdle"] = [string]$aggressiveIdleBox.Checked
    $result["RememberWindowPositions"] = [string]$rememberPositionsBox.Checked
    $result["RunStepsOnRejoin"] = [string]$runOnRejoinBox.Checked
    return $result
}

function Test-Settings($settings)
{
    if (-not $settings.MainAccount) { throw "Main username is required" }
    if (-not $settings.AltAccounts) { throw "At least one alt username is required" }
    if (($settings.AltAccounts -split "`r?`n" | ForEach-Object { $_.Trim() }) -contains $settings.MainAccount)
    {
        throw "Main username must not also be in the alt list"
    }
    if ($settings.PlaceId -notmatch '^\d{1,19}$') { throw "Place ID must be a number" }
    if ($settings.AccountManagerPort -notmatch '^\d{1,5}$') { throw "Port must be a number" }
    if ([int]$settings.AccountManagerPort -lt 1 -or [int]$settings.AccountManagerPort -gt 65535)
    {
        throw "Port must be between 1 and 65535"
    }
    if ($settings.AccountManagerPassword.Length -lt 6) { throw "RAM password must match the Webserver Password in RAM (RAM requires 6+ characters for LaunchAccount)" }

    # The link is handed straight to RAM, which turns it into a private game join. Any
    # other Roblox url used to be accepted here, and a plain game link looks close enough
    # to paste by mistake: it then joins with no permission and the client shows error
    # 524, over and over, which is a miserable thing to debug from the other end.
    if ($settings.PrivateServerLink)
    {
        $shareLink = $settings.PrivateServerLink -match '^https://(www\.)?roblox\.com/share\?.*\bcode=[A-Za-z0-9_-]+' -and
                     $settings.PrivateServerLink -match 'type=Server'
        $classicLink = $settings.PrivateServerLink -match '^https://(www\.)?roblox\.com/games/\d+.*[?&]privateServerLinkCode=[A-Za-z0-9_-]+'
        if (-not ($shareLink -or $classicLink))
        {
            throw ("Private server link must be a private server link, not an ordinary game link.`r`n`r`n" +
                   "Either of these is fine:`r`n" +
                   "  https://www.roblox.com/share?code=...&type=Server`r`n" +
                   "  https://www.roblox.com/games/<id>/...?privateServerLinkCode=...`r`n`r`n" +
                   "In Roblox, open the private server and use its invite link. Leave this empty to join a public server.")
        }
    }

    foreach ($key in "MinimumFreeMegabytes", "RelaunchDelaySeconds", "MaximumSessionMinutes")
    {
        if ($settings[$key] -notmatch '^\d{1,9}$') { throw "$key must be a number" }
    }
    # 0 turns it off, for machines that sit at full memory all the time where closing an
    # alt every ten seconds is worse than letting it run
    $freeMegabytesSetting = [int]$settings.MinimumFreeMegabytes
    if ($freeMegabytesSetting -ne 0 -and $freeMegabytesSetting -lt 100)
    {
        throw "Kill an alt below free MB must be 0, or at least 100"
    }
    if ([int]$settings.RelaunchDelaySeconds -lt 5)   { throw "Seconds between launches must be at least 5" }
    if ([int]$settings.MaximumSessionMinutes -lt 5)  { throw "Relog alts after minutes must be at least 5" }

    # 0 leaves Roblox's own setting alone; otherwise keep it in a sane range
    if ($settings.FramerateCap -notmatch '^\d{1,3}$') { throw "Frame rate cap must be a number (0 to leave it alone)" }
    $cap = [int]$settings.FramerateCap
    if ($cap -ne 0 -and ($cap -lt 15 -or $cap -gt 360)) { throw "Frame rate cap must be 0, or between 15 and 360" }

    # Roblox kicks at 20 minutes idle, so the interval has to leave room to get there
    if ($settings.AntiIdleMinutes -notmatch '^\d{1,2}$') { throw "Anti-idle minutes must be a number (0 to turn it off)" }
    $idle = [int]$settings.AntiIdleMinutes
    if ($idle -ne 0 -and ($idle -lt 1 -or $idle -gt 18)) { throw "Anti-idle minutes must be 0, or between 1 and 18 (Roblox kicks at 20)" }
    if ($settings.AntiIdleKey -notmatch '^(Space|[A-Za-z])$') { throw "Anti-idle key must be Space or a single letter" }

    # Grace period before an untracked windowless client counts as a stray. Must be
    # longer than a launch takes, or a client still starting up would be killed
    if ($settings.ReapStrayMinutes -notmatch '^\d{1,3}$') { throw "Close strays after minutes must be a number (0 to turn it off)" }
    $reap = [int]$settings.ReapStrayMinutes
    if ($reap -ne 0 -and ($reap -lt 2 -or $reap -gt 120)) { throw "Close strays after minutes must be 0, or between 2 and 120" }

    # Checked so a mistyped url fails here rather than silently never alerting
    if ($settings.DiscordWebhookUrl -and
        $settings.DiscordWebhookUrl -notmatch '^https://(discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+$')
    {
        throw "Discord webhook must be a https://discord.com/api/webhooks/... url, or empty"
    }
    # A Discord user or role id is a 17 to 20 digit snowflake. Accepted with or without
    # the <@...> wrapper, since that is what you get from Copy ID in some clients.
    if ($settings.DiscordPingId)
    {
        if ($settings.DiscordPingId -notmatch '^<?@?&?(\d{17,20})>?$')
        {
            throw "Discord id to ping must be a user or role id (17 to 20 digits), or empty"
        }
        $settings.DiscordPingId = $Matches[1]
    }
    # Checked here so a typo is caught while you are looking at the dialog, rather than
    # halfway through a run that is already clicking things
    if ($settings.StepList)
    {
        try { Get-StepList $settings.StepList | Out-Null }
        catch { throw "Steps: $($_.Exception.Message)" }
    }
    if ($settings.DiscordSummaryMinutes -notmatch '^\d{1,4}$') { throw "Discord alerts every minutes must be a number (0 to turn it off)" }
    $summary = [int]$settings.DiscordSummaryMinutes
    if ($summary -ne 0 -and ($summary -lt 5 -or $summary -gt 1440)) { throw "Discord alerts every minutes must be 0, or between 5 and 1440" }
}

# Reopen the window on a bad value instead of throwing away everything that was typed
$settings = Get-SavedSettings

# Restarted after a crash: nobody is sitting there to press Start, so it goes straight
# in on what was saved. If those settings are not usable it falls through to the dialog.
if ($autoStarted)
{
    try
    {
        Test-Settings $settings
        $skipSettingsDialog = $true
    }
    catch
    {
        $skipSettingsDialog = $false
    }
}

while (-not $skipSettingsDialog)
{
    $settings = Show-SettingsWindow $settings
    if (-not $settings) { exit 0 }                                                   # cancelled on the way in
    try
    {
        Test-Settings $settings
        break
    }
    catch
    {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Check your settings",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}
Save-Settings $settings

$mainAccount = $settings.MainAccount
$altAccounts = $settings.AltAccounts -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$placeId = $settings.PlaceId
$privateServerLink = $settings.PrivateServerLink                                     # full link, RAM resolves it; empty = public
$accountManagerPort = [int]$settings.AccountManagerPort
$accountManagerPassword = $settings.AccountManagerPassword
$minimumFreeMegabytes = [int]$settings.MinimumFreeMegabytes
$relaunchDelaySeconds = [int]$settings.RelaunchDelaySeconds
$maximumSessionMinutes = [int]$settings.MaximumSessionMinutes
$closeOtherClients = ($settings.CloseOtherClients -ne "False")
$framerateCap = [int]$settings.FramerateCap
$antiIdleMinutes = [int]$settings.AntiIdleMinutes
$antiIdleKey = $settings.AntiIdleKey
$aggressiveAntiIdle = ($settings.AggressiveAntiIdle -eq "True")
# A-Z virtual key codes are the same numbers as their uppercase characters
$antiIdleVirtualKey = if ($antiIdleKey -eq "Space") { [byte]0x20 } else { [byte][char]([string]$antiIdleKey).ToUpper() }
$reapStrayMinutes = [int]$settings.ReapStrayMinutes
$useAllMonitors = ($settings.UseAllMonitors -ne "False")
$discordWebhookUrl = $settings.DiscordWebhookUrl
$discordPingId = $settings.DiscordPingId
$discordSummaryMinutes = [int]$settings.DiscordSummaryMinutes
$rememberWindowPositions = ($settings.RememberWindowPositions -ne "False")
$stepListText = $settings.StepList
$runStepsOnRejoin = ($settings.RunStepsOnRejoin -eq "True")
$reportedStrays = @{}                                                                # windowed strays already mentioned, so the log is not spammed

# ---- Watchdog ----------------------------------------------------------------------

function Get-RobloxClients
{
    Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object { $_.WorkingSet64 -gt $minimumClientBytes }
}

function Get-FreeMegabytes
{
    # AvailableMBytes matches the "Available" figure in Task Manager; the raw perf class
    # is used instead of a PerformanceCounter because those category names are localised
    $performance = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction SilentlyContinue
    if ($performance -and $performance.AvailableMBytes) { return [double]$performance.AvailableMBytes }
    return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1024
}

function Set-RobloxFramerateCap
{
    # Roblox reads this once at client startup and rewrites the file when a client
    # exits, so a closing client resets it to unlimited; reassert it before launching
    if ($framerateCap -le 0) { return }
    $path = Join-Path $env:LOCALAPPDATA "Roblox\GlobalBasicSettings_13.xml"
    if (-not (Test-Path $path)) { return }
    try
    {
        $raw = [System.IO.File]::ReadAllText($path)
        $new = [regex]::Replace($raw, '(<int name="FramerateCap">)(-?\d+)(</int>)', "`${1}$framerateCap`${3}")
        if ($new -ne $raw)
        {
            # written back exactly as Roblox writes it: UTF-8 without BOM
            [System.IO.File]::WriteAllText($path, $new, (New-Object System.Text.UTF8Encoding($false)))
            Write-Log "set Roblox frame rate cap to $framerateCap"
        }
    }
    catch
    {
        Write-Log "WARNING: could not set the frame rate cap: $($_.Exception.Message)"
    }
}

function Get-SessionProcess($session)
{
    # Windows recycles PIDs, so the start time has to match before we trust the id
    if (-not $session.ProcessId) { return $null }
    $process = Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -ne $processName) { return $null }
    if ($session.ProcessStartTime -and $process.StartTime -ne $session.ProcessStartTime) { return $null }
    return $process
}

function Get-TilingScreens
{
    # Primary first so main keeps slot 0 on the screen you actually look at, then the
    # rest left to right
    if (-not $useAllMonitors)
    {
        return @([System.Windows.Forms.Screen]::PrimaryScreen)
    }
    return @([System.Windows.Forms.Screen]::AllScreens |
             Sort-Object @{ Expression = { -not $_.Primary } }, @{ Expression = { $_.Bounds.X } })
}

function Get-SavedWindowPositions
{
    $positions = @{}
    if (-not $rememberWindowPositions) { return $positions }
    try
    {
        if (Test-Path $positionsPath)
        {
            $json = Get-Content $positionsPath -Raw | ConvertFrom-Json
            foreach ($property in $json.PSObject.Properties)
            {
                $positions[$property.Name] = [string]$property.Value
            }
        }
    }
    catch
    {
        Write-Log "WARNING: could not read the saved window positions: $($_.Exception.Message)"
    }
    return $positions
}

function Save-WindowPosition($accountName, $rectangleText)
{
    # Written as "x,y,width,height" per account, in its own file so the settings file
    # stays a flat list of strings
    if (-not $rememberWindowPositions) { return }
    try
    {
        $positions = Get-SavedWindowPositions
        if ($positions[$accountName] -eq $rectangleText) { return }                   # nothing new to write
        $positions[$accountName] = $rectangleText
        $positions | ConvertTo-Json | Set-Content $positionsPath -Encoding UTF8
        Write-Log "remembered where $accountName was moved to ($rectangleText)"
    }
    catch
    {
        Write-Log "WARNING: could not save the window position for $accountName : $($_.Exception.Message)"
    }
}

function Get-SlotRectangle($slotIndex)
{
    # Accounts are shared out between the screens in proportion to their area, then
    # tiled inside each one. Tiling across the whole desktop as a single grid would be
    # simpler but would leave windows straddling the gap between two monitors.
    $screens = Get-TilingScreens
    $accountCount = [math]::Max($allAccounts.Count, 1)

    $areas = @($screens | ForEach-Object { [double]($_.WorkingArea.Width * $_.WorkingArea.Height) })
    $totalArea = ($areas | Measure-Object -Sum).Sum

    # Largest-remainder share-out, so the counts always add up to the account count
    $exactShares = @(0..($screens.Count - 1) | ForEach-Object { $accountCount * $areas[$_] / $totalArea })
    $counts = @($exactShares | ForEach-Object { [int][math]::Floor($_) })
    $remaining = $accountCount - (($counts | Measure-Object -Sum).Sum)
    if ($remaining -gt 0)
    {
        $byRemainder = @(0..($screens.Count - 1) |
            Sort-Object @{ Expression = { $exactShares[$_] - [math]::Floor($exactShares[$_]) }; Descending = $true })
        for ($step = 0; $step -lt $remaining; $step++)
        {
            $counts[$byRemainder[$step % $screens.Count]]++
        }
    }

    $cursor = 0
    for ($index = 0; $index -lt $screens.Count; $index++)
    {
        $onThisScreen = $counts[$index]
        if ($onThisScreen -gt 0 -and $slotIndex -lt ($cursor + $onThisScreen))
        {
            $localIndex = $slotIndex - $cursor
            $columns = [math]::Ceiling([math]::Sqrt($onThisScreen))
            $rows = [math]::Ceiling($onThisScreen / $columns)
            $area = $screens[$index].WorkingArea
            $tileWidth = [int]($area.Width / $columns)
            $tileHeight = [int]($area.Height / $rows)
            return [pscustomobject]@{
                X = $area.X + ($localIndex % $columns) * $tileWidth
                Y = $area.Y + [math]::Floor($localIndex / $columns) * $tileHeight
                Width = $tileWidth
                Height = $tileHeight
                ScreenNumber = $index + 1
                ScreenCount = $screens.Count
            }
        }
        $cursor += $onThisScreen
    }

    # More accounts than the share-out covered: fall back to the primary, full size
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    return [pscustomobject]@{ X = $area.X; Y = $area.Y; Width = $area.Width; Height = $area.Height
                              ScreenNumber = 1; ScreenCount = $screens.Count }
}

function Set-ClientWindow($accountName, $processId)
{
    # Nothing here waits: the Tiling state does the waiting, one step per tick, so the
    # status window stays responsive instead of freezing for a minute per launch
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    $process.Refresh()
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }

    $slotIndex = [array]::IndexOf($allAccounts, $accountName)

    # Where you dragged it to wins over the computed grid
    $slot = Get-SlotRectangle $slotIndex
    $x = $slot.X
    $y = $slot.Y
    $tileWidth = $slot.Width
    $tileHeight = $slot.Height
    $fromMemory = $false

    $savedPositions = Get-SavedWindowPositions
    if ($savedPositions.ContainsKey($accountName))
    {
        $parts = $savedPositions[$accountName] -split ','
        if ($parts.Count -eq 4)
        {
            $x = [int]$parts[0]; $y = [int]$parts[1]
            $tileWidth = [int]$parts[2]; $tileHeight = [int]$parts[3]
            $fromMemory = $true
        }
    }

    [Win32.Window]::ShowWindow($process.MainWindowHandle, 9) | Out-Null   # SW_RESTORE, MoveWindow ignores maximized windows
    $moved = [Win32.Window]::MoveWindow($process.MainWindowHandle, $x, $y, $tileWidth, $tileHeight, $true)

    # Read the window back instead of trusting the call. A normal process is not allowed
    # to move an elevated client's window, and this used to be logged as a success
    # anyway, so the log claimed the windows were tiled when nothing had moved.
    Start-Sleep -Milliseconds 250
    $rect = New-Object RECT
    $readBack = [WinPos]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
    # Roblox nudges its own window by a few pixels after the move, so allow some slack
    $offBy = if ($readBack) { [math]::Max([math]::Abs($rect.Left - $x), [math]::Abs($rect.Top - $y)) } else { 99999 }

    if ($moved -and $readBack -and $offBy -le 40)
    {
        # Remembered so a later manual drag can be told apart from where we put it
        $sessions[$accountName].AppliedRect = "$x,$y,$tileWidth,$tileHeight"
        $where = if ($fromMemory) { "where you left it" } else
        {
            "slot $slotIndex" + $(if ($slot.ScreenCount -gt 1) { " on screen $($slot.ScreenNumber)" } else { "" })
        }
        Write-Log "moved $accountName (PID $processId) to $where ($x,$y $($tileWidth)x$($tileHeight))"
        return $true
    }

    Write-Log "WARNING: $accountName (PID $processId) did not move (asked for $x,$y, it sits at $($rect.Left),$($rect.Top))"
    Write-ElevationHint
    return $false
}

function Remove-StrayClients
{
    # Roblox relaunches its own clients into "systray mode" every few hours. The
    # original exits and gets picked up as "is gone", but the process it spawned stays
    # alive with no window and never joins a game, so they pile up until someone
    # clears them out of Task Manager. Anything we did not launch, has no window, and
    # has outlived the grace period is one of those.
    if ($reapStrayMinutes -le 0) { return }

    $trackedIds = @($sessions.Values | ForEach-Object { $_.ProcessId } | Where-Object { $_ -ne 0 })
    $cutoff = (Get-Date).AddMinutes(-$reapStrayMinutes)
    $clients = @(Get-Process $processName -ErrorAction SilentlyContinue)

    # Forget PIDs that are gone, so the table cannot grow forever and a reused PID is
    # reported again rather than staying silently suppressed
    $livePids = @($clients | ForEach-Object { $_.Id })
    foreach ($key in @($reportedStrays.Keys))
    {
        if ($livePids -notcontains $key) { $reportedStrays.Remove($key) }
    }

    foreach ($process in $clients)
    {
        if ($trackedIds -contains $process.Id) { continue }
        try
        {
            if ($process.StartTime -gt $cutoff) { continue }                          # still within its grace period
            $process.Refresh()

            if ($process.MainWindowHandle -eq [IntPtr]::Zero)
            {
                $ageMinutes = ((Get-Date) - $process.StartTime).TotalMinutes
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $script:strayClosedCount++
                Write-Log "closed stray PID $($process.Id) (no window, $([int]$ageMinutes) min old, $([int]($process.WorkingSet64 / 1MB)) MB)"
            }
            elseif (-not $reportedStrays.ContainsKey($process.Id))
            {
                # It has a window, so it could be a client started by hand. Left alone
                # on purpose, but said once so it is not a surprise.
                $reportedStrays[$process.Id] = $true
                Write-Log "note: PID $($process.Id) is an untracked client with a window, leaving it alone"
            }
        }
        catch
        {
            # Once per process, not once per tick: this used to repeat every ten seconds
            if (-not $reportedStrays.ContainsKey($process.Id))
            {
                $reportedStrays[$process.Id] = $true
                Write-Log "WARNING: could not close stray PID $($process.Id): $($_.Exception.Message)"
                Write-ElevationHint
            }
        }
    }
}

function Set-WindowFocused($handle)
{
    # Roblox only counts input while its window has focus, so anything that sends input
    # has to get it first. Windows refuses SetForegroundWindow unless the caller already
    # owns the foreground, and SwitchToThisWindow is not bound by that.
    # 400ms, which is what anti-idle used before this was pulled out into a shared
    # helper. Extracting it quietly halved the wait, and focus timing is finicky enough
    # that there was no reason to.
    [Win32.Window]::ShowWindow($handle, 9) | Out-Null                                 # SW_RESTORE, a minimised window cannot take focus
    [Win32.Window]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds 400
    if ([Win32.Window]::GetForegroundWindow() -eq $handle) { return $true }

    [Win32.Window]::SwitchToThisWindow($handle, $true)
    Start-Sleep -Milliseconds 400
    return ([Win32.Window]::GetForegroundWindow() -eq $handle)
}

# ---- Step list ---------------------------------------------------------------------

function Start-StepRun($reason)
{
    if ($script:stepRun.Active) { return }
    if (-not $stepListText) { return }

    try
    {
        $steps = Get-StepList $stepListText
    }
    catch
    {
        Write-Log "ERROR: the step list has a problem, $($_.Exception.Message)"
        return
    }
    if ($steps.Count -eq 0) { return }

    $session = $sessions[$mainAccount]
    if ($session.State -ne "Running" -or -not $session.JoinedAt)
    {
        Write-Log "not running the steps: $mainAccount is not in the game"
        return
    }

    $script:stepRun = @{ Active = $true; Steps = $steps; Index = 0; NextAt = (Get-Date); Reason = $reason; HeldKey = $null }
    Write-Log "running $($steps.Count) steps on $mainAccount ($reason)"
}

function Stop-StepRun($reason)
{
    if (-not $script:stepRun.Active) { return }

    # A run aborted in the middle of a hold would otherwise leave the key down and the
    # character walking off on its own
    if ($script:stepRun.HeldKey)
    {
        $heldKey = [byte]$script:stepRun.HeldKey
        $scanCode = [byte]([Win32.Window]::MapVirtualKey($heldKey, 0))
        [Win32.Window]::keybd_event($heldKey, $scanCode, 2, [UIntPtr]::Zero)          # KEYEVENTF_KEYUP
        Write-Log "released the key that was being held"
    }

    Write-Log "step run stopped after $($script:stepRun.Index) of $($script:stepRun.Steps.Count) steps: $reason"
    $script:stepRun = @{ Active = $false; Steps = @(); Index = 0; NextAt = $null; Reason = $null; HeldKey = $null }
}

function Step-StepRun
{
    # One step per tick at most, so a sequence with long waits in it never blocks the
    # window the way the old launch code did
    if (-not $script:stepRun.Active) { return }
    if ((Get-Date) -lt $script:stepRun.NextAt) { return }

    $session = $sessions[$mainAccount]
    if ($session.State -ne "Running" -or -not $session.JoinedAt)
    {
        Stop-StepRun "$mainAccount left the game"
        return
    }

    if ($script:stepRun.Index -ge $script:stepRun.Steps.Count)
    {
        Write-Log "step run finished on $mainAccount"
        Stop-StepRun "finished"
        return
    }

    $step = $script:stepRun.Steps[$script:stepRun.Index]
    $script:stepRun.Index++

    if ($step.Kind -eq "wait")
    {
        $script:stepRun.NextAt = (Get-Date).AddMilliseconds($step.Milliseconds)
        return
    }

    $process = Get-SessionProcess $session
    if (-not $process) { Stop-StepRun "$mainAccount is gone"; return }
    $process.Refresh()
    $handle = $process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) { Stop-StepRun "$mainAccount has no window"; return }

    if (-not (Set-WindowFocused $handle))
    {
        Stop-StepRun "could not focus $mainAccount"
        Write-ElevationHint
        return
    }

    if ($step.Kind -eq "key")
    {
        $scanCode = [byte]([Win32.Window]::MapVirtualKey($step.Key, 0))
        [Win32.Window]::keybd_event($step.Key, $scanCode, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
        [Win32.Window]::keybd_event($step.Key, $scanCode, 2, [UIntPtr]::Zero)
    }
    elseif ($step.Kind -eq "keydown")
    {
        # Left held while the following wait step runs, which is how walking works
        $scanCode = [byte]([Win32.Window]::MapVirtualKey($step.Key, 0))
        [Win32.Window]::keybd_event($step.Key, $scanCode, 0, [UIntPtr]::Zero)
        $script:stepRun.HeldKey = $step.Key
    }
    elseif ($step.Kind -eq "keyup")
    {
        $scanCode = [byte]([Win32.Window]::MapVirtualKey($step.Key, 0))
        [Win32.Window]::keybd_event($step.Key, $scanCode, 2, [UIntPtr]::Zero)
        $script:stepRun.HeldKey = $null
    }
    elseif ($step.Kind -eq "scroll")
    {
        # The wheel goes to whatever is under the pointer, so it has to be over the
        # window first or the zoom lands on something else entirely
        $windowRect = Get-WindowRectangle $handle
        if (-not $windowRect) { Stop-StepRun "could not read the window position"; return }
        [Win32.Window]::SetCursorPos([int]($windowRect.X + $windowRect.Width / 2),
                                     [int]($windowRect.Y + $windowRect.Height / 2)) | Out-Null
        Start-Sleep -Milliseconds 40
        # One notch is 120, negative scrolls back, which is zoom out in Roblox
        [Win32.Window]::mouse_event(0x0800, 0, 0, [uint32]($step.Clicks * 120), [UIntPtr]::Zero)
    }
    elseif ($step.Kind -eq "click")
    {
        # Fractions of the window, not screen pixels, so the same list works whichever
        # monitor the window ended up on and whatever size the tile is
        $windowRect = Get-WindowRectangle $handle
        if (-not $windowRect) { Stop-StepRun "could not read the window position"; return }
        $targetX = [int]($windowRect.X + ($windowRect.Width * $step.X))
        $targetY = [int]($windowRect.Y + ($windowRect.Height * $step.Y))
        [Win32.Window]::SetCursorPos($targetX, $targetY) | Out-Null
        Start-Sleep -Milliseconds 40
        [Win32.Window]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)                 # left down
        Start-Sleep -Milliseconds 50
        [Win32.Window]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)                 # left up
    }

    # Steps with no explicit wait still get a moment, or the game sees them as one action
    $script:stepRun.NextAt = (Get-Date).AddMilliseconds($stepGapMilliseconds)
}

function Get-AntiIdleInterval
{
    # Aggressive mode goes twice as often, with a floor of one minute. Roblox pulls the
    # plug at 20, so the normal setting is already capped at 18 in the settings window.
    if (-not $aggressiveAntiIdle) { return $antiIdleMinutes }
    return [math]::Max(1, [int][math]::Floor($antiIdleMinutes / 2))                     # floor, so 15 becomes 7 rather than 8

}

function Send-AntiIdleInput($accountName)
{
    # Roblox kicks a client after 20 minutes without input, and it only counts input
    # while its window has focus, so the window has to be brought to the front first.
    # Whatever the user was working in gets the focus back afterwards.
    $session = $sessions[$accountName]
    $process = Get-SessionProcess $session
    if (-not $process) { return }

    $process.Refresh()
    $handle = $process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero)
    {
        Write-Log "WARNING: $accountName has no window, skipping anti-idle"
        return
    }

    $previous = [Win32.Window]::GetForegroundWindow()                                 # give this back when done

    # Focus is refused often enough to matter: 1301 of 5867 attempts in one log, 22%,
    # and every refusal used to mean waiting another minute. Windows hands focus over
    # far more readily on the second or third ask, so ask again here instead.
    $attempts = if ($aggressiveAntiIdle) { 4 } else { 2 }
    $focused = $false
    for ($attempt = 1; $attempt -le $attempts -and -not $focused; $attempt++)
    {
        $focused = Set-WindowFocused $handle
        if (-not $focused -and $attempt -lt $attempts) { Start-Sleep -Milliseconds 150 }
    }

    if (-not $focused)
    {
        # Retry in a minute rather than fighting for focus on every tick
        $session.LastInputAt = (Get-Date).AddMinutes(1 - (Get-AntiIdleInterval))

        # Said once, then not again until it works. Windows refuses focus for as long as
        # someone is using the machine, and with six accounts each retrying every minute
        # that was six identical warnings a minute: five and a half minutes of it on
        # 05-10 buried the teleport lines that actually mattered.
        if (-not $session.FocusRefusedSince)
        {
            $session.FocusRefusedSince = Get-Date
            $session.FocusRefusedCount = 1
            Write-Log ("WARNING: could not focus $accountName after $attempts tries, anti-idle keystroke not " +
                       "sent, retrying every minute until it works")
            Write-ElevationHint
        }
        else
        {
            $session.FocusRefusedCount++
        }
        return
    }

    if ($session.FocusRefusedSince)
    {
        $refusedFor = [int]((Get-Date) - $session.FocusRefusedSince).TotalMinutes
        Write-Log ("focus for $accountName came back after $($session.FocusRefusedCount) refusals over " +
                   "$refusedFor min")
        $session.FocusRefusedSince = $null
        $session.FocusRefusedCount = 0
    }

    $scanCode = [byte]([Win32.Window]::MapVirtualKey($antiIdleVirtualKey, 0))          # games want a real scan code

    if ($aggressiveAntiIdle)
    {
        # One tap is enough for Roblox's own 20 minute timer, but a game can watch for
        # more than that, so this moves the character and the mouse as well. W is held
        # rather than tapped because a tap can be swallowed between frames.
        $moveKey = [byte]0x57                                                          # W
        $moveScan = [byte]([Win32.Window]::MapVirtualKey($moveKey, 0))
        [Win32.Window]::keybd_event($moveKey, $moveScan, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 220
        [Win32.Window]::keybd_event($moveKey, $moveScan, 2, [UIntPtr]::Zero)

        $rectangle = Get-WindowRectangle $handle
        if ($rectangle)
        {
            # Inside the window, so the move cannot land on another client
            $centreX = [int]($rectangle.Left + ($rectangle.Right - $rectangle.Left) / 2)
            $centreY = [int]($rectangle.Top + ($rectangle.Bottom - $rectangle.Top) / 2)
            [Win32.Window]::SetCursorPos($centreX, $centreY) | Out-Null
            Start-Sleep -Milliseconds 40
            [Win32.Window]::SetCursorPos($centreX + 12, $centreY + 8) | Out-Null
        }
    }

    [Win32.Window]::keybd_event($antiIdleVirtualKey, $scanCode, 0, [UIntPtr]::Zero)    # key down
    Start-Sleep -Milliseconds 80
    [Win32.Window]::keybd_event($antiIdleVirtualKey, $scanCode, 2, [UIntPtr]::Zero)    # KEYEVENTF_KEYUP

    if ($aggressiveAntiIdle)
    {
        Start-Sleep -Milliseconds 60
        [Win32.Window]::keybd_event($antiIdleVirtualKey, $scanCode, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 80
        [Win32.Window]::keybd_event($antiIdleVirtualKey, $scanCode, 2, [UIntPtr]::Zero)
    }

    $session.LastInputAt = Get-Date
    $how = if ($aggressiveAntiIdle) { "walked and pressed $antiIdleKey twice" } else { "pressed $antiIdleKey" }
    Write-Log ("anti-idle: $how in $accountName" +
               $(if ($attempt -gt 2) { " (focus took $($attempt - 1) tries)" } else { "" }))

    if ($previous -ne [IntPtr]::Zero -and $previous -ne $handle)
    {
        [Win32.Window]::SetForegroundWindow($previous) | Out-Null
    }
}

function Get-LaunchUrl($accountName)
{
    $launchUrl = "http://localhost:$accountManagerPort/LaunchAccount" +
                 "?Account=$([uri]::EscapeDataString($accountName))" +
                 "&PlaceId=$placeId" +
                 "&Password=$([uri]::EscapeDataString($accountManagerPassword))"
    if ($privateServerLink) { $launchUrl += "&JobId=$([uri]::EscapeDataString($privateServerLink))" }
    return $launchUrl
}

function Invoke-AccountManager($url)
{
    # RAM answers LaunchAccount with 400 even when the launch works, so the status code
    # is only logged; the new Roblox window found in Step-Launching is the real check
    Write-Log "RAM: $($url -replace 'Password=[^&]+', 'Password=***')"
    try
    {
        $response = $httpClient.GetAsync($url).GetAwaiter().GetResult()              # HTTP response
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()       # RAM's reply text
    }
    catch
    {
        # Re-thrown without the url, so the password never lands in an error message
        throw "could not reach Roblox Account Manager on localhost:$accountManagerPort (is the web server enabled?)"
    }
    $reply = "$([int]$response.StatusCode) '$($response.ReasonPhrase)' $body"         # status + text for logs
    Write-Log "RAM replied: $reply"

    # RAM answers LaunchAccount with 400 whether or not it worked, so the status code says
    # nothing. The body does. Across 1613 launches in one log, every empty body was
    # followed by a client starting, with no exceptions, and a non-empty body is RAM
    # refusing: "Invalid Account" when the name is not one it holds. That used to be
    # thrown away, so a refused launch sat for 90 seconds waiting for a window that was
    # never coming, then retried for ever with nothing explaining why.
    $message = "$body".Trim()
    if ($message)
    {
        $hint = ""
        if ($message -match '(?i)account')
        {
            $hint = ". The username has to match the account in RAM exactly, including capitals, " +
                    "and watch for a digit 1 where there should be a letter l"
        }
        elseif ($message -match '(?i)password')
        {
            $hint = ". That is the Webserver Password from RAM's Settings > Developer, not an account password"
        }
        throw "RAM refused it: $message$hint"
    }
    return $reply
}

function Request-Launch($accountName)
{
    # Only asks RAM to launch. Watching for the client happens in Step-Launching, one
    # look per tick, so nothing blocks the status window.
    $session = $sessions[$accountName]
    Set-RobloxFramerateCap                                                            # a client that just closed may have reset it

    $session.LaunchTrackedIds = @($sessions.Values | ForEach-Object { $_.ProcessId } | Where-Object { $_ -ne 0 })
    $session.LaunchedAt = Get-Date                                                    # log files after this are new
    $session.InstallerKilled = $false
    $session.LaunchUrl = Get-LaunchUrl $accountName

    Invoke-AccountManager $session.LaunchUrl | Out-Null
    Write-Log "launched $accountName"
    Set-SessionState $session "Launching"
}

function Test-LaunchHitInstanceGuard($session)
{
    # Roblox can refuse to start another client by crashing inside its own single
    # instance guard: the new starter looks for the running client's guard window, does
    # not find it, and throws "Invalid window handle" before any window appears. RAM
    # reports nothing, because RAM did its part and asked for the launch. The only trace
    # is a 1.3 KB log that ends in RBXCRASH, so that is what gets read.
    try
    {
        foreach ($file in @(Get-PlayerLogFiles |
            Where-Object { $_.CreationTime -ge $session.LaunchedAt -and $_.Length -lt 64KB -and
                           $_.CreationTime -le $session.LaunchedAt.AddSeconds($launchTimeoutSeconds) }))
        {
            if ((Get-Content $file.FullName -Raw -ErrorAction Stop) -match $instanceGuardPattern) { return $true }
        }
    }
    catch { }
    return $false
}

function Reset-RobloxInstanceGuard($trigger)
{
    # Nothing can start while Roblox believes a client holds the guard and that client's
    # window is gone, and retrying changes nothing: the farm sat dead through two hours
    # of retries on 04-10. The only thing seen to clear it is every Roblox client being
    # gone. That is how it recovered by hand the first time: with nothing left running,
    # all six accounts launched in a row without trouble. It means closing main as well,
    # so it is said out loud rather than done quietly.
    $script:lastInstanceGuardResetAt = Get-Date
    Write-Log ("ERROR: Roblox will not start another client, it crashes in its own single instance guard " +
               "instead. Closing every Roblox client, main included, because that is the only thing known " +
               "to clear it, then relaunching all of them")
    Send-DiscordAlert "Roblox would not start another client" (
        "Roblox crashed inside its own single instance guard while launching $trigger, so no new client " +
        "could start and retrying would not have helped.`n`nEvery client is being closed, main included, " +
        "and all of them are being relaunched. That is the only thing known to clear it.") $alertRed $true

    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        if ($session.State -ne "Idle")
        {
            Stop-Session $accountName "closed to clear Roblox's single instance guard"
        }
        $session.FailureCount = 0
        $session.LastFailureReason = $null
    }

    # A process Roblox left behind holds the guard just as well as a tracked client does
    foreach ($leftover in @(Get-Process $processName -ErrorAction SilentlyContinue))
    {
        Stop-Process -Id $leftover.Id -Force -ErrorAction SilentlyContinue
    }

    Update-LaunchQueue $relaunchDelaySeconds
}

function Step-Launching($accountName)
{
    $session = $sessions[$accountName]

    # Checked every tick so the installer dies before it can close other instances
    $installer = Get-Process "RobloxInstaller" -ErrorAction SilentlyContinue
    if ($installer)
    {
        $installer | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not $session.InstallerKilled)
        {
            $session.InstallerKilled = $true
            Write-Log "killed RobloxInstaller for $accountName, retrying launch (a Roblox update in progress may need repairing)"
            Invoke-AccountManager $session.LaunchUrl | Out-Null
        }
    }

    # Claimed ids are read fresh, not from the snapshot taken at launch: if two launches
    # ever overlap, a snapshot would let both sessions claim the same process and then
    # tile it into both their slots
    $claimedIds = @($sessions.Values | ForEach-Object { $_.ProcessId } | Where-Object { $_ -ne 0 })
    $newClient = Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object { $session.LaunchTrackedIds -notcontains $_.Id -and
                       $claimedIds -notcontains $_.Id -and
                       $_.MainWindowHandle -ne 0 } |
        Sort-Object StartTime |
        Select-Object -First 1

    if ($newClient)
    {
        $session.ProcessId = $newClient.Id
        $session.ProcessStartTime = $newClient.StartTime
        Set-SessionState $session "FindingLog"
        return
    }

    # Roblox can fail a launch without any window ever appearing, and then waiting out
    # the timeout and retrying on a longer and longer backoff changes nothing at all
    if (((Get-Date) - $session.StateSince).TotalSeconds -gt $instanceGuardCheckSeconds -and
        (Test-LaunchHitInstanceGuard $session))
    {
        if (-not $script:lastInstanceGuardResetAt -or
            ((Get-Date) - $script:lastInstanceGuardResetAt).TotalMinutes -ge $instanceGuardCooldownMinutes)
        {
            Reset-RobloxInstanceGuard $accountName
            return
        }
        throw ("Roblox crashed in its own single instance guard, and closing everything to clear it was " +
               "already tried less than $instanceGuardCooldownMinutes minutes ago")
    }

    if (((Get-Date) - $session.StateSince).TotalSeconds -gt $launchTimeoutSeconds)
    {
        throw "no new Roblox window appeared within $launchTimeoutSeconds s"
    }
}

function Step-FindingLog($accountName)
{
    # Launches run one at a time, so the oldest unclaimed log since launch is this client's
    $session = $sessions[$accountName]
    $takenPaths = @($sessions.Values | ForEach-Object { $_.LogPath })
    $logFile = Get-PlayerLogFiles |
        Where-Object { $_.CreationTime -ge $session.LaunchedAt -and $takenPaths -notcontains $_.FullName -and
                       -not (Test-IsStarterStub $_.FullName) } |
        Sort-Object CreationTime |
        Select-Object -First 1

    if ($logFile)
    {
        $session.LogPath = $logFile.FullName
        $session.LogOffset = 0
        $session.StartedAt = Get-Date
        $session.JoinedAt = $null                                                     # not in the game until the log says so
        $session.ServerAddress = $null                                                # read from the log's first join line
        $session.PendingDrop = $null
        $session.LastInputAt = Get-Date                                               # joining counts as input
        $session.WindowSeenAt = $null
        $session.EverStarted = $true
        Write-Log "$accountName running as PID $($session.ProcessId), log $(Split-Path -Leaf $session.LogPath)"

        # The next one waits a full delay before starting, then the rest queue up behind it
        Update-LaunchQueue $relaunchDelaySeconds

        Set-SessionState $session "Tiling"
        return
    }

    if (((Get-Date) - $session.StateSince).TotalSeconds -gt $logTimeoutSeconds)
    {
        # A warm start reuses an existing session, so there may be no new log to find and
        # killing the client over it would be throwing away something that works. The
        # session carries on without one: disconnects then come from the process going
        # away and being in the game comes from memory, which is less detail but true.
        Write-Log "WARNING: no new log appeared for $accountName within $logTimeoutSeconds s, carrying on without one (no disconnect codes for this session)"
        $session.LogPath = $null
        $session.LogOffset = 0
        $session.StartedAt = Get-Date
        $session.JoinedAt = $null
        $session.ServerAddress = $null
        $session.PendingDrop = $null
        $session.LastInputAt = Get-Date
        $session.WindowSeenAt = $null
        $session.EverStarted = $true
        Update-LaunchQueue $relaunchDelaySeconds
        Set-SessionState $session "Tiling"
        return
    }
}

function Step-Tiling($accountName)
{
    $session = $sessions[$accountName]
    $process = Get-SessionProcess $session
    if (-not $process)
    {
        Set-SessionState $session "Running"                                           # already gone; the running checks will catch it
        return
    }
    $process.Refresh()

    if ($process.MainWindowHandle -eq [IntPtr]::Zero)
    {
        if (((Get-Date) - $session.StateSince).TotalSeconds -gt $windowTimeoutSeconds)
        {
            # Tiling is cosmetic: a client without a window keeps running, just untiled
            Write-Log "WARNING: $accountName never showed a window, leaving it untiled"
            Set-SessionState $session "Running"
        }
        return
    }

    # Roblox restores its own saved size right after the window appears; move after that
    if (-not $session.WindowSeenAt)
    {
        $session.WindowSeenAt = Get-Date
        return
    }
    if (((Get-Date) - $session.WindowSeenAt).TotalSeconds -lt $windowSettleSeconds) { return }

    Set-ClientWindow $accountName $session.ProcessId | Out-Null
    Set-SessionState $session "Running"
}

function Get-PlayerLogFiles
{
    # Roblox's crash handler writes its own file that matches this filter as well. It
    # never mentions joining or disconnecting, so attaching to one would mean watching
    # nothing happen for the rest of the session.
    Get-ChildItem $logFolder -Filter "*_Player_*.log" -ErrorAction Stop |
        Where-Object { $_.Name -notlike "*CrashHandler*" }
}

function Test-IsStarterStub($path)
{
    # Roblox 0.741 warm-starts: a launch can hand off to an existing client, write a
    # handful of lines and end with the starter being destroyed. That file never mentions
    # joining or disconnecting, so attaching to it means watching nothing.
    try
    {
        if ((Get-Item $path).Length -gt 64KB) { return $false }
        foreach ($line in (Get-Content $path -Tail 3 -ErrorAction Stop))
        {
            if ($line -like "*RobloxStarter destroyed*") { return $true }
        }
        return $false
    }
    catch
    {
        return $false
    }
}

function Find-StartupLogFile($process)
{
    # A client that was already running: its log was created within seconds of the process
    $logFile = Get-PlayerLogFiles |
        Sort-Object { [math]::Abs(($_.CreationTime - $process.StartTime).TotalSeconds) } |
        Select-Object -First 1
    if (-not $logFile -or [math]::Abs(($logFile.CreationTime - $process.StartTime).TotalSeconds) -gt 60)
    {
        throw "No *_Player_*.log in $logFolder matches PID $($process.Id) started at $($process.StartTime)"
    }
    return $logFile.FullName
}

function Read-NewLogText($session)
{
    # Roblox keeps the log open for writing, so share ReadWrite; only read what's new
    $stream = [System.IO.File]::Open($session.LogPath, "Open", "Read", "ReadWrite")  # log file handle
    try
    {
        # A rotated or truncated log would otherwise leave us reading past the end forever
        if ($session.LogOffset -gt $stream.Length)
        {
            Write-Log "log $(Split-Path -Leaf $session.LogPath) shrank, reading it from the start"
            $session.LogOffset = 0
        }
        $stream.Seek($session.LogOffset, "Begin") | Out-Null
        $reader = New-Object System.IO.StreamReader($stream)
        try
        {
            $text = $reader.ReadToEnd()                                               # new log lines
            $session.LogOffset = $stream.Position
            return $text
        }
        finally
        {
            $reader.Dispose()
        }
    }
    finally
    {
        $stream.Dispose()
    }
}

function Update-SessionFromLog($session)
{
    # One read per tick, because the offset only moves forward and every check shares it.
    # Returns $null while nothing worth acting on happened, or what this chunk of log
    # said: the last disconnect code in it, and the server the client joined afterwards
    # if it came back. Both are needed, because a disconnect line on its own does not
    # mean the client is gone.
    $text = Read-NewLogText $session

    $joins = [regex]::Matches($text, $joinAddressPattern)                            # every server it joined, with the address

    if (-not $session.JoinedAt -and $text.Contains($joinMarker))
    {
        $session.JoinedAt = Get-Date
        $session.NeverJoinedCount = 0
        $session.StepsPending = $true                                                 # freshly in the game, so the setup may be due
    }
    if (-not $session.ServerAddress -and $joins.Count)
    {
        # Where this account belongs. Read from the log rather than configured, because
        # the private server's address is not known until a client has connected to it.
        $session.ServerAddress = $joins[0].Groups[1].Value
    }

    # The last disconnect, not the first: a teleport logs the same code from three
    # threads at once, and what matters is whether anything came after it
    $disconnects = [regex]::Matches($text, $disconnectPattern)
    $reason = $null
    $reasonIndex = -1
    for ($index = $disconnects.Count - 1; $index -ge 0; $index--)
    {
        if ($ignoredDisconnectReasons -contains $disconnects[$index].Groups[1].Value) { continue }
        $reason = $disconnects[$index].Groups[1].Value
        $reasonIndex = $disconnects[$index].Index
        break
    }

    # A join after that line is the client putting itself back, which is what tells a
    # teleport apart from a real drop
    $rejoinAddress = $null
    foreach ($join in $joins)
    {
        if ($join.Index -gt $reasonIndex) { $rejoinAddress = $join.Groups[1].Value }
    }

    # Except that the order of those lines is a race. Roblox writes the join and the
    # disconnects from different threads, and on 05-10 one account logged its join 20 ms
    # before the disconnect rather than after:
    #
    #   14:20:52.823 thread 55e4  Connection accepted from 128.116.21.33|58590
    #   14:20:52.843 thread 2494  Sending disconnect with reason: 285
    #
    # Looking only after the disconnect missed it, so a healthy client was closed and
    # relaunched while its five siblings in the same teleport were left alone. The
    # teleport marker settles it: the game logs that line when it moves a player and no
    # real drop ever does, so with it present any join in the chunk is the client coming
    # back, whichever order the two landed in.
    $teleported = $text.Contains($teleportMarker)
    if ($reason -and $teleported -and -not $rejoinAddress -and $joins.Count)
    {
        $rejoinAddress = $joins[$joins.Count - 1].Groups[1].Value
    }

    if (-not $reason -and -not $rejoinAddress) { return $null }
    return @{ Reason = $reason; RejoinAddress = $rejoinAddress; Teleported = $teleported }
}

function Find-LogByElimination($accountName)
{
    # A warm-started client writes to the log of the process it took over, which was
    # created before this launch, so the usual "oldest log since launch" search never
    # finds it and the session stays blind for as long as it runs: no disconnect codes,
    # no drop count, no Discord alert. The main account sat like that for nine hours on
    # 04-10 while it was in the game the whole time.
    #
    # A log cannot be asked which account it belongs to. But if every other session has
    # its own log, and exactly one log is both unclaimed and still being written to,
    # that one is this session's by elimination. More than one would be a guess, so it
    # waits and tries again instead.
    $session = $sessions[$accountName]
    $takenPaths = @($sessions.Values | ForEach-Object { $_.LogPath } | Where-Object { $_ })
    $candidates = @(Get-PlayerLogFiles |
        Where-Object { $takenPaths -notcontains $_.FullName -and
                       $_.LastWriteTime -ge (Get-Date).AddSeconds(-$logLivenessSeconds) -and
                       -not (Test-IsStarterStub $_.FullName) })

    if ($candidates.Count -ne 1) { return $false }

    $session.LogPath = $candidates[0].FullName
    $session.LogOffset = $candidates[0].Length                                        # only what happens from here on
    $session.ServerAddress = $null
    $session.PendingDrop = $null
    Write-Log ("$accountName had no log of its own, and $(Split-Path -Leaf $session.LogPath) is the only " +
               "live one left unclaimed, so it is read for $accountName from now on")
    return $true
}

function Set-SessionState($session, $state)
{
    $session.State = $state
    $session.StateSince = Get-Date
}

function Update-LaunchQueue($firstDelaySeconds)
{
    # Launches happen one at a time, so each waiting account is given its own turn:
    # pushing them all to the same moment made every countdown read the same and be
    # wrong for all but the next in line. Walks $allAccounts rather than
    # $sessions.Values, which has no order.
    $queuePosition = 0
    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        if ($session.State -eq "Idle" -and -not $session.Paused)
        {
            $session.RelaunchAfter = (Get-Date).AddSeconds($firstDelaySeconds + ($relaunchDelaySeconds * $queuePosition))
            $queuePosition++
        }
    }
}

function Stop-Session($accountName, $reason)
{
    $session = $sessions[$accountName]
    $process = Get-SessionProcess $session
    if ($process)
    {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Log "$accountName (PID $($session.ProcessId)) $reason, relaunching in $relaunchDelaySeconds s"

    # Kept so one account that drops far more than the others is visible at a glance
    if ($session.StartedAt)
    {
        $session.TotalUpSeconds += [int]((Get-Date) - $session.StartedAt).TotalSeconds
    }
    $session.ProcessId = 0
    $session.ProcessStartTime = $null
    $session.LogPath = $null
    $session.JoinedAt = $null
    $session.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
    Set-SessionState $session "Idle"
}

function Register-LaunchFailure($accountName, $message)
{
    # Back off a little further each time instead of hammering RAM, but never give up:
    # an account that cannot start yet keeps being retried
    $session = $sessions[$accountName]
    $session.FailureCount++
    $session.LastFailureReason = $message
    $backoffSeconds = [math]::Min($relaunchDelaySeconds * $session.FailureCount, 600)
    $session.RelaunchAfter = (Get-Date).AddSeconds($backoffSeconds)
    Set-SessionState $session "Idle"

    Write-Log "WARNING: launching $accountName failed ($($session.FailureCount)x): $message"
    if ($session.FailureCount -eq $maximumLaunchFailures)
    {
        Write-Log "ERROR: $accountName has failed $maximumLaunchFailures launches in a row, is RAM running with the web server on?"
        Send-DiscordAlert "$accountName will not start" ("$maximumLaunchFailures launches in a row have failed. Last reason:`n``$message``" +
            "`n`nIt keeps retrying, but Roblox Account Manager is probably not running with its web server on.") $alertRed
    }
    Write-Log "retrying $accountName in $backoffSeconds s"
}

function Get-SessionStatusText($accountName)
{
    $session = $sessions[$accountName]
    if ($session.Paused) { return "paused" }

    if ($session.State -eq "Idle")
    {
        # Said plainly, because otherwise a countdown sits at zero and looks stuck
        if ($script:stepRun.Active -and $accountName -ne $mainAccount) { return "waiting for main's setup" }

        $waitSeconds = [int](($session.RelaunchAfter - (Get-Date)).TotalSeconds)
        # "relaunching" is only true once it has actually been up
        $verb = if ($session.EverStarted) { "relaunching" } else { "launching" }
        if ($waitSeconds -gt 0) { return "$verb in $waitSeconds s" }
        return "queued"                                                               # its turn has come, waiting for the one in flight
    }
    if ($session.State -eq "Launching")  { return "launching" }
    if ($session.State -eq "FindingLog") { return "finding log" }
    if ($session.State -eq "Tiling")     { return "positioning" }
    if ($session.State -eq "Running")
    {
        if ($session.JoinedAt) { return "playing" }
        return "joining"
    }
    return $session.State
}

function Get-SessionColor($accountName)
{
    $session = $sessions[$accountName]
    if ($session.Paused) { return $themeGrey }
    if ($session.State -eq "Running" -and $session.JoinedAt) { return $themeGreen }
    if ($session.State -eq "Idle") { return $themeGrey }
    return $themeAmber                                                                # mid-launch
}

# ---- State ------------------------------------------------------------------------

# Main first, so it is relaunched before any alt
$allAccounts = @($mainAccount) + $altAccounts
$sessions = @{}
foreach ($accountName in $allAccounts)
{
    $sessions[$accountName] = @{ ProcessId = 0; ProcessStartTime = $null; StartedAt = $null
                                 RelaunchAfter = (Get-Date); LogPath = $null; LogOffset = 0; FailureCount = 0
                                 LastInputAt = $null; JoinedAt = $null
                                 State = "Idle"; StateSince = (Get-Date)
                                 LaunchTrackedIds = @(); LaunchedAt = $null; InstallerKilled = $false
                                 LaunchUrl = $null; WindowSeenAt = $null; Paused = $false
                                 EverStarted = $false; AppliedRect = $null
                                 DropCount = 0; LastDropAt = $null; LastDropReason = $null
                                 TotalUpSeconds = 0; StepsPending = $false; NeverJoinedCount = 0
                                 LastFailureReason = $null; ServerAddress = $null
                                 PendingDrop = $null; RelogCount = 0
                                 PendingAddress = $null; FocusRefusedSince = $null
                                 FocusRefusedCount = 0 }
}

$globalPaused = $false
$reallyExit = $false
$lastInstanceGuardResetAt = $null
$versionCheckTask = $null
$lastVersionCheckAt = $null
$newerVersion = $null
$strayClosedCount = 0
$lastDisconnectAt = $null
$lastFreeMegabytes = 0
$lowMemoryAlerted = $false
$lastMemoryKillAt = $null
$lastSummaryAt = Get-Date
$watchdogStartedAt = Get-Date
$tickCount = 0
$logForm = $null
$logBox = $null

Write-Log "watchdog started, settings in $settingsPath, log in $logFilePath"
if ($isElevated)
{
    Write-Log "running as administrator"
}
else
{
    Write-Log "WARNING: not running as administrator. If Roblox Account Manager is elevated then its clients are too,"
    Write-Log "WARNING: and closing strays plus anti-idle focus will be denied. Run the exe as administrator, or stop"
    Write-Log "WARNING: running RAM as administrator."
}
Set-RobloxFramerateCap
if ($minimumFreeMegabytes -gt 0)
{
    Write-Log "will kill the largest alt below $minimumFreeMegabytes MB available (now $([int](Get-FreeMegabytes)) MB)"
}
else
{
    Write-Log "will not kill alts over memory (now $([int](Get-FreeMegabytes)) MB available)"
}

# A running client is adopted as main; everything else is untracked and closed
$runningMain = Get-RobloxClients | Sort-Object StartTime | Select-Object -First 1
if ($runningMain)
{
    $sessions[$mainAccount].ProcessId = $runningMain.Id
    $sessions[$mainAccount].ProcessStartTime = $runningMain.StartTime
    $sessions[$mainAccount].StartedAt = $runningMain.StartTime
    $sessions[$mainAccount].LastInputAt = Get-Date                                    # unknown when it last had input, so start the clock now
    $sessions[$mainAccount].JoinedAt = Get-Date                                       # it was already playing, so don't hold it to the join timeout
    $sessions[$mainAccount].EverStarted = $true                                       # it is already up, so a stop is a relaunch
    Set-SessionState $sessions[$mainAccount] "Running"
    try
    {
        $sessions[$mainAccount].LogPath = Find-StartupLogFile $runningMain
        Write-Log "adopted PID $($runningMain.Id) as main $mainAccount, log $(Split-Path -Leaf $sessions[$mainAccount].LogPath)"
    }
    catch
    {
        # Without a log we cannot see main disconnect, but it is still tracked and tiled
        Write-Log "WARNING: adopted PID $($runningMain.Id) as main $mainAccount but found no matching log, disconnect detection stays off for main until it relaunches"
    }
    Set-ClientWindow $mainAccount $runningMain.Id | Out-Null                          # main is always slot 0
}
Write-Log "alts: $($altAccounts -join ', ')"
if ($discordWebhookUrl)
{
    Write-Log "Discord alerts are on$(if ($discordSummaryMinutes -gt 0) { ", with a status message every $discordSummaryMinutes min" })"
    Send-DiscordAlert "Watchdog started" ("Watching $($allAccounts.Count) accounts: " + ($allAccounts -join ", ")) $alertGreen
}

if ($closeOtherClients)
{
    Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $sessions[$mainAccount].ProcessId -and $_.MainWindowHandle -ne 0 } |
        ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Log "closed leftover PID $($_.Id)"
        }
}

# ---- Status window ----------------------------------------------------------------

$statusForm = New-Object System.Windows.Forms.Form
$statusForm.Text = "Roblox Watchdog"
$statusForm.Size = New-Object System.Drawing.Size(580, 600)
$statusForm.StartPosition = "CenterScreen"
$statusForm.FormBorderStyle = "FixedSingle"
$statusForm.MaximizeBox = $false
Set-ThemedForm $statusForm

# Always present rather than shown only on trouble, so the layout never shifts and the
# answer to "is this elevated" is on screen instead of buried in the log
$elevationStrip = New-Object System.Windows.Forms.Label
$elevationStrip.Location = New-Object System.Drawing.Point(0, 0)
$elevationStrip.Size = New-Object System.Drawing.Size(564, 44)
$elevationStrip.TextAlign = "MiddleLeft"
$elevationStrip.Padding = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)
if ($isElevated)
{
    $elevationStrip.Text = "Running as administrator"
    $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(24, 40, 32)
    $elevationStrip.ForeColor = $themeGreen
}
else
{
    $elevationStrip.Text = "Not running as administrator. If Account Manager is elevated, tiling, anti-idle and closing strays will be denied."
    $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(45, 36, 20)
    $elevationStrip.ForeColor = $themeAmber
}
# Kept, because the update notice is added as a second line on this same strip rather
# than as another one that would push the whole window down
$elevationStripText = $elevationStrip.Text
$elevationStripBack = $elevationStrip.BackColor
$elevationStripFore = $elevationStrip.ForeColor
$elevationStrip.Add_Click({
    if ($script:newerVersion) { Start-Process $releasePageUrl }
})
$statusForm.Controls.Add($elevationStrip)

$headline = New-Object System.Windows.Forms.Label
$headline.Location = New-Object System.Drawing.Point(14, 58)
$headline.Size = New-Object System.Drawing.Size(536, 40)
$headline.Font = New-Object System.Drawing.Font("Segoe UI Light", 22)
$headline.TextAlign = "MiddleCenter"
$headline.ForeColor = $themeText
$headline.Text = "starting"
$statusForm.Controls.Add($headline)

function New-Tile($caption, $x, $y)
{
    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Location = New-Object System.Drawing.Point($x, $y)
    $captionLabel.Size = New-Object System.Drawing.Size(250, 16)
    $captionLabel.ForeColor = $themeMuted
    $captionLabel.Text = $caption
    $statusForm.Controls.Add($captionLabel)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Location = New-Object System.Drawing.Point($x, ($y + 17))
    $valueLabel.Size = New-Object System.Drawing.Size(250, 25)
    $valueLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $valueLabel.ForeColor = $themeAccent
    $valueLabel.Text = "-"
    $statusForm.Controls.Add($valueLabel)
    return $valueLabel
}

$tileFreeRam  = New-Tile "free memory"     28 108
$tileStrays   = New-Tile "strays closed"   300 108
$tileUptime   = New-Tile "watchdog uptime" 28 156
$tileLastDrop = New-Tile "last disconnect" 300 156

$divider = New-Object System.Windows.Forms.Panel
$divider.Location = New-Object System.Drawing.Point(14, 198)
$divider.Size = New-Object System.Drawing.Size(536, 1)
$divider.BackColor = $themeBorder
$statusForm.Controls.Add($divider)

# The real ListView header cannot be themed and would sit there light grey on a dark
# list, so it is switched off and these labels stand in for it, lined up with the
# column widths below
$headerOffsets = @{ Account = 42; Status = 192; Memory = 332; Up = 406; Drops = 482 }
foreach ($headerName in @("Account", "Status", "Memory", "Up", "Drops"))
{
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = $headerName
    $headerLabel.Location = New-Object System.Drawing.Point($headerOffsets[$headerName], 208)
    $headerLabel.Size = New-Object System.Drawing.Size(120, 16)
    $headerLabel.ForeColor = $themeMuted
    $statusForm.Controls.Add($headerLabel)
}

$accountList = New-Object System.Windows.Forms.ListView
$accountList.Location = New-Object System.Drawing.Point(14, 228)
$accountList.Size = New-Object System.Drawing.Size(536, 166)
$accountList.View = "Details"
$accountList.FullRowSelect = $true
$accountList.GridLines = $false
$accountList.HeaderStyle = "None"
$accountList.MultiSelect = $true                                                      # relaunching or pausing a few at once is the normal case
$accountList.BorderStyle = "None"
$accountList.BackColor = $themeSurface
$accountList.ForeColor = $themeText
$accountList.Columns.Add("", 28) | Out-Null
$accountList.Columns.Add("Account", 150) | Out-Null
$accountList.Columns.Add("Status", 140) | Out-Null
$accountList.Columns.Add("Memory", 74) | Out-Null
$accountList.Columns.Add("Up", 76) | Out-Null
$accountList.Columns.Add("Drops", 68) | Out-Null                                      # fills the rest, so no empty sliver column
foreach ($accountName in $allAccounts)
{
    $item = New-Object System.Windows.Forms.ListViewItem("")
    $item.UseItemStyleForSubItems = $false                                            # so only the dot is coloured
    $item.SubItems.Add($accountName) | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.Tag = $accountName
    $accountList.Items.Add($item) | Out-Null
}
$statusForm.Controls.Add($accountList)

# One line of detail for whatever is selected, so the numbers behind a row are readable
# without cramming more columns in
$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Location = New-Object System.Drawing.Point(14, 400)
$detailLabel.Size = New-Object System.Drawing.Size(536, 18)
$detailLabel.ForeColor = $themeMuted
$detailLabel.Text = ""
$statusForm.Controls.Add($detailLabel)

$relaunchButton = New-Object System.Windows.Forms.Button
$relaunchButton.Text = "Relaunch selected"
$relaunchButton.Location = New-Object System.Drawing.Point(14, 424)
$relaunchButton.Size = New-Object System.Drawing.Size(140, 27)
$relaunchButton.Enabled = $false
Set-ThemedButton $relaunchButton $false
$statusForm.Controls.Add($relaunchButton)

$pauseAccountButton = New-Object System.Windows.Forms.Button
$pauseAccountButton.Text = "Pause selected"
$pauseAccountButton.Location = New-Object System.Drawing.Point(162, 424)
$pauseAccountButton.Size = New-Object System.Drawing.Size(140, 27)
$pauseAccountButton.Enabled = $false
Set-ThemedButton $pauseAccountButton $false
$statusForm.Controls.Add($pauseAccountButton)

$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Text = "Settings"
$settingsButton.Location = New-Object System.Drawing.Point(14, 468)
$settingsButton.Size = New-Object System.Drawing.Size(100, 30)
Set-ThemedButton $settingsButton $false
$statusForm.Controls.Add($settingsButton)

$pauseButton = New-Object System.Windows.Forms.Button
$pauseButton.Text = "Pause"
$pauseButton.Location = New-Object System.Drawing.Point(122, 468)
$pauseButton.Size = New-Object System.Drawing.Size(100, 30)
Set-ThemedButton $pauseButton $false
$statusForm.Controls.Add($pauseButton)

$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "Log"
$logButton.Location = New-Object System.Drawing.Point(230, 468)
$logButton.Size = New-Object System.Drawing.Size(100, 30)
Set-ThemedButton $logButton $false
$statusForm.Controls.Add($logButton)

# Runs the step list on main. Enabled only when there is a list and main is in the game.
$runStepsButton = New-Object System.Windows.Forms.Button
$runStepsButton.Text = "Run"
$runStepsButton.Location = New-Object System.Drawing.Point(338, 468)
$runStepsButton.Size = New-Object System.Drawing.Size(100, 30)
$runStepsButton.Enabled = $false
Set-ThemedButton $runStepsButton $false
$statusForm.Controls.Add($runStepsButton)

$runStepsButton.Add_Click({
    if ($script:stepRun.Active) { Stop-StepRun "you pressed Stop"; return }
    Start-StepRun "you pressed Run"
})

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Location = New-Object System.Drawing.Point(450, 468)
$exitButton.Size = New-Object System.Drawing.Size(100, 30)
Set-ThemedButton $exitButton $false
$statusForm.Controls.Add($exitButton)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Location = New-Object System.Drawing.Point(14, 508)
$hintLabel.Size = New-Object System.Drawing.Size(536, 18)
$hintLabel.ForeColor = $themeMuted
$hintLabel.Text = "Closing this window keeps the watchdog running in the tray. Use Exit to stop it."
$statusForm.Controls.Add($hintLabel)

# ---- Tray -------------------------------------------------------------------------

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.SystemIcons]::Application
$trayIcon.Text = "Roblox Watchdog"
$trayIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayShowItem = $trayMenu.Items.Add("Show")
$trayExitItem = $trayMenu.Items.Add("Exit")
$trayIcon.ContextMenuStrip = $trayMenu

function Show-StatusWindow
{
    $statusForm.Show()
    $statusForm.WindowState = "Normal"
    $statusForm.Activate()
}

$trayShowItem.Add_Click({ Show-StatusWindow })
$trayIcon.Add_DoubleClick({ Show-StatusWindow })
$trayExitItem.Add_Click({
    $script:reallyExit = $true
    $statusForm.Close()
})

# ---- Window behaviour -------------------------------------------------------------

$statusForm.Add_FormClosing({
    param($eventSender, $eventArgs)
    # The X minimises to the tray: stopping the watchdog should be deliberate
    if (-not $script:reallyExit)
    {
        $eventArgs.Cancel = $true
        $statusForm.Hide()
        $trayIcon.ShowBalloonTip(2500, "Roblox Watchdog", "Still running. Double-click the tray icon to bring it back.", "Info")
    }
})

$statusForm.Add_FormClosed({
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
})

$exitButton.Add_Click({
    $script:reallyExit = $true
    $statusForm.Close()
})

$pauseButton.Add_Click({
    $script:globalPaused = -not $script:globalPaused
    if ($script:globalPaused)
    {
        $pauseButton.Text = "Resume"
        Write-Log "paused from the window: no relaunching, anti-idle or stray cleanup"
    }
    else
    {
        $pauseButton.Text = "Pause"
        Write-Log "resumed from the window"
    }
})

$relaunchButton.Add_Click({
    $selected = @($accountList.SelectedItems | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    # Asked for by hand, so these go to the front: the first straight away and the rest
    # behind it. Everyone else's place in the queue is left alone.
    $queuePosition = 0
    foreach ($accountName in $selected)
    {
        $session = $sessions[$accountName]
        if ($session.State -ne "Idle")
        {
            Stop-Session $accountName "relaunch asked for from the window"
        }
        $session.FailureCount = 0
        $session.LastFailureReason = $null
        $session.Paused = $false
        $session.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds * $queuePosition)
        $queuePosition++
    }
})

$pauseAccountButton.Add_Click({
    $selected = @($accountList.SelectedItems | ForEach-Object { $_.Tag })
    if ($selected.Count -eq 0) { return }

    # A mixed selection would make the button ambiguous, so one running account means
    # pause the lot, and only an all-paused selection resumes
    $shouldPause = $false
    foreach ($accountName in $selected)
    {
        if (-not $sessions[$accountName].Paused) { $shouldPause = $true; break }
    }

    $queuePosition = 0
    foreach ($accountName in $selected)
    {
        $session = $sessions[$accountName]
        if ($shouldPause)
        {
            if (-not $session.Paused)
            {
                $session.Paused = $true
                Write-Log "$accountName paused from the window, it will not be relaunched or poked"
            }
        }
        else
        {
            $session.Paused = $false
            $session.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds * $queuePosition)
            $queuePosition++
            Write-Log "$accountName resumed from the window"
        }
    }
})

$logButton.Add_Click({
    if ($script:logForm -and -not $script:logForm.IsDisposed)
    {
        $script:logForm.Activate()
        return
    }
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Roblox Watchdog - log"
    $form.Size = New-Object System.Drawing.Size(940, 520)
    $form.StartPosition = "CenterParent"
    Set-ThemedForm $form

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = "Both"
    $box.WordWrap = $false
    $box.Dock = "Fill"
    $box.BackColor = $themeBackground
    $box.ForeColor = $themeText
    $box.BorderStyle = "None"
    $box.Font = New-Object System.Drawing.Font("Consolas", 9)
    $form.Controls.Add($box)

    $script:logForm = $form
    $script:logBox = $box
    $form.Add_FormClosed({
        $script:logForm = $null
        $script:logBox = $null
    })
    $form.Show()
})

$settingsButton.Add_Click({
    $updated = Show-SettingsWindow (Get-SavedSettings)
    if (-not $updated) { return }
    try
    {
        Test-Settings $updated
    }
    catch
    {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Check your settings",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Save-Settings $updated

    # The numbers take effect straight away; the account list would need every session
    # rebuilt, so that one waits for a restart
    $script:minimumFreeMegabytes = [int]$updated.MinimumFreeMegabytes
    $script:relaunchDelaySeconds = [int]$updated.RelaunchDelaySeconds
    $script:maximumSessionMinutes = [int]$updated.MaximumSessionMinutes
    $script:framerateCap = [int]$updated.FramerateCap
    $script:antiIdleMinutes = [int]$updated.AntiIdleMinutes
    $script:antiIdleKey = $updated.AntiIdleKey
    $script:aggressiveAntiIdle = ($updated.AggressiveAntiIdle -eq "True")
    $script:antiIdleVirtualKey = if ($updated.AntiIdleKey -eq "Space") { [byte]0x20 } else { [byte][char]([string]$updated.AntiIdleKey).ToUpper() }
    $script:reapStrayMinutes = [int]$updated.ReapStrayMinutes
    $script:closeOtherClients = ($updated.CloseOtherClients -ne "False")
    $script:useAllMonitors = ($updated.UseAllMonitors -ne "False")
    $script:discordWebhookUrl = $updated.DiscordWebhookUrl
    $script:discordPingId = $updated.DiscordPingId
    $script:discordSummaryMinutes = [int]$updated.DiscordSummaryMinutes
    $script:rememberWindowPositions = ($updated.RememberWindowPositions -ne "False")
    $script:stepListText = $updated.StepList
    $script:runStepsOnRejoin = ($updated.RunStepsOnRejoin -eq "True")
    if (-not $script:rememberWindowPositions -and (Test-Path $positionsPath))
    {
        # Turning it off forgets them, otherwise they would come back on re-ticking it
        Remove-Item $positionsPath -Force -ErrorAction SilentlyContinue
        Write-Log "forgot the saved window positions"
    }
    Write-Log "settings saved and applied"

    if ($updated.MainAccount -ne $mainAccount -or $updated.AltAccounts -ne $settings.AltAccounts)
    {
        [System.Windows.Forms.MessageBox]::Show(
            "Saved. The account list takes effect the next time you start the watchdog.",
            "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})

# ---- Refresh ----------------------------------------------------------------------

function Update-StatusUi
{
    $playing = 0
    foreach ($item in $accountList.Items)
    {
        $accountName = $item.Tag
        $session = $sessions[$accountName]

        $stateColor = Get-SessionColor $accountName
        $item.Text = "  " + [char]0x25CF
        $item.ForeColor = $stateColor

        $label = $accountName
        if ($accountName -eq $mainAccount) { $label += "   (main)" }
        $item.SubItems[1].Text = $label
        $item.SubItems[2].Text = Get-SessionStatusText $accountName

        # Subitems keep their own colours (UseItemStyleForSubItems is off), and on a dark
        # background they default to black, so every one has to be set
        $item.SubItems[5].Text = if ($session.DropCount -gt 0) { "$($session.DropCount)" } else { "-" }

        $item.SubItems[1].ForeColor = $themeText
        $item.SubItems[2].ForeColor = $stateColor
        $item.SubItems[3].ForeColor = $themeMuted
        $item.SubItems[4].ForeColor = $themeMuted
        # Amber once an account is dropping noticeably more than a couple of times
        $item.SubItems[5].ForeColor = if ($session.DropCount -ge 5) { $themeAmber } else { $themeMuted }

        $process = Get-SessionProcess $session
        if ($process)
        {
            $item.SubItems[3].Text = "{0:N1} GB" -f ($process.WorkingSet64 / 1GB)
        }
        else
        {
            $item.SubItems[3].Text = "-"
        }

        if ($session.StartedAt -and $session.State -eq "Running")
        {
            $upFor = (Get-Date) - $session.StartedAt
            $item.SubItems[4].Text = "{0}h{1:00}m" -f [int]$upFor.TotalHours, $upFor.Minutes
        }
        else
        {
            $item.SubItems[4].Text = "-"
        }

        if ($session.State -eq "Running" -and $session.JoinedAt) { $playing++ }
    }

    $headline.Text = "$playing / $($allAccounts.Count) accounts playing"
    if ($script:globalPaused) { $headline.Text = $headline.Text + "   (paused)" }

    $mainIsIn = ($sessions[$mainAccount].State -eq "Running" -and $sessions[$mainAccount].JoinedAt)
    if ($script:stepRun.Active)
    {
        $runStepsButton.Enabled = $true
        $runStepsButton.Text = "Stop $($script:stepRun.Index)/$($script:stepRun.Steps.Count)"
    }
    else
    {
        $runStepsButton.Enabled = ($stepListText -and $mainIsIn -and -not $script:globalPaused)
        $runStepsButton.Text = "Run"
    }

    $tileFreeRam.Text = "$script:lastFreeMegabytes MB"
    $tileStrays.Text = "$script:strayClosedCount"

    $watchdogUp = (Get-Date) - $watchdogStartedAt
    $tileUptime.Text = "{0}h{1:00}m" -f [int]$watchdogUp.TotalHours, $watchdogUp.Minutes

    if ($script:lastDisconnectAt)
    {
        $tileLastDrop.Text = "{0} min ago" -f [int](((Get-Date) - $script:lastDisconnectAt).TotalMinutes)
    }
    else
    {
        $tileLastDrop.Text = "none yet"
    }

    if ($accountList.SelectedItems.Count -eq 1)
    {
        $detailAccount = $accountList.SelectedItems[0].Tag
        $detailSession = $sessions[$detailAccount]
        $parts = New-Object System.Collections.Generic.List[string]

        $liveSeconds = $detailSession.TotalUpSeconds
        if ($detailSession.StartedAt -and $detailSession.State -eq "Running")
        {
            $liveSeconds += [int]((Get-Date) - $detailSession.StartedAt).TotalSeconds
        }
        $parts.Add(("up {0}h{1:00}m in total" -f [int]($liveSeconds / 3600), [int](($liveSeconds % 3600) / 60)))

        if ($detailSession.DropCount -gt 0)
        {
            $parts.Add("$($detailSession.DropCount) drop$(if ($detailSession.DropCount -ne 1) { 's' })")
            if ($detailSession.LastDropAt)
            {
                $parts.Add(("last {0} min ago, reason {1}" -f [int](((Get-Date) - $detailSession.LastDropAt).TotalMinutes),
                                                              $detailSession.LastDropReason))
            }
        }
        else
        {
            $parts.Add("no drops yet")
        }
        if ($detailSession.RelogCount -gt 0)
        {
            $parts.Add("relogged $($detailSession.RelogCount)x without being relaunched")
        }
        if ($detailSession.FailureCount -gt 0)
        {
            $parts.Add("$($detailSession.FailureCount) failed launch$(if ($detailSession.FailureCount -ne 1) { 'es' })")
            # Shown here as well as in the log, because an account that never starts at all
            # has no drops and no uptime, so the reason was the one thing the window did not say
            if ($detailSession.LastFailureReason) { $parts.Add($detailSession.LastFailureReason) }
        }

        # Written as escapes, not literal characters: the file has no BOM, so PowerShell
        # 5.1 reads it as ANSI and a literal middle dot would come out as mojibake
        $separator = "  " + [char]0x00B7 + "  "
        $detailLabel.Text = "$detailAccount  " + [char]0x2013 + "  " + ($parts -join $separator)
    }
    else
    {
        $detailLabel.Text = if ($accountList.SelectedItems.Count -gt 1) { "$($accountList.SelectedItems.Count) accounts selected" } else { "" }
    }

    # Shown on the strip at the top because that is the one thing always on screen, and
    # only redrawn when it changes so a click is not stolen mid press
    $shownVersion = if ($script:newerVersion) { $script:newerVersion } else { "" }
    if ($elevationStrip.Tag -ne $shownVersion)
    {
        $elevationStrip.Tag = $shownVersion
        if ($shownVersion)
        {
            $elevationStrip.Text = ($elevationStripText + [char]0x000A +
                                    "Version $shownVersion is out and this is $(Get-OwnVersion). Click here to download it.")
            $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(22, 38, 50)
            $elevationStrip.ForeColor = $themeAccent
            $elevationStrip.Cursor = [System.Windows.Forms.Cursors]::Hand
        }
        else
        {
            $elevationStrip.Text = $elevationStripText
            $elevationStrip.BackColor = $elevationStripBack
            $elevationStrip.ForeColor = $elevationStripFore
            $elevationStrip.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    $selectedCount = $accountList.SelectedItems.Count
    $relaunchButton.Enabled = $selectedCount -gt 0
    $pauseAccountButton.Enabled = $selectedCount -gt 0
    if ($selectedCount -gt 0)
    {
        # The count only earns its place once there is more than one
        $what = if ($selectedCount -gt 1) { "$selectedCount selected" } else { "selected" }
        $relaunchButton.Text = "Relaunch $what"

        # Matches what the click will do: any running account means the button pauses
        $anyRunning = $false
        foreach ($selectedItem in $accountList.SelectedItems)
        {
            if (-not $sessions[$selectedItem.Tag].Paused) { $anyRunning = $true; break }
        }
        $pauseAccountButton.Text = if ($anyRunning) { "Pause $what" } else { "Resume $what" }
    }
    else
    {
        $relaunchButton.Text = "Relaunch selected"
        $pauseAccountButton.Text = "Pause selected"
    }

    if ($script:logBox -and -not $script:logBox.IsDisposed)
    {
        # Only rewrite when there is something new, otherwise the caret fights the user
        if ($script:logBox.Lines.Count -ne $recentLogLines.Count)
        {
            $script:logBox.Text = ($recentLogLines -join "`r`n")
            $script:logBox.SelectionStart = $script:logBox.TextLength
            $script:logBox.ScrollToCaret()
        }
    }
}

# ---- Ticks ------------------------------------------------------------------------

function Invoke-SlowChecks
{
    if (-not $script:globalPaused)
    {
        try
        {
            $freeMegabytes = Get-FreeMegabytes
            $script:lastFreeMegabytes = [int]$freeMegabytes
            if ($freeMegabytes -ge $minimumFreeMegabytes) { $script:lowMemoryAlerted = $false }

            # A closing client takes a while to hand its memory back, and the check runs
            # every ten seconds, so without a gap a machine that stays low closes one alt
            # after another until there are none left. One at a time, then wait and look
            # again.
            $killCooldownOver = (-not $script:lastMemoryKillAt) -or
                                (((Get-Date) - $script:lastMemoryKillAt).TotalSeconds -ge $memoryKillCooldownSeconds)

            if ($minimumFreeMegabytes -gt 0 -and $freeMegabytes -lt $minimumFreeMegabytes -and $killCooldownOver)
            {
                $largestAlt = Get-RobloxClients |
                    Where-Object { $_.Id -ne $sessions[$mainAccount].ProcessId } |
                    Sort-Object WorkingSet64 -Descending |
                    Select-Object -First 1

                if ($largestAlt)
                {
                    Stop-Process -Id $largestAlt.Id -Force -ErrorAction SilentlyContinue
                    $script:lastMemoryKillAt = Get-Date
                    Write-Log ("killed PID $($largestAlt.Id) ($([int]($largestAlt.WorkingSet64 / 1MB)) MB), free was " +
                               "$([int]$freeMegabytes) MB, not closing another for $memoryKillCooldownSeconds s")
                }
                else
                {
                    Write-Log "WARNING: only $([int]$freeMegabytes) MB free and no alt left to kill"
                    if (-not $script:lowMemoryAlerted)
                    {
                        $script:lowMemoryAlerted = $true                              # once, not every ten seconds
                        Send-DiscordAlert "Out of memory" ("Only $([int]$freeMegabytes) MB free and there is no alt left to close. " +
                            "Main is never closed, so nothing more can be freed automatically.") $alertRed
                    }
                }
            }
        }
        catch
        {
            Write-Log "WARNING: memory check failed: $($_.Exception.Message)"
        }

        try
        {
            Remove-StrayClients
        }
        catch
        {
            Write-Log "WARNING: stray cleanup failed: $($_.Exception.Message)"
        }
    }
    else
    {
        try { $script:lastFreeMegabytes = [int](Get-FreeMegabytes) } catch { }
    }

    # A single disconnect is routine and not worth a notification; several at once means
    # the server went down and is worth knowing about, so they are collected and sent once
    $droppedThisPass = New-Object System.Collections.Generic.List[string]
    $mainDroppedThisPass = $false

    # A relog needs no relaunch, but the account comes back with its character respawned
    # and its inventory in the hotbar, so anything that was set up by hand has to be done
    # again. That is worth being told about even though nothing went wrong.
    $reloggedThisPass = New-Object System.Collections.Generic.List[string]
    $mainReloggedThisPass = $false

    # Focusing a window and holding a key takes most of a second, so only one account
    # gets poked per pass; several at once would visibly freeze the window
    $antiIdleSentThisPass = $false

    # One launch at a time. The old blocking design serialised launches by accident;
    # stepping through them does not, and launching several at once means the "which
    # process just appeared" check cannot tell them apart.
    $launchInFlight = $false
    foreach ($otherSession in $sessions.Values)
    {
        if ($otherSession.State -eq "Launching" -or $otherSession.State -eq "FindingLog" -or
            $otherSession.State -eq "Tiling")
        {
            $launchInFlight = $true
            break
        }
    }

    # Nothing launches while main is running its steps. A client loading is far heavier
    # than one already playing, and that is what makes the frame rate wobble, which is
    # the one thing a timed walk cannot survive. Main gets the machine to itself until
    # the sequence is done.
    if ($script:stepRun.Active) { $launchInFlight = $true }

    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        if ($session.Paused) { continue }
        try
        {
            if ($session.State -eq "Idle")
            {
                if (-not $script:globalPaused -and -not $launchInFlight -and
                    (Get-Date) -ge $session.RelaunchAfter)
                {
                    $launchInFlight = $true                                           # the rest wait their turn
                    try
                    {
                        Request-Launch $accountName
                    }
                    catch
                    {
                        Register-LaunchFailure $accountName $_.Exception.Message
                        $launchInFlight = $false                                      # nothing actually started
                    }
                }
            }
            elseif ($session.State -eq "Running")
            {
                if (-not (Get-SessionProcess $session))
                {
                    # Roblox 0.741 can hand a session over to a new process and let the old
                    # one exit, so a process going away is not proof the account is gone. If
                    # exactly one client is unclaimed and sitting on in-game memory, it is
                    # this session carrying on somewhere else, and relaunching would throw
                    # away a game that is running.
                    $claimedIds = @($sessions.Values | ForEach-Object { $_.ProcessId } | Where-Object { $_ -ne 0 })
                    $handover = @(Get-Process $processName -ErrorAction SilentlyContinue |
                        Where-Object { $claimedIds -notcontains $_.Id -and $_.MainWindowHandle -ne 0 -and
                                       $_.WorkingSet64 -ge $joinedMemoryBytes })

                    if ($handover.Count -eq 1 -and -not $launchInFlight)
                    {
                        $session.ProcessId = $handover[0].Id
                        $session.ProcessStartTime = $handover[0].StartTime
                        $session.WindowSeenAt = $null
                        $session.AppliedRect = $null
                        Write-Log ("$accountName's process went away, but PID $($handover[0].Id) is unclaimed and " +
                                   "using $([int]($handover[0].WorkingSet64 / 1MB)) MB, so the session was handed " +
                                   "over to it rather than relaunched")
                        Set-SessionState $session "Tiling"                            # new process, new window to place
                    }
                    else
                    {
                        # Counted and alerted, unlike before: a main that dies this way used
                        # to be relaunched in silence, which is exactly the case worth waking
                        # up for
                        $script:lastDisconnectAt = Get-Date
                        $session.DropCount++
                        $session.LastDropAt = Get-Date
                        $session.LastDropReason = "its process went away"
                        $droppedThisPass.Add("$accountName (its process went away)")
                        if ($accountName -eq $mainAccount) { $mainDroppedThisPass = $true }
                        Stop-Session $accountName "is gone"
                    }
                }
                else
                {
                    # A session that never found a log is blind, so keep looking while it runs
                    if (-not $session.LogPath -and $session.JoinedAt -and -not $launchInFlight)
                    {
                        [void](Find-LogByElimination $accountName)
                    }

                    if ($session.LogPath)
                    {
                        $logged = Update-SessionFromLog $session                       # $null = nothing new to act on
                        $realDropReason = $null

                        if ($logged -and $logged.Reason)
                        {
                            if ($logged.RejoinAddress -and $logged.RejoinAddress -eq $session.ServerAddress)
                            {
                                # The game teleports players between rounds: the client leaves
                                # the server, logs a disconnect from three threads at once, and
                                # rejoins the same server in the same process about five
                                # seconds later. It was never gone. Killing it here is what
                                # reset the main account over and over, back to spawn with its
                                # rockets unplaced: 728 of the 785 disconnects in one log, 93%,
                                # were this and every one of them cost a healthy session.
                                $session.RelogCount++
                                # A relog respawns the character, so the setup is due again just as much as
                                # after a relaunch. Absorbing it instead of relaunching took away the only
                                # thing that used to notice, which left main standing at spawn with its
                                # rockets unplaced and nothing saying so.
                                $session.StepsPending = $true
                                $session.PendingDrop = $null
                                $reloggedThisPass.Add($accountName)
                                if ($accountName -eq $mainAccount) { $mainReloggedThisPass = $true }
                                Write-Log ("$accountName relogged into $($logged.RejoinAddress) by itself " +
                                           "(reason $($logged.Reason)), so the client is left alone, but its " +
                                           "character and inventory are back to the start")
                            }
                            elseif ($logged.RejoinAddress)
                            {
                                # Back in a game, but not on the server it belongs to. That
                                # is either this one account being moved away on its own, or
                                # the private server itself having moved and taken everyone
                                # with it. Which one cannot be told from this account alone,
                                # so it waits for the end of the pass.
                                $session.PendingDrop = $null
                                $session.PendingAddress = @{ Address = $logged.RejoinAddress; Reason = $logged.Reason }
                            }
                            elseif (-not $session.PendingDrop)
                            {
                                # No rejoin in this chunk, which may only mean the read landed
                                # in the gap between the disconnect and the rejoin, so give it
                                # a moment before throwing the session away
                                $session.PendingDrop = @{ Reason = $logged.Reason; At = Get-Date }
                                Write-Log ("$accountName logged a disconnect (reason $($logged.Reason)), waiting " +
                                           "$rejoinGraceSeconds s to see whether it comes back by itself")
                            }
                        }
                        elseif ($logged -and $logged.RejoinAddress -and $session.PendingDrop)
                        {
                            # The rejoin turned up in a later read than the disconnect did
                            if (-not $session.ServerAddress -or $logged.RejoinAddress -eq $session.ServerAddress)
                            {
                                $session.RelogCount++
                                $session.StepsPending = $true
                                $reloggedThisPass.Add($accountName)
                                if ($accountName -eq $mainAccount) { $mainReloggedThisPass = $true }
                                Write-Log ("$accountName relogged into $($logged.RejoinAddress) by itself after " +
                                           "reason $($session.PendingDrop.Reason), so the client is left alone, " +
                                           "but its character and inventory are back to the start")
                            }
                            else
                            {
                                $session.PendingAddress = @{ Address = $logged.RejoinAddress
                                                             Reason = $session.PendingDrop.Reason }
                            }
                            $session.PendingDrop = $null
                        }

                        # Nothing came back within the grace period, so it really has dropped
                        if ($session.PendingDrop -and
                            ((Get-Date) - $session.PendingDrop.At).TotalSeconds -ge $rejoinGraceSeconds)
                        {
                            $realDropReason = $session.PendingDrop.Reason
                            $session.PendingDrop = $null
                        }

                        if ($realDropReason)
                        {
                            $script:lastDisconnectAt = Get-Date
                            $session.DropCount++
                            $session.LastDropAt = Get-Date
                            $session.LastDropReason = $realDropReason
                            $droppedThisPass.Add("$accountName (reason $realDropReason)")
                            if ($accountName -eq $mainAccount) { $mainDroppedThisPass = $true }
                            Stop-Session $accountName "disconnected (reason $realDropReason)"
                        }
                    }

                    # Deliberately outside the log check: a session with no usable log
                    # still needs to know whether it got into the game
                    if ($session.State -eq "Running" -and -not $session.JoinedAt -and $session.StartedAt -and
                        ((Get-Date) - $session.StartedAt).TotalSeconds -gt $joinTimeoutSeconds)
                    {
                        # The log is not the only evidence, and trusting it alone killed a
                        # healthy client. Roblox 0.741 warm-starts clients: a launch can
                        # hand off to an existing session and destroy its starter, leaving
                        # a stub log that never mentions joining. Memory settles it. An
                        # in-game client sits on gigabytes; one stuck on an error screen
                        # never gets past a few hundred megabytes.
                        $liveProcess = Get-SessionProcess $session
                        if ($liveProcess -and $liveProcess.WorkingSet64 -ge $joinedMemoryBytes)
                        {
                            $session.JoinedAt = Get-Date
                            $session.NeverJoinedCount = 0
                            # Set here as well as in the log reader, or a warm-started main
                            # would never trigger its setup sequence
                            $session.StepsPending = $true
                            Write-Log ("$accountName has no join line in its log but is using " +
                                       "$([int]($liveProcess.WorkingSet64 / 1MB)) MB, so it is in the game")
                        }
                        else
                        {
                            # Launched and has a window, but never got in: sitting on a
                            # "failed to connect" screen, which no disconnect code is ever
                            # written for, so nothing else would notice it
                            $session.NeverJoinedCount++
                            Stop-Session $accountName "never joined the game within $joinTimeoutSeconds s (stuck on an error screen)"

                            # A join that fails for a reason relaunching cannot fix, a
                            # wrong private server link being the usual one, used to retry
                            # at full speed for ever. It backs off like a failed launch
                            # does, and says so once rather than silently churning.
                            if ($session.NeverJoinedCount -ge 2)
                            {
                                $backoffSeconds = [math]::Min($relaunchDelaySeconds * $session.NeverJoinedCount, 600)
                                $session.RelaunchAfter = (Get-Date).AddSeconds($backoffSeconds)
                                Write-Log "$accountName has failed to join $($session.NeverJoinedCount) times in a row, next try in $backoffSeconds s"
                            }
                            if ($session.NeverJoinedCount -eq $maximumLaunchFailures)
                            {
                                Write-Log "ERROR: $accountName keeps launching but never joining, check the private server link and that this account can join it"
                                Send-DiscordAlert "$accountName cannot join" ("It has launched and failed to get into the game " +
                                    "$maximumLaunchFailures times. The client is probably showing a join error such as 524, " +
                                    "which usually means the private server link is wrong or this account is not allowed in " +
                                    "that server.") $alertRed ($accountName -eq $mainAccount)
                            }
                        }
                    }

                    if ($session.State -eq "Running" -and $accountName -ne $mainAccount -and $session.StartedAt -and
                        ((Get-Date) - $session.StartedAt).TotalMinutes -gt $maximumSessionMinutes)
                    {
                        Stop-Session $accountName "is older than $maximumSessionMinutes min"
                    }
                }

                # A window that is no longer where we put it was moved by hand, so that
                # is where this account wants to be from now on. Compared against the
                # rectangle we applied rather than the computed slot, otherwise a
                # remembered position would keep re-detecting itself.
                if ($rememberWindowPositions -and $session.State -eq "Running" -and $session.AppliedRect)
                {
                    $liveProcess = Get-SessionProcess $session
                    if ($liveProcess)
                    {
                        $liveProcess.Refresh()
                        if ($liveProcess.MainWindowHandle -ne [IntPtr]::Zero)
                        {
                            $current = Get-WindowRectangle $liveProcess.MainWindowHandle
                            if ($current)
                            {
                                $applied = $session.AppliedRect -split ','
                                $movedBy = [math]::Max([math]::Abs($current.X - [int]$applied[0]),
                                                       [math]::Abs($current.Y - [int]$applied[1]))
                                if ($movedBy -gt $manualMoveThreshold)
                                {
                                    $session.AppliedRect = "$($current.X),$($current.Y),$($current.Width),$($current.Height)"
                                    Save-WindowPosition $accountName $session.AppliedRect
                                }
                            }
                        }
                    }
                }

                # Still running after the checks above, so it is due a keystroke if it
                # has gone quiet
                if ($antiIdleMinutes -gt 0 -and -not $script:globalPaused -and -not $antiIdleSentThisPass -and
                    $session.State -eq "Running" -and
                    $session.LastInputAt -and ((Get-Date) - $session.LastInputAt).TotalMinutes -ge (Get-AntiIdleInterval))
                {
                    Send-AntiIdleInput $accountName
                    $antiIdleSentThisPass = $true
                }
            }
        }
        catch
        {
            Write-Log "WARNING: checking $accountName failed: $($_.Exception.Message)"
        }
    }

    # Main dropping is the one worth being interrupted for, so it pings. Sent as one
    # message either way: if main went down with the others, the group alert carries the
    # ping rather than firing a second notification for the same event.
    # Every account that came back somewhere unexpected is decided here rather than when
    # it was seen, because one account cannot tell the difference on its own. If several
    # landed on the same new server, the private server moved and took them with it: that
    # happened at 20:38 on 04-10 and all six were closed and relaunched for nothing. If
    # an account is alone on an address nobody else is on, it really has been moved out
    # of the farm and does need relaunching.
    $parked = @($allAccounts | Where-Object { $sessions[$_].PendingAddress })

    # Taken as a snapshot first. Clearing each one as the loop goes would mean every
    # account after the first saw fewer accounts agreeing with it than the one before.
    $parkedAddress = @{}
    foreach ($accountName in $parked) { $parkedAddress[$accountName] = $sessions[$accountName].PendingAddress }

    foreach ($accountName in $parked)
    {
        $session = $sessions[$accountName]
        $address = $parkedAddress[$accountName].Address
        $reason = $parkedAddress[$accountName].Reason
        $session.PendingAddress = $null

        # Everyone sitting on that address already, plus everyone who moved to it in
        # this same pass. Counts itself, so one witness means nobody else agrees.
        $witnesses = @($allAccounts | Where-Object {
            $sessions[$_].ServerAddress -eq $address -or
            ($parkedAddress.ContainsKey($_) -and $parkedAddress[$_].Address -eq $address) }).Count

        if ($witnesses -ge $migrationWitnesses)
        {
            $session.ServerAddress = $address
            $session.RelogCount++
            $session.StepsPending = $true
            $reloggedThisPass.Add($accountName)
            if ($accountName -eq $mainAccount) { $mainReloggedThisPass = $true }
            Write-Log ("$accountName moved to $address with $($witnesses - 1) other account$(if ($witnesses -ne 2) { 's' }), " +
                       "so the private server moved rather than the account dropping (reason $reason)")
        }
        else
        {
            $script:lastDisconnectAt = Get-Date
            $session.DropCount++
            $session.LastDropAt = Get-Date
            $session.LastDropReason = "$reason, left for $address on its own"
            $droppedThisPass.Add("$accountName (reason $reason, left for $address on its own)")
            if ($accountName -eq $mainAccount) { $mainDroppedThisPass = $true }
            Stop-Session $accountName "came back on $address, which no other account is on"
        }
    }

    if ($mainDroppedThisPass)
    {
        if ($droppedThisPass.Count -gt 1)
        {
            Send-DiscordAlert "Main dropped, with $($droppedThisPass.Count - 1) other$(if ($droppedThisPass.Count -ne 2) { 's' })" ((
                "They are being relaunched one at a time.`n`n" + ($droppedThisPass -join "`n"))) $alertRed $true
        }
        else
        {
            Send-DiscordAlert "Main dropped" ("$($droppedThisPass[0]).`n`nIt is being relaunched.") $alertRed $true
        }
    }
    elseif ($droppedThisPass.Count -gt 1)
    {
        Send-DiscordAlert "$($droppedThisPass.Count) accounts dropped at once" ((
            "They are being relaunched one at a time.`n`n" + ($droppedThisPass -join "`n"))) $alertAmber
    }

    if ($discordSummaryMinutes -gt 0 -and ((Get-Date) - $script:lastSummaryAt).TotalMinutes -ge $discordSummaryMinutes)
    {
        $script:lastSummaryAt = Get-Date
        $playing = 0
        $notPlaying = New-Object System.Collections.Generic.List[string]
        foreach ($accountName in $allAccounts)
        {
            $session = $sessions[$accountName]
            if ($session.State -eq "Running" -and $session.JoinedAt) { $playing++ }
            else { $notPlaying.Add("$accountName - $(Get-SessionStatusText $accountName)") }
        }
        $watchdogUp = (Get-Date) - $watchdogStartedAt
        $summary = "**$playing / $($allAccounts.Count)** playing`n" +
                   "Free memory: $script:lastFreeMegabytes MB`n" +
                   ("Watchdog up: {0}h{1:00}m" -f [int]$watchdogUp.TotalHours, $watchdogUp.Minutes)
        if ($notPlaying.Count -gt 0) { $summary += "`n`nNot playing:`n" + ($notPlaying -join "`n") }
        $color = if ($playing -eq $allAccounts.Count) { $alertGreen } else { $alertAmber }
        Send-DiscordAlert "Status" $summary $color
    }

    # Main has just got back into the game, so the one-off setup is due again. With a step
    # list it either runs itself or waits for Run to be pressed; with none, there is
    # nothing to run and the notice below is the whole of it.
    $mainSession = $sessions[$mainAccount]
    $stepsWaiting = $false
    if ($stepListText -and $mainSession.StepsPending -and $mainSession.State -eq "Running" -and $mainSession.JoinedAt)
    {
        $mainSession.StepsPending = $false
        if ($runStepsOnRejoin)
        {
            Start-StepRun "$mainAccount rejoined"
        }
        else
        {
            $stepsWaiting = $true
            Write-Log "$mainAccount is back in the game, the steps are waiting for you to press Run"
        }
    }

    # Nothing has gone wrong, so this is not an error, but the account comes back with its
    # character respawned and its inventory in the hotbar. Anything placed by hand has to
    # be placed again, which is worth being told. Main is always worth saying, because it
    # is the one with a setup; a whole group relogging at once is worth saying because it
    # means every one of them needs it. A single alt is logged and left at that.
    if ($mainReloggedThisPass -or $reloggedThisPass.Count -ge $relogWaveSize)
    {
        $others = @($reloggedThisPass | Where-Object { $_ -ne $mainAccount })
        if ($mainReloggedThisPass)
        {
            $tail = if ($stepsWaiting) { "Press Run in the watchdog window to set it up again." }
                    elseif ($stepListText) { "The steps are running now." }
                    else { "Its inventory is back in the hotbar, so the rockets need placing again." }
            $withOthers = if ($others.Count) { "`n`nAlso relogged: $($others -join ', ')" } else { "" }
            Send-DiscordAlert "Main relogged" ("$mainAccount went back into the game on its own, so it was not " +
                "relaunched and nothing is broken.`n`n$tail$withOthers") $alertAmber $true
        }
        else
        {
            Send-DiscordAlert "$($reloggedThisPass.Count) accounts relogged" ("They went back into the game on " +
                "their own, so none of them were relaunched.`n`n$($reloggedThisPass -join ', ')`n`nTheir characters " +
                "and inventories are back to the start.") $alertAmber
        }
    }

    if (-not $script:lastVersionCheckAt -or
        ((Get-Date) - $script:lastVersionCheckAt).TotalHours -ge $versionCheckHours)
    {
        Start-VersionCheck
    }
    Complete-VersionCheck

    Complete-PendingWebhooks
}

function Invoke-WatchdogTick
{
    $script:tickCount++

    # Every tick: move any launch along by one step. These are the only states that
    # need to be watched closely, and each step returns immediately.
    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        if ($session.State -eq "Idle" -or $session.State -eq "Running") { continue }
        try
        {
            if ($session.State -eq "Launching")      { Step-Launching $accountName }
            elseif ($session.State -eq "FindingLog") { Step-FindingLog $accountName }
            elseif ($session.State -eq "Tiling")     { Step-Tiling $accountName }
        }
        catch
        {
            Register-LaunchFailure $accountName $_.Exception.Message
        }
    }

    # Also every tick, so the waits inside a sequence are honoured to the tick rather
    # than to the ten second checks
    try
    {
        if (-not $script:globalPaused) { Step-StepRun }
        elseif ($script:stepRun.Active) { Stop-StepRun "paused" }
    }
    catch
    {
        Write-Log "WARNING: step run failed: $($_.Exception.Message)"
        Stop-StepRun "it errored"
    }

    if (($script:tickCount % $slowTicksPerCheck) -eq 0)
    {
        try
        {
            Invoke-SlowChecks
        }
        catch
        {
            Write-Log "WARNING: tick failed: $($_.Exception.Message)"
        }
    }

    if (($script:tickCount % $uiTicksPerRefresh) -eq 0)
    {
        try
        {
            Update-StatusUi
        }
        catch
        {
            # never let a redraw problem take the watchdog down
        }
    }
}

$tickTimer = New-Object System.Windows.Forms.Timer
$tickTimer.Interval = $tickMilliseconds
$tickTimer.Add_Tick({ Invoke-WatchdogTick })
$tickTimer.Start()

Update-StatusUi
[System.Windows.Forms.Application]::Run($statusForm)

$tickTimer.Stop()
Write-Log "watchdog stopped"
