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
# 012          06-10-2026 Miniwar AFK FG  Roblox kan een join weigeren met 403 en challengedByGcs, waarna de client de
#                                         vasthoudcontrole laat zien. Dat zag eruit als vastlopen op een foutmelding,
#                                         dus werd de client na 150 seconden gesloten en opnieuw gestart: drie keer in
#                                         zeven minuten op 05-10, en elke poging vraagt Roblox opnieuw. Nu wordt het
#                                         venster met rust gelaten tot iemand de controle doet, met een melding erbij,
#                                         en daarna gaat het account gewoon verder.
# 013          06-10-2026 Miniwar AFK FG  Pauze stopte het herstarten maar niet het kijken: er werd nog gelezen, nog
#                                         besloten dat een account van server was gewisseld, en nog een client
#                                         gesloten om een disconnect die daarna niet herstart kon worden. Pauze doet
#                                         nu niets meer, en bij hervatten wordt wat de logbestanden in de tussentijd
#                                         kregen overgeslagen. Verder een instelling om de al openstaande Roblox
#                                         vensters over te nemen in plaats van ze te sluiten en opnieuw te starten:
#                                         de oudste wordt main en de rest alts op volgorde van starten, elk met het
#                                         eigen logbestand dat via de starttijd van het proces wordt gevonden.
#                                         Sluiten en overnemen zijn tegenpolen, dus in het instellingenvenster kan er
#                                         maar een van de twee aan staan: de ander gaat uit zodra je er een aanzet.
# 014          06-10-2026 Miniwar AFK FG  Vensterposities onthouden werkte voor veel mensen niet. Drie oorzaken: de
#                                         grootte werd nooit vergeleken, dus alleen slepen werd gezien en niet het
#                                         veranderen van de grootte; er was 60 pixels nodig voordat slepen meetelde;
#                                         en als het verplaatsen werd geweigerd, wat gebeurt als de clients als
#                                         administrator draaien en de watchdog niet, bleef er niets om tegen te
#                                         vergelijken en deed de hele functie niets. Nu wordt de echt gemeten
#                                         rechthoek bewaard, ook na een geweigerde verplaatsing. Daarnaast twee
#                                         knoppen om de hele indeling met groottes op te slaan en terug te zetten.
# 015          06-10-2026 Miniwar AFK FG  Anti-idle nam alleen Space of een losse letter. Nu elke letter, cijfer of
#                                         benoemde toets die de stappenlijst ook kent, of een plek in het venster om
#                                         op te klikken, met een Pick knop die de toets of de plek voor je opschrijft.
#                                         Ook opgelost: de muisbeweging in de agressieve stand las Left en Top van een
#                                         rechthoek die X en Y heet, dus de cursor werd sinds 1.6.0 naar 0,0 gezet in
#                                         plaats van naar het midden van het venster.
# 016          06-10-2026 Miniwar AFK FG  Space koos in de picker niets: Space en Enter activeren de knop die focus
#                                         heeft, en dat was de Pick knop zelf, dus de vraag werd geantwoord en de
#                                         knop opnieuw ingedrukt. Knop staat nu uit tijdens het kiezen. Verder kan
#                                         er nu ctrl, alt of shift bij gehouden worden, en bij het starten gaat er
#                                         geen Discord bericht meer uit tenzij het na een crash zelf terugkwam.
# 017          06-10-2026 Miniwar AFK FG  Agressieve anti-idle negeert nu de ingestelde toets of plek en loopt en
#                                         springt in plaats daarvan. Een personage dat beweegt en springt is
#                                         moeilijker te verwarren met iemand die stilzit dan een losse toets.
# 018          07-10-2026 Miniwar AFK FG  Meerdere servers. Elke server heeft zijn eigen link, place, accounts,
#                                         stappenlijst, relogtijd, anti-idle en limieten; main is per server en op de
#                                         extra servers optioneel. Het instellingenvenster is opnieuw opgezet met
#                                         tabbladen (Servers, Account Manager, Windows, Alerts, Housekeeping) in
#                                         plaats van een lange kolom. Een server kan er tijdens het draaien bij, met
#                                         de knop Add server: lopende accounts houden hun sessie en venster, nieuwe
#                                         komen er achteraan bij en starten op hun beurt.
# 019          07-10-2026 Miniwar AFK FG  Nieuw kleurenpalet: donker paars met magenta als accent en oranje voor een
#                                         main. De tabbladen zijn geen TabControl meer maar eigen knoppen: Windows
#                                         tekent tabkoppen zelf en negeert BackColor, en ook met OwnerDrawFixed blijft
#                                         de strook eromheen wit. De serverlijst tekent zijn eigen regels, want een
#                                         ListBox gebruikt anders het blauw van Windows. Add server stond bovenop de
#                                         melding over de tray; het venster is 48 pixels hoger.
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
$manualMoveThreshold = 12                                                            # further than Roblox's own nudging, so only a real drag counts
$stepGapMilliseconds = 200                                                           # between steps with no explicit wait of their own
# Account, because with more than one server there is more than one main with a setup to
# run. Only one runs at a time: a step run holds the keyboard and the foreground, so two
# at once would fight over both. The others keep their setup pending and get their turn.
$stepRun = @{ Active = $false; Steps = @(); Index = 0; NextAt = $null; Reason = $null; HeldKey = $null
              Account = $null }
$maximumLaunchFailures = 5                                                           # log loudly after this many failed launches in a row
$logFolder = Join-Path $env:LOCALAPPDATA "Roblox\logs"                              # Roblox client log files
$disconnectPattern = "Sending disconnect with reason: (\d+)"                         # logged on drop (277) and leave (285)
$ignoredDisconnectReasons = @()                                                      # never acted on at all; a teleport is recognised, not listed here
$joinMarker = "Connection accepted"                                                  # logged only once the client is really in the game
$joinAddressPattern = "Connection accepted from ([0-9.]+\|[0-9]+)"                   # the server it joined, so a rejoin can be compared with it
$teleportMarker = "SessionTransitionFSM] Teleported."                                # the game moving the player, which no real drop ever logs
$challengePattern = "challengedByGcs|challengePageLoaded"                            # Roblox refusing the join until a person passes its check
$rejoinGraceSeconds = 30                                                             # a teleport is back in about 5 s, so this is plenty
$migrationWitnesses = 2                                                              # accounts landing on the same new server before it counts as a move
$relogWaveSize = 3                                                                   # accounts relogging together before it is worth saying so on its own
$logLivenessSeconds = 120                                                            # a log written more recently than this belongs to a live client
$watchdogVersion = "2.1.0"                                                           # the build stamps the exe with this too, and the exe wins at runtime
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
# Flat fills only, no gradients. Raised is for the one thing that is selected, and the
# second accent is kept for marking a main, so the first accent never has to mean two
# different things at once.
$themeBackground = [System.Drawing.Color]::FromArgb(23, 19, 31)                      # 17131F
$themeSurface    = [System.Drawing.Color]::FromArgb(34, 27, 46)                      # 221B2E
$themeRaised     = [System.Drawing.Color]::FromArgb(46, 36, 64)                      # 2E2440
$themeBorder     = [System.Drawing.Color]::FromArgb(61, 49, 82)                      # 3D3152
$themeText       = [System.Drawing.Color]::FromArgb(239, 233, 245)                   # EFE9F5
$themeMuted      = [System.Drawing.Color]::FromArgb(151, 139, 168)                   # 978BA8
$themeAccent     = [System.Drawing.Color]::FromArgb(232, 121, 199)                   # E879C7
$themeAccent2    = [System.Drawing.Color]::FromArgb(251, 146, 60)                    # FB923C, a main
$themeGreen      = [System.Drawing.Color]::FromArgb(74, 222, 128)                    # 4ADE80
$themeAmber      = [System.Drawing.Color]::FromArgb(251, 191, 36)                    # FBBF24
$themeRed        = [System.Drawing.Color]::FromArgb(251, 113, 133)                   # FB7185
$themeGrey       = [System.Drawing.Color]::FromArgb(124, 112, 138)                   # paused, deliberately flat

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
        $button.ForeColor = $themeBackground                                           # dark text on the accent, so it reads
        $button.FlatAppearance.BorderColor = $themeAccent
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(240, 150, 212)
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

function Get-KeyNameFromCode($code)
{
    # The other direction from Get-StepKeyCode, so a picker can write back something the
    # settings field accepts and a person can read
    $named = @{ 0x20 = "space"; 0x10 = "shift"; 0x11 = "ctrl"; 0x12 = "alt"; 0x09 = "tab"
                0x0D = "enter"; 0x1B = "esc"; 0x26 = "up"; 0x28 = "down"; 0x25 = "left"; 0x27 = "right" }
    if ($named.ContainsKey([int]$code)) { return $named[[int]$code] }
    if (($code -ge 0x30 -and $code -le 0x39) -or ($code -ge 0x41 -and $code -le 0x5A))
    {
        return ([string][char][int]$code).ToLower()                               # lower case, like the modifier names and the step list

    }
    return $null
}

function Test-KeyDown($code)
{
    # Its own function so the picker can be driven in a test without a keyboard. The high
    # bit means the key is down right now.
    return ([Win32.Window]::GetAsyncKeyState($code) -lt 0)
}

function Get-AntiIdleModifiers
{
    # In the order they are written, so ctrl+alt+e always comes out the same way round
    return [ordered]@{ ctrl = 0x11; alt = 0x12; shift = 0x10 }
}

function Get-AntiIdlePickableCodes
{
    # Only what can actually be sent: the letters, the digits and the named keys. Escape
    # is left out because the picker uses it to cancel.
    $codes = New-Object System.Collections.Generic.List[int]
    0x20, 0x10, 0x11, 0x12, 0x09, 0x0D, 0x26, 0x28, 0x25, 0x27 | ForEach-Object { $codes.Add($_) }
    0x30..0x39 | ForEach-Object { $codes.Add($_) }
    0x41..0x5A | ForEach-Object { $codes.Add($_) }
    return $codes
}

function Get-CursorPoint
{
    # Wrapped so the picker can be driven in a test without a mouse
    $point = New-Object POINT
    if (-not [WinPos]::GetCursorPos([ref]$point)) { return $null }
    return [pscustomobject]@{ X = $point.X; Y = $point.Y }
}

function Wait-NoKeyDown($seconds)
{
    # Whatever dismissed the dialog is probably still held: the OK click, or the Enter or
    # Space that pressed its button. Capturing before that comes up reads the dismissal
    # as the answer.
    $watched = @(Get-AntiIdlePickableCodes) + @(0x01)
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline)
    {
        $anyDown = $false
        foreach ($code in $watched)
        {
            if (Test-KeyDown $code) { $anyDown = $true; break }
        }
        if (-not $anyDown) { return $true }
        Start-Sleep -Milliseconds 30
    }
    return $false
}

function Get-PickedAntiIdleInput($windowRect, $seconds)
{
    # Returns what to put in the box: a key, a combination, a click, or $null if it was
    # cancelled or nothing happened in time.
    #
    # Modifiers on their own do not finish the pick, so holding ctrl and then tapping e
    # gives ctrl+e. Letting a modifier go without pressing anything with it gives the
    # modifier by itself, which is how shift alone can still be chosen.
    $modifierTable = Get-AntiIdleModifiers
    $modifierCodes = @($modifierTable.Values)
    $baseCodes = @(Get-AntiIdlePickableCodes | Where-Object { $modifierCodes -notcontains $_ })
    $lastHeldNames = @()

    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline)
    {
        if (Test-KeyDown 0x1B) { return $null }                                       # VK_ESCAPE cancels

        $heldNames = New-Object System.Collections.Generic.List[string]
        foreach ($name in $modifierTable.Keys)
        {
            if (Test-KeyDown $modifierTable[$name]) { $heldNames.Add($name) }
        }

        foreach ($code in $baseCodes)
        {
            if (-not (Test-KeyDown $code)) { continue }
            $name = Get-KeyNameFromCode $code
            if (-not $name) { continue }
            $pieces = @($heldNames) + @($name)
            return ($pieces -join "+")
        }

        # A modifier that was held and then let go, with nothing pressed alongside it
        if ($heldNames.Count -eq 0 -and $lastHeldNames.Count -eq 1)
        {
            return $lastHeldNames[0]
        }
        $lastHeldNames = @($heldNames)

        if ($windowRect -and (Test-KeyDown 0x01))                                     # VK_LBUTTON
        {
            $point = Get-CursorPoint
            if (-not $point) { return $null }
            $fractionX = [math]::Round((($point.X - $windowRect.X) / $windowRect.Width), 4)
            $fractionY = [math]::Round((($point.Y - $windowRect.Y) / $windowRect.Height), 4)
            if ($fractionX -lt 0 -or $fractionX -gt 1 -or $fractionY -lt 0 -or $fractionY -gt 1)
            {
                return "outside"
            }
            return "click $fractionX,$fractionY"
        }
        Start-Sleep -Milliseconds 30
    }
    return $null
}

function Get-AntiIdleAction($setting)
{
    # The anti-idle used to take Space or a single letter and nothing else. It now takes
    # anything the step list takes, which is any letter, digit or named key, plus a spot
    # in the window to click. Same vocabulary as the step list on purpose: one thing to
    # learn, and the picker writes it for you.
    $trimmed = "$setting".Trim()
    if (-not $trimmed) { throw "Anti-idle needs a key or a spot to click" }

    if ($trimmed -match '^click\s+([0-9]*\.?[0-9]+)\s*,\s*([0-9]*\.?[0-9]+)$')
    {
        $fractionX = [double]$Matches[1]
        $fractionY = [double]$Matches[2]
        if ($fractionX -lt 0 -or $fractionX -gt 1 -or $fractionY -lt 0 -or $fractionY -gt 1)
        {
            throw "An anti-idle click has to be inside the window, so both numbers have to be between 0 and 1"
        }
        return [pscustomobject]@{ Kind = "click"; X = $fractionX; Y = $fractionY; Label = "a click at $fractionX,$fractionY" }
    }

    # Something meant as a click but written wrong would otherwise fall through to the
    # key error and be told it is not a letter, which is no help at all
    if ($trimmed -match '^click\b')
    {
        throw "An anti-idle click is written as 'click 0.5,0.6': two numbers between 0 and 1, which are fractions of the window"
    }

    # ctrl+e, alt+shift+w, and so on. Held while the key is tapped, then released, which
    # is what a game sees as a real shortcut rather than two separate presses.
    $modifierTable = Get-AntiIdleModifiers
    $pieces = @($trimmed -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($pieces.Count -gt 1 -or ($trimmed -match '\+'))
    {
        if ($pieces.Count -lt 2)
        {
            throw "A combination needs a key after the modifier, like 'ctrl+e'"
        }
        $modifierCodes = New-Object System.Collections.Generic.List[byte]
        $names = New-Object System.Collections.Generic.List[string]
        for ($index = 0; $index -lt $pieces.Count - 1; $index++)
        {
            $name = $pieces[$index].ToLower()
            if (-not $modifierTable.Contains($name))
            {
                throw "'$($pieces[$index])' is not a modifier. Only ctrl, alt and shift can be held, like 'ctrl+e'"
            }
            if ($modifierCodes -contains [byte]$modifierTable[$name])
            {
                throw "'$name' is held twice in '$trimmed'"
            }
            $modifierCodes.Add([byte]$modifierTable[$name])
            $names.Add($name)
        }
        $baseName = $pieces[$pieces.Count - 1]
        if ($modifierTable.Contains($baseName.ToLower()))
        {
            throw "'$trimmed' is only modifiers. One of them has to be a key, like 'ctrl+e'"
        }
        $baseCode = Get-StepKeyCode $baseName 0
        $names.Add($baseName)
        return [pscustomobject]@{ Kind = "key"; Key = [byte]$baseCode; Modifiers = $modifierCodes.ToArray()
                                  Label = ($names -join "+") }
    }

    # Get-StepKeyCode throws with the list of what it accepts, which is the message worth
    # showing here too, so it is left to do the talking
    $code = Get-StepKeyCode $trimmed 0
    return [pscustomobject]@{ Kind = "key"; Key = [byte]$code; Modifiers = @(); Label = $trimmed }
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

function Get-DefaultServer
{
    # One private server and the accounts that farm it. Everything here can differ from
    # one server to the next; anything that belongs to the machine or to Account Manager
    # is in the settings around it instead.
    return @{
        Name                  = "Server 1"
        PlaceId               = ""
        PrivateServerLink     = ""
        MainAccount           = ""
        AltAccounts           = ""
        StepList              = ""
        RunStepsOnRejoin      = "False"
        MaximumSessionMinutes = "45"
        AntiIdleMinutes       = "15"
        AntiIdleKey           = "Space"
        AggressiveAntiIdle    = "False"
        FramerateCap          = "30"
        MinimumFreeMegabytes  = "3000"
    }
}

# The keys a server owns, which is also the list the migration copies across and the
# settings window writes back. Kept in one place so the three cannot drift apart.
$serverOwnedKeys = @("Name", "PlaceId", "PrivateServerLink", "MainAccount", "AltAccounts", "StepList",
                     "RunStepsOnRejoin", "MaximumSessionMinutes", "AntiIdleMinutes", "AntiIdleKey",
                     "AggressiveAntiIdle", "FramerateCap", "MinimumFreeMegabytes")

function ConvertTo-ServerRecord($value)
{
    # Whatever came out of the json, laid over a full set of defaults so a server saved
    # by an older version still has every key
    $server = Get-DefaultServer
    if ($value)
    {
        foreach ($property in $value.PSObject.Properties)
        {
            if ($serverOwnedKeys -contains $property.Name) { $server[$property.Name] = [string]$property.Value }
        }
    }
    return $server
}

function Get-ServerAccounts($server)
{
    # Main first when there is one, then the alts. A server without a main is allowed:
    # only the first one really needs somebody to set the rockets up.
    $accounts = New-Object System.Collections.Generic.List[string]
    $main = "$($server.MainAccount)".Trim()
    if ($main) { $accounts.Add($main) }
    foreach ($line in ("$($server.AltAccounts)" -split "`r?`n"))
    {
        $name = $line.Trim()
        if ($name -and -not $accounts.Contains($name)) { $accounts.Add($name) }
    }
    return $accounts.ToArray()
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
        AdoptOpenClients       = "False"
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
        Servers                 = @(Get-DefaultServer)
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
        if ($property.Name -eq "Servers") { continue }                                 # a list, not a string
        $settings[$property.Name] = [string]$property.Value
    }

    # A file written before servers existed has the place, the link, the accounts and the
    # rest at the top level. Those become the first server, so nobody has to type their
    # setup in again.
    if ($json.PSObject.Properties.Name -contains "Servers" -and $json.Servers)
    {
        $settings["Servers"] = @($json.Servers | ForEach-Object { ConvertTo-ServerRecord $_ })
    }
    else
    {
        $first = Get-DefaultServer
        foreach ($key in $serverOwnedKeys)
        {
            if ($key -eq "Name") { continue }
            if ($json.PSObject.Properties.Name -contains $key) { $first[$key] = [string]$json.$key }
        }
        $settings["Servers"] = @($first)
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
    # Depth, because the servers are a list of records inside the object and the default
    # of 2 would flatten them into strings that read "System.Collections.Hashtable"
    $toSave | ConvertTo-Json -Depth 6 | Set-Content $settingsPath -Encoding UTF8
    Protect-SettingsFile $settingsPath

    # The old file kept the password in clear text, so it does not stay behind
    if ((Test-Path $legacySettingsPath) -and ($legacySettingsPath -ne $settingsPath))
    {
        Remove-Item $legacySettingsPath -Force -ErrorAction SilentlyContinue
        Write-Log "settings moved to $settingsPath, removed the old plain text $legacySettingsPath"
    }
}

function Set-TabButtonLook($button, $isActive)
{
    $button.BackColor = if ($isActive) { $themeRaised } else { $themeBackground }
    $button.ForeColor = if ($isActive) { $themeText } else { $themeMuted }
    $button.FlatAppearance.MouseOverBackColor = if ($isActive) { $themeRaised } else { $themeSurface }
}

function Add-TabbedPages($container, $captions, $left, $top, $width, $height)
{
    # Our own tab row instead of a TabControl. Windows draws tab headers itself and
    # ignores BackColor, which left a white strip across the top of a dark window.
    # Owner drawing does not fix it either: DrawItem does fire, once per tab, but it only
    # owns the tab item rectangles and the strip around and above them stays system
    # painted. Sampling the rendered pixels showed 240,240,240 above the labels whatever
    # was drawn. A row of flat buttons over panels is fully ours, and it is where the
    # accent underline lives.
    $rowHeight = 28
    $pages = New-Object System.Collections.Specialized.OrderedDictionary
    $buttons = New-Object System.Collections.Generic.List[object]

    # the underline is one panel that moves to whichever button is active
    $indicator = New-Object System.Windows.Forms.Panel
    $indicator.BackColor = $themeAccent
    $indicator.Size = New-Object System.Drawing.Size(10, 3)
    # Sits just under the row rather than inside it. Overlapping the button meant
    # depending on z-order, which paints correctly on screen but not in a DrawToBitmap
    # render, so it could not be checked; clear of it, there is nothing to get wrong.
    $indicator.Location = New-Object System.Drawing.Point($left, ($top + $rowHeight))
    $container.Controls.Add($indicator)

    $measureFont = New-Object System.Drawing.Font("Segoe UI", 9)
    $graphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)

    $buttonLeft = $left
    foreach ($caption in $captions)
    {
        $page = New-Object System.Windows.Forms.Panel
        $page.Location = New-Object System.Drawing.Point($left, ($top + $rowHeight + 10))
        $page.Size = New-Object System.Drawing.Size($width, ($height - $rowHeight - 10))
        $page.BackColor = $themeBackground
        $page.Visible = ($pages.Count -eq 0)
        $container.Controls.Add($page)
        $pages[$caption] = $page

        $buttonWidth = [int][math]::Ceiling($graphics.MeasureString($caption, $measureFont).Width) + 22
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $caption
        $button.Tag = $caption
        $button.FlatStyle = "Flat"
        $button.FlatAppearance.BorderSize = 0
        $button.UseVisualStyleBackColor = $false
        $button.Cursor = "Hand"
        $button.Location = New-Object System.Drawing.Point($buttonLeft, $top)
        $button.Size = New-Object System.Drawing.Size($buttonWidth, $rowHeight)
        Set-TabButtonLook $button ($pages.Count -eq 1)
        $container.Controls.Add($button)
        $buttons.Add($button)

        if ($pages.Count -eq 1)
        {
            $indicator.Size = New-Object System.Drawing.Size($buttonWidth, 3)
            $indicator.Location = New-Object System.Drawing.Point($buttonLeft, ($top + $rowHeight))
        }
        $buttonLeft += $buttonWidth + 2
    }
    $graphics.Dispose()

    # One handler for every button, reading which one it was from the Tag, with the state
    # hung off the container so the handler does not have to capture anything
    # The indicator was added before the buttons so it would exist to be positioned,
    # which also put it behind them: a three pixel underline under a button that covers
    # it is not visible at all.
    $indicator.BringToFront()

    $container.Tag = @{ Pages = $pages; Buttons = $buttons; Indicator = $indicator; Top = $top; RowHeight = $rowHeight }
    foreach ($button in $buttons)
    {
        $button.Add_Click({
            $state = $this.Parent.Tag
            foreach ($name in @($state.Pages.Keys)) { $state.Pages[$name].Visible = ($name -eq $this.Tag) }
            foreach ($other in $state.Buttons) { Set-TabButtonLook $other ($other.Tag -eq $this.Tag) }
            $state.Indicator.Size = New-Object System.Drawing.Size($this.Width, 3)
            $state.Indicator.Location = New-Object System.Drawing.Point($this.Left, ($state.Top + $state.RowHeight))
            $state.Indicator.BringToFront()
        })
    }
    return $pages
}


function Add-FieldRow($page, $inputs, $labelText, $key, $value, $top, $height, $maskInput)
{
    # A caption on the left, a box on the right. Returns the top for the next row, so a
    # page is written as a list of these rather than arithmetic at every line.
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $labelText
    $label.Location = New-Object System.Drawing.Point(4, ($top + 3))
    $label.Size = New-Object System.Drawing.Size(210, 20)
    $label.ForeColor = $themeText
    $page.Controls.Add($label)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(220, $top)
    $box.Size = New-Object System.Drawing.Size(300, $height)
    $box.Text = "$value"
    $box.BackColor = $themeSurface
    $box.ForeColor = $themeText
    $box.BorderStyle = "FixedSingle"
    if ($height -gt 24)
    {
        $box.Multiline = $true
        $box.AcceptsReturn = $true
        $box.ScrollBars = "Vertical"
    }
    if ($maskInput) { $box.UseSystemPasswordChar = $true }
    $page.Controls.Add($box)
    $inputs[$key] = $box
    return ($top + $height + 10)
}

function Add-CheckRow($page, $inputs, $labelText, $key, $checked, $top)
{
    $box = New-Object System.Windows.Forms.CheckBox
    $box.Text = $labelText
    $box.Location = New-Object System.Drawing.Point(220, $top)
    $box.Size = New-Object System.Drawing.Size(312, 20)                             # fits the longest label, which is the aggressive one at 307 px

    $box.Checked = $checked
    $box.FlatStyle = "Flat"
    $box.ForeColor = $themeText
    $page.Controls.Add($box)
    $inputs[$key] = $box
    return ($top + 26)
}

function Get-ServerSummary($server, $index)
{
    # What the list on the Servers tab shows for one server
    $accounts = @(Get-ServerAccounts $server)
    $main = "$($server.MainAccount)".Trim()
    $name = if ("$($server.Name)".Trim()) { "$($server.Name)" } else { "Server $($index + 1)" }
    $who = if ($main) { "main $main" } else { "no main" }
    return "$name  -  place $($server.PlaceId)  -  $($accounts.Count) account$(if ($accounts.Count -ne 1) { 's' }), $who"
}

function Show-ServerWindow($server, $index, $isFirst)
{
    # One server's own settings, in the same shape as the rest of the window. Returns the
    # edited copy, or $null if it was cancelled, so the caller can leave the list alone.
    $working = @{}
    foreach ($key in $server.Keys) { $working[$key] = $server[$key] }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Server settings"
    $form.Size = New-Object System.Drawing.Size(580, 680)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    Set-ThemedForm $form

    $inputs = @{}
    $top = 14
    $top = Add-FieldRow $form $inputs "Name for this server" "Name" $working.Name $top 20 $false
    $top = Add-FieldRow $form $inputs "Place ID" "PlaceId" $working.PlaceId $top 20 $false
    $top = Add-FieldRow $form $inputs "Private server link" "PrivateServerLink" $working.PrivateServerLink $top 20 $false

    $mainCaption = if ($isFirst) { "Main username" } else { "Main username (optional)" }
    $top = Add-FieldRow $form $inputs $mainCaption "MainAccount" $working.MainAccount $top 20 $false
    if (-not $isFirst)
    {
        $mainNote = New-Object System.Windows.Forms.Label
        $mainNote.Text = "Leave blank and every account here is treated as an alt."
        $mainNote.Location = New-Object System.Drawing.Point(220, ($top - 6))
        $mainNote.Size = New-Object System.Drawing.Size(312, 30)                      # two lines of room: the text needs 304 px and 300 was not enough
        $mainNote.ForeColor = $themeMuted
        $form.Controls.Add($mainNote)
        $top += 22

    }

    $top = Add-FieldRow $form $inputs "Alt usernames (one per line)" "AltAccounts" $working.AltAccounts $top 90 $false
    $top = Add-FieldRow $form $inputs "Relog alts after minutes" "MaximumSessionMinutes" $working.MaximumSessionMinutes $top 20 $false
    $top = Add-FieldRow $form $inputs "Frame rate cap (0=off)" "FramerateCap" $working.FramerateCap $top 20 $false
    $top = Add-FieldRow $form $inputs "Kill an alt below free MB (0=off)" "MinimumFreeMegabytes" $working.MinimumFreeMegabytes $top 20 $false
    $top = Add-FieldRow $form $inputs "Anti-idle every min (0=off)" "AntiIdleMinutes" $working.AntiIdleMinutes $top 20 $false

    # the key field is narrowed to leave room for its picker
    $top = Add-FieldRow $form $inputs "Anti-idle key or spot" "AntiIdleKey" $working.AntiIdleKey $top 20 $false
    $antiIdleBox = $inputs["AntiIdleKey"]
    $antiIdleBox.Size = New-Object System.Drawing.Size(232, 20)
    $pickKeyButton = New-Object System.Windows.Forms.Button
    $pickKeyButton.Text = "Pick"
    $pickKeyButton.Location = New-Object System.Drawing.Point(458, ($antiIdleBox.Location.Y - 1))
    $pickKeyButton.Size = New-Object System.Drawing.Size(62, 23)
    Set-ThemedButton $pickKeyButton $false
    $pickKeyButton.Add_Click({
        $pickKeyButton.Enabled = $false
        $antiIdleBox.Focus() | Out-Null
        try
        {
            $robloxWindow = $null
            foreach ($candidate in (Get-Process $processName -ErrorAction SilentlyContinue | Sort-Object StartTime))
            {
                $candidate.Refresh()
                if ($candidate.MainWindowHandle -ne [IntPtr]::Zero) { $robloxWindow = $candidate; break }
            }
            $windowRect = if ($robloxWindow) { Get-WindowRectangle $robloxWindow.MainWindowHandle } else { $null }
            $clickPart = if ($windowRect) { ", or click a spot inside the Roblox window" }
                         else { ". Open a Roblox window first if you want to pick a spot to click instead" }
            [System.Windows.Forms.MessageBox]::Show(
                "Press the key you want to use$clickPart.`r`n`r`nHold ctrl, alt or shift with it for a " +
                "combination. Escape cancels.",
                "Pick a key or a spot", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            $null = Wait-NoKeyDown 3
            $picked = Get-PickedAntiIdleInput $windowRect 30
            if ($picked -eq "outside")
            {
                [System.Windows.Forms.MessageBox]::Show("That click was outside the Roblox window.",
                    "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
            elseif ($picked) { $antiIdleBox.Text = $picked }
            $null = Wait-NoKeyDown 3
        }
        finally { $pickKeyButton.Enabled = $true }
    })
    $form.Controls.Add($pickKeyButton)

    $top = Add-CheckRow $form $inputs "Aggressive anti-idle: walk and jump, ignores the key" "AggressiveAntiIdle" ("$($working.AggressiveAntiIdle)" -eq "True") $top

    # the step list, with the spot picker it already had
    $top += 4
    $stepsLabel = New-Object System.Windows.Forms.Label
    $stepsLabel.Text = "Steps to run on main"
    $stepsLabel.Location = New-Object System.Drawing.Point(4, ($top + 3))
    $stepsLabel.Size = New-Object System.Drawing.Size(210, 20)
    $stepsLabel.ForeColor = $themeText
    $form.Controls.Add($stepsLabel)

    $stepsHint = New-Object System.Windows.Forms.Label
    $stepsHint.Text = "key 2   hold w 4200" + [char]0x2003 + "scroll -6" + [char]0x2003 + "click 0.5,0.6   wait 7000"
    $stepsHint.Location = New-Object System.Drawing.Point(4, ($top + 24))
    $stepsHint.Size = New-Object System.Drawing.Size(210, 46)
    $stepsHint.ForeColor = $themeMuted
    $form.Controls.Add($stepsHint)

    $stepsBox = New-Object System.Windows.Forms.TextBox
    $stepsBox.Location = New-Object System.Drawing.Point(220, $top)
    $stepsBox.Size = New-Object System.Drawing.Size(232, 90)
    $stepsBox.Multiline = $true
    $stepsBox.AcceptsReturn = $true
    $stepsBox.ScrollBars = "Vertical"
    $stepsBox.Text = "$($working.StepList)"
    $stepsBox.BackColor = $themeSurface
    $stepsBox.ForeColor = $themeText
    $stepsBox.BorderStyle = "FixedSingle"
    $form.Controls.Add($stepsBox)
    $inputs["StepList"] = $stepsBox

    $pickSpotButton = New-Object System.Windows.Forms.Button
    $pickSpotButton.Text = "Pick"
    $pickSpotButton.Location = New-Object System.Drawing.Point(458, ($top - 1))
    $pickSpotButton.Size = New-Object System.Drawing.Size(62, 23)
    Set-ThemedButton $pickSpotButton $false
    $pickSpotButton.Add_Click({
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
        $null = Wait-NoKeyDown 3
        $picked = Get-PickedAntiIdleInput $windowRect 30
        if ($picked -eq "outside")
        {
            [System.Windows.Forms.MessageBox]::Show("That click was outside the Roblox window.",
                "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if (-not $picked -or $picked -notlike "click *") { return }                     # a key is no use as a step spot
        if ($stepsBox.Text -and -not $stepsBox.Text.EndsWith("`n")) { $stepsBox.AppendText("`r`n") }
        $stepsBox.AppendText($picked)
    })
    $form.Controls.Add($pickSpotButton)
    $top += 100

    $top = Add-CheckRow $form $inputs "Run the steps by itself when main rejoins" "RunStepsOnRejoin" ("$($working.RunStepsOnRejoin)" -eq "True") $top

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(350, ($top + 10))
    $okButton.Size = New-Object System.Drawing.Size(80, 28)
    $okButton.DialogResult = "OK"
    Set-ThemedButton $okButton $true
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(440, ($top + 10))
    $cancelButton.Size = New-Object System.Drawing.Size(80, 28)
    $cancelButton.DialogResult = "Cancel"
    Set-ThemedButton $cancelButton $false
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne "OK") { $form.Dispose(); return $null }

    foreach ($key in $inputs.Keys)
    {
        $control = $inputs[$key]
        if ($control -is [System.Windows.Forms.CheckBox]) { $working[$key] = [string]$control.Checked }
        else { $working[$key] = $control.Text.Trim() }
    }
    if (-not $working.Name) { $working.Name = "Server $($index + 1)" }
    $form.Dispose()
    return $working
}

function Show-SettingsWindow($saved)
{
    # Five pages instead of one long column. The old window had sixteen text rows, six
    # tickboxes and the step list stacked down a single page, which ran past the bottom
    # of a 800 pixel form and had no room left for a second server.
    $servers = New-Object System.Collections.Generic.List[object]
    foreach ($server in @($saved.Servers)) { $servers.Add((ConvertTo-ServerRecord ([pscustomobject]$server))) }
    if (-not $servers.Count) { $servers.Add((Get-DefaultServer)) }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Roblox Watchdog"
    $form.Size = New-Object System.Drawing.Size(580, 520)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    Set-ThemedForm $form

    $pages = Add-TabbedPages $form @("Servers", "Account Manager", "Windows", "Alerts", "Housekeeping") 10 10 546 410

    $inputs = @{}

    # ---- Servers ---------------------------------------------------------------
    $serversPage = $pages["Servers"]

    $serverList = New-Object System.Windows.Forms.ListBox
    $serverList.Location = New-Object System.Drawing.Point(4, 8)
    $serverList.Size = New-Object System.Drawing.Size(516, 290)
    $serverList.BackColor = $themeSurface
    $serverList.ForeColor = $themeText
    $serverList.BorderStyle = "FixedSingle"
    $serverList.ItemHeight = 20

    # Drawn by hand, because a ListBox paints its selected row in the Windows highlight
    # colour and there is no property for it: against this background it came out as a
    # band of bright blue. Unlike a TabControl, the whole item rectangle really is ours,
    # so this works.
    $serverList.DrawMode = "OwnerDrawFixed"
    $serverList.Add_DrawItem({
        param($drawn, $event)
        if ($event.Index -lt 0) { return }
        $isSelected = (($event.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)

        $faceBrush = New-Object System.Drawing.SolidBrush($(if ($isSelected) { $themeRaised } else { $themeSurface }))
        $event.Graphics.FillRectangle($faceBrush, $event.Bounds)
        $faceBrush.Dispose()

        if ($isSelected)
        {
            # a bar down the left rather than a filled highlight, so the row stays readable
            $barBrush = New-Object System.Drawing.SolidBrush($themeAccent)
            $event.Graphics.FillRectangle($barBrush, $event.Bounds.Left, $event.Bounds.Top, 3, $event.Bounds.Height)
            $barBrush.Dispose()
        }

        $textBrush = New-Object System.Drawing.SolidBrush($(if ($isSelected) { $themeText } else { $themeMuted }))
        $event.Graphics.DrawString($drawn.Items[$event.Index], $drawn.Font, $textBrush,
                                   ($event.Bounds.Left + 9), ($event.Bounds.Top + 2))
        $textBrush.Dispose()
    })
    $serversPage.Controls.Add($serverList)

    $refreshServers = {
        $keep = $serverList.SelectedIndex
        $serverList.Items.Clear()
        for ($i = 0; $i -lt $servers.Count; $i++) { $null = $serverList.Items.Add((Get-ServerSummary $servers[$i] $i)) }
        if ($keep -ge 0 -and $keep -lt $serverList.Items.Count) { $serverList.SelectedIndex = $keep }
        elseif ($serverList.Items.Count) { $serverList.SelectedIndex = 0 }
    }
    & $refreshServers

    $addServerButton = New-Object System.Windows.Forms.Button
    $addServerButton.Text = "Add server"
    $addServerButton.Location = New-Object System.Drawing.Point(4, 306)
    $addServerButton.Size = New-Object System.Drawing.Size(110, 27)
    Set-ThemedButton $addServerButton $false
    $serversPage.Controls.Add($addServerButton)

    $editServerButton = New-Object System.Windows.Forms.Button
    $editServerButton.Text = "Edit"
    $editServerButton.Location = New-Object System.Drawing.Point(120, 306)
    $editServerButton.Size = New-Object System.Drawing.Size(90, 27)
    Set-ThemedButton $editServerButton $false
    $serversPage.Controls.Add($editServerButton)

    $removeServerButton = New-Object System.Windows.Forms.Button
    $removeServerButton.Text = "Remove"
    $removeServerButton.Location = New-Object System.Drawing.Point(216, 306)
    $removeServerButton.Size = New-Object System.Drawing.Size(90, 27)
    Set-ThemedButton $removeServerButton $false
    $serversPage.Controls.Add($removeServerButton)

    $serversNote = New-Object System.Windows.Forms.Label
    $serversNote.Text = "Each server has its own link, accounts, step list, relog timer, anti-idle and limits."
    $serversNote.Location = New-Object System.Drawing.Point(4, 340)
    $serversNote.Size = New-Object System.Drawing.Size(516, 32)
    $serversNote.ForeColor = $themeMuted
    $serversPage.Controls.Add($serversNote)

    $addServerButton.Add_Click({
        $fresh = Get-DefaultServer
        $fresh.Name = "Server $($servers.Count + 1)"
        # a new server starts from the first one's limits, since those are usually the
        # same machine and the same taste, and only the link and accounts really differ
        if ($servers.Count)
        {
            foreach ($key in "MaximumSessionMinutes", "AntiIdleMinutes", "AntiIdleKey", "AggressiveAntiIdle", "FramerateCap")
            {
                $fresh[$key] = $servers[0][$key]
            }
            $fresh.PlaceId = $servers[0].PlaceId
        }
        $edited = Show-ServerWindow $fresh $servers.Count $false
        if ($edited) { $servers.Add($edited); & $refreshServers; $serverList.SelectedIndex = $servers.Count - 1 }
    })

    $editServerButton.Add_Click({
        $index = $serverList.SelectedIndex
        if ($index -lt 0 -or $index -ge $servers.Count) { return }
        $edited = Show-ServerWindow $servers[$index] $index ($index -eq 0)
        if ($edited) { $servers[$index] = $edited; & $refreshServers }
    })

    $serverList.Add_DoubleClick({ $editServerButton.PerformClick() })

    $removeServerButton.Add_Click({
        $index = $serverList.SelectedIndex
        if ($index -lt 0 -or $index -ge $servers.Count) { return }
        if ($servers.Count -le 1)
        {
            [System.Windows.Forms.MessageBox]::Show("There has to be at least one server.",
                "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $servers.RemoveAt($index)
        & $refreshServers
    })

    # ---- Account Manager -------------------------------------------------------
    $ramPage = $pages["Account Manager"]
    $top = 14
    $top = Add-FieldRow $ramPage $inputs "RAM web server port" "AccountManagerPort" $saved.AccountManagerPort $top 20 $false
    $top = Add-FieldRow $ramPage $inputs "RAM web server password" "AccountManagerPassword" $saved.AccountManagerPassword $top 20 $true
    $top = Add-FieldRow $ramPage $inputs "Seconds between launches" "RelaunchDelaySeconds" $saved.RelaunchDelaySeconds $top 20 $false

    $ramNote = New-Object System.Windows.Forms.Label
    $ramNote.Text = ("In Account Manager: Settings > Developer, turn on Enable Web Server and Allow " +
                     "LaunchAccount Method, and set the Webserver Password there. That password, not an " +
                     "account password.")
    $ramNote.Location = New-Object System.Drawing.Point(4, ($top + 10))
    $ramNote.Size = New-Object System.Drawing.Size(516, 60)
    $ramNote.ForeColor = $themeMuted
    $ramPage.Controls.Add($ramNote)

    # ---- Windows ---------------------------------------------------------------
    $windowsPage = $pages["Windows"]
    $top = 14
    $top = Add-CheckRow $windowsPage $inputs "Close other Roblox windows on start" "CloseOtherClients" ($saved["CloseOtherClients"] -ne "False") $top
    $top = Add-CheckRow $windowsPage $inputs "Adopt the windows already open, launch nothing" "AdoptOpenClients" ($saved["AdoptOpenClients"] -eq "True") $top
    $top = Add-CheckRow $windowsPage $inputs "Spread the windows over all monitors" "UseAllMonitors" ($saved["UseAllMonitors"] -ne "False") $top
    $top = Add-CheckRow $windowsPage $inputs "Put windows back where I dragged them" "RememberWindowPositions" ($saved["RememberWindowPositions"] -ne "False") $top

    $closeBox = $inputs["CloseOtherClients"]
    $adoptBox = $inputs["AdoptOpenClients"]
    $closeBox.Add_CheckedChanged({ if ($closeBox.Checked) { $adoptBox.Checked = $false } })
    $adoptBox.Add_CheckedChanged({ if ($adoptBox.Checked) { $closeBox.Checked = $false } })
    if ($closeBox.Checked -and $adoptBox.Checked) { $closeBox.Checked = $false }

    $windowsNote = New-Object System.Windows.Forms.Label
    $windowsNote.Text = ("Closing the open windows and adopting them are opposites, so only one of those " +
                         "two can be on. Save layout and Load layout are in the watchdog window itself.")
    $windowsNote.Location = New-Object System.Drawing.Point(4, ($top + 10))
    $windowsNote.Size = New-Object System.Drawing.Size(516, 48)
    $windowsNote.ForeColor = $themeMuted
    $windowsPage.Controls.Add($windowsNote)

    # ---- Alerts ----------------------------------------------------------------
    $alertsPage = $pages["Alerts"]
    $top = 14
    $top = Add-FieldRow $alertsPage $inputs "Discord webhook (optional)" "DiscordWebhookUrl" $saved.DiscordWebhookUrl $top 20 $false
    $webhookBox = $inputs["DiscordWebhookUrl"]
    $webhookBox.Size = New-Object System.Drawing.Size(232, 20)

    $testButton = New-Object System.Windows.Forms.Button
    $testButton.Text = "Test"
    $testButton.Location = New-Object System.Drawing.Point(458, ($webhookBox.Location.Y - 1))
    $testButton.Size = New-Object System.Drawing.Size(62, 23)
    Set-ThemedButton $testButton $false
    $testButton.Add_Click({
        $url = $webhookBox.Text.Trim()
        if (-not $url)
        {
            [System.Windows.Forms.MessageBox]::Show("Paste a webhook url first.", "Roblox Watchdog",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        try
        {
            $payload = @{ content = "Roblox Watchdog test: this webhook works." } | ConvertTo-Json -Compress
            $content = New-Object System.Net.Http.StringContent($payload, [System.Text.Encoding]::UTF8, "application/json")
            $response = $httpClient.PostAsync($url, $content).Result
            if ($response.IsSuccessStatusCode)
            {
                [System.Windows.Forms.MessageBox]::Show("Sent. Check the channel.", "Roblox Watchdog",
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            else
            {
                [System.Windows.Forms.MessageBox]::Show("Discord said $([int]$response.StatusCode) '$($response.ReasonPhrase)'.",
                    "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            }
        }
        catch
        {
            [System.Windows.Forms.MessageBox]::Show("That did not work: $($_.Exception.GetBaseException().Message)",
                "Roblox Watchdog", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    })
    $alertsPage.Controls.Add($testButton)

    $top = Add-FieldRow $alertsPage $inputs "Discord id to ping for main" "DiscordPingId" $saved.DiscordPingId $top 20 $false
    $top = Add-FieldRow $alertsPage $inputs "Discord alerts every min (0=off)" "DiscordSummaryMinutes" $saved.DiscordSummaryMinutes $top 20 $false

    $alertsNote = New-Object System.Windows.Forms.Label
    $alertsNote.Text = ("Only things worth looking at are sent: a crash and whether it is coming back, an " +
                        "account that will not start, no memory left, missing permissions, a main relogging, " +
                        "and several accounts dropping at once. Starting it yourself sends nothing.")
    $alertsNote.Location = New-Object System.Drawing.Point(4, ($top + 10))
    $alertsNote.Size = New-Object System.Drawing.Size(516, 64)
    $alertsNote.ForeColor = $themeMuted
    $alertsPage.Controls.Add($alertsNote)

    # ---- Housekeeping ----------------------------------------------------------
    $housePage = $pages["Housekeeping"]
    $top = 14
    $top = Add-FieldRow $housePage $inputs "Close strays after min (0=off)" "ReapStrayMinutes" $saved.ReapStrayMinutes $top 20 $false

    $houseNote = New-Object System.Windows.Forms.Label
    $houseNote.Text = ("Roblox leaves helper processes behind when a client closes. They have no window, " +
                       "sit on about 175 MB each and never exit, so they are closed once they are older " +
                       "than this. A client that does have a window is never touched.")
    $houseNote.Location = New-Object System.Drawing.Point(4, ($top + 10))
    $houseNote.Size = New-Object System.Drawing.Size(516, 64)
    $houseNote.ForeColor = $themeMuted
    $housePage.Controls.Add($houseNote)

    # ---- Start and cancel, outside the pages -----------------------------------
    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "Start"
    $startButton.Location = New-Object System.Drawing.Point(456, 432)
    $startButton.Size = New-Object System.Drawing.Size(100, 30)
    $startButton.DialogResult = "OK"
    Set-ThemedButton $startButton $true
    $form.Controls.Add($startButton)
    $form.AcceptButton = $startButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(348, 432)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 30)
    $cancelButton.DialogResult = "Cancel"
    Set-ThemedButton $cancelButton $false
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -ne "OK")
    {
        $form.Dispose()
        return $null
    }

    $result = @{}
    foreach ($key in $inputs.Keys)
    {
        $control = $inputs[$key]
        if ($control -is [System.Windows.Forms.CheckBox]) { $result[$key] = [string]$control.Checked }
        else { $result[$key] = $control.Text.Trim() }
    }
    # ToArray, not @(): in PowerShell 5.1 @() leaves a List as a List, and assigning one
    # into a hashtable index throws "Argument types do not match". This crashed the
    # settings window on Start.
    $result["Servers"] = $servers.ToArray()

    $form.Dispose()
    return $result
}

function Test-ServerSettings($server, $label, $mainRequired)
{
    # One server's own settings. The first server has to have a main, because it is the
    # one whose oldest window is adopted on startup and the one the step list belongs to
    # by default. The extras do not: a server can be nothing but alts.
    if ($mainRequired -and -not "$($server.MainAccount)".Trim())
    {
        throw "$label : a main username is required on the first server"
    }
    $accounts = @(Get-ServerAccounts $server)
    if (-not $accounts.Count) { throw "$label : it has no accounts at all" }

    $alts = @("$($server.AltAccounts)" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ("$($server.MainAccount)".Trim() -and $alts -contains "$($server.MainAccount)".Trim())
    {
        throw "$label : $($server.MainAccount) is both the main and an alt"
    }
    $duplicateAlt = @($alts | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -First 1)
    if ($duplicateAlt.Count) { throw "$label : $($duplicateAlt[0].Name) is listed twice" }

    if ("$($server.PlaceId)" -notmatch '^\d{1,19}$') { throw "$label : place ID must be a number" }

    if ($server.PrivateServerLink)
    {
        $shareLink = $server.PrivateServerLink -match '^https://(www\.)?roblox\.com/share\?.*\bcode=[A-Za-z0-9_-]+' -and
                     $server.PrivateServerLink -match 'type=Server'
        $classicLink = $server.PrivateServerLink -match '^https://(www\.)?roblox\.com/games/\d+.*[?&]privateServerLinkCode=[A-Za-z0-9_-]+'
        if (-not ($shareLink -or $classicLink))
        {
            throw ("$label : that does not look like a private server link. Paste the whole link from Roblox, " +
                   "either a share link with type=Server or a game link with privateServerLinkCode")
        }
    }

    # 0 turns it off: on a machine that sits at full memory, closing an alt is worse than
    # leaving it running
    if ("$($server.MinimumFreeMegabytes)" -notmatch '^\d{1,6}$') { throw "$label : free MB must be a number (0 to turn it off)" }
    $freeMegabytes = [int]$server.MinimumFreeMegabytes
    if ($freeMegabytes -ne 0 -and $freeMegabytes -lt 200) { throw "$label : free MB must be 0, or at least 200" }

    if ("$($server.MaximumSessionMinutes)" -notmatch '^\d{1,5}$') { throw "$label : relog alts after minutes must be a number" }
    if ([int]$server.MaximumSessionMinutes -lt 5) { throw "$label : relog alts after minutes must be at least 5" }

    # 0 leaves Roblox's own setting alone; otherwise keep it in a sane range
    if ("$($server.FramerateCap)" -notmatch '^\d{1,3}$') { throw "$label : frame rate cap must be a number (0 to leave it alone)" }
    $cap = [int]$server.FramerateCap
    if ($cap -ne 0 -and ($cap -lt 15 -or $cap -gt 360)) { throw "$label : frame rate cap must be 0, or between 15 and 360" }

    # Roblox kicks at 20 minutes idle, so the interval has to leave room to get there
    if ("$($server.AntiIdleMinutes)" -notmatch '^\d{1,2}$') { throw "$label : anti-idle minutes must be a number (0 to turn it off)" }
    $idle = [int]$server.AntiIdleMinutes
    if ($idle -ne 0 -and ($idle -lt 1 -or $idle -gt 18))
    {
        throw "$label : anti-idle minutes must be 0, or between 1 and 18 (Roblox kicks at 20)"
    }
    if ($idle -gt 0)
    {
        try { $null = Get-AntiIdleAction $server.AntiIdleKey }
        catch { throw "$label : anti-idle - $($_.Exception.Message -replace '^line 0 : ', '')" }
    }

    if ($server.StepList)
    {
        try { Get-StepList $server.StepList | Out-Null }
        catch { throw "$label : step list - $($_.Exception.Message)" }
    }
}

function Test-Settings($settings)
{
    # The settings that belong to the machine rather than to any one server
    if ($settings.AccountManagerPort -notmatch '^\d{1,5}$') { throw "RAM web server port must be a number" }
    $port = [int]$settings.AccountManagerPort
    if ($port -lt 1 -or $port -gt 65535) { throw "RAM web server port must be between 1 and 65535" }

    # RAM refuses LaunchAccount without one, so an empty password means nothing launches
    if (-not $settings.AccountManagerPassword) { throw "RAM web server password is required" }
    if ($settings.AccountManagerPassword.Length -lt 6) { throw "RAM web server password must be at least 6 characters" }

    if ($settings.RelaunchDelaySeconds -notmatch '^\d{1,4}$') { throw "Seconds between launches must be a number" }
    if ([int]$settings.RelaunchDelaySeconds -lt 5) { throw "Seconds between launches must be at least 5" }

    # Grace period before an untracked windowless client counts as a stray. Must be
    # longer than a launch takes, or a client still starting up would be killed
    if ($settings.ReapStrayMinutes -notmatch '^\d{1,3}$') { throw "Close strays after minutes must be a number (0 to turn it off)" }
    $reap = [int]$settings.ReapStrayMinutes
    if ($reap -ne 0 -and $reap -lt 2) { throw "Close strays after minutes must be 0, or at least 2" }

    if ($settings.DiscordSummaryMinutes -notmatch '^\d{1,4}$') { throw "Discord alerts every minutes must be a number (0 to turn it off)" }
    $summary = [int]$settings.DiscordSummaryMinutes
    if ($summary -ne 0 -and ($summary -lt 5 -or $summary -gt 1440)) { throw "Discord alerts every minutes must be 0, or between 5 and 1440" }

    # And every server in turn
    $serverList = @($settings.Servers)
    if (-not $serverList.Count) { throw "There are no servers. Add one on the Servers tab." }

    $seen = @{}
    for ($index = 0; $index -lt $serverList.Count; $index++)
    {
        $server = $serverList[$index]
        $label = if ("$($server.Name)".Trim()) { "$($server.Name)" } else { "Server $($index + 1)" }
        Test-ServerSettings $server $label ($index -eq 0)

        # The same account on two servers would have two sessions fighting over one
        # client, so it is caught here rather than quietly dropped at launch
        foreach ($accountName in (Get-ServerAccounts $server))
        {
            if ($seen.ContainsKey($accountName))
            {
                throw "$accountName is on both $($seen[$accountName]) and $label. An account can only farm one server."
            }
            $seen[$accountName] = $label
        }
    }
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

# The servers are the real list now. $mainAccount and $altAccounts stay as the first
# server's, because the step list and a few log lines still read them, and because a
# one server setup is what almost everyone has.
$servers = @($settings.Servers)
$mainAccount = $servers[0].MainAccount
$altAccounts = @(Get-ServerAccounts $servers[0] | Where-Object { $_ -ne $mainAccount })
$accountManagerPort = [int]$settings.AccountManagerPort
$accountManagerPassword = $settings.AccountManagerPassword
$relaunchDelaySeconds = [int]$settings.RelaunchDelaySeconds
$closeOtherClients = ($settings.CloseOtherClients -ne "False")
$adoptOpenClients = ($settings.AdoptOpenClients -eq "True")

# The first server's, kept only as the answer when something asks before it knows which
# server it is dealing with. Everything that runs per account reads the account's own
# server instead.
$placeId = $servers[0].PlaceId
$privateServerLink = $servers[0].PrivateServerLink                                    # full link, RAM resolves it; empty = public
$minimumFreeMegabytes = [int]$servers[0].MinimumFreeMegabytes
$maximumSessionMinutes = [int]$servers[0].MaximumSessionMinutes
$framerateCap = [int]$servers[0].FramerateCap
$antiIdleMinutes = [int]$servers[0].AntiIdleMinutes
$antiIdleKey = $servers[0].AntiIdleKey
$aggressiveAntiIdle = ("$($servers[0].AggressiveAntiIdle)" -eq "True")
$antiIdleAction = try { Get-AntiIdleAction $antiIdleKey } catch { $null }
$reapStrayMinutes = [int]$settings.ReapStrayMinutes
$useAllMonitors = ($settings.UseAllMonitors -ne "False")
$discordWebhookUrl = $settings.DiscordWebhookUrl
$discordPingId = $settings.DiscordPingId
$discordSummaryMinutes = [int]$settings.DiscordSummaryMinutes
$rememberWindowPositions = ($settings.RememberWindowPositions -ne "False")
$stepListText = $servers[0].StepList
$runStepsOnRejoin = ("$($servers[0].RunStepsOnRejoin)" -eq "True")
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

function Set-RobloxFramerateCap($cap)
{
    # Roblox reads this once at client startup and rewrites the file when a client
    # exits, so a closing client resets it to unlimited; reassert it before launching.
    #
    # Being read at startup is also what lets one server cap differently from another:
    # the value is written immediately before that server's account is launched, and the
    # client that starts keeps it.
    $framerateCap = if ($null -eq $cap) { 0 } else { [int]$cap }
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

function Read-WindowLayoutFile
{
    # Whatever is on disk, regardless of the setting. Saving and loading a layout by hand
    # has to work even with automatic remembering turned off, which is the whole point of
    # the buttons.
    $positions = @{}
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

function Get-SavedWindowPositions
{
    # What a launch should put the window back to: nothing, unless remembering is on
    if (-not $rememberWindowPositions) { return @{} }
    return Read-WindowLayoutFile
}

function Get-ClientWindowRectangle($session)
{
    # The window as it actually is now, or $null if there is nothing to read
    $process = Get-SessionProcess $session
    if (-not $process) { return $null }
    $process.Refresh()
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { return $null }
    $rectangle = Get-WindowRectangle $process.MainWindowHandle
    if (-not $rectangle) { return $null }
    return "$($rectangle.X),$($rectangle.Y),$($rectangle.Width),$($rectangle.Height)"
}

function Save-WindowLayout
{
    # Every window where it stands, size included, written in one go. Asked for by hand,
    # so it does not care whether automatic remembering is on and it does not care
    # whether the watchdog put the window there or someone dragged it.
    $positions = Read-WindowLayoutFile
    $saved = 0
    foreach ($accountName in $allAccounts)
    {
        $rectangleText = Get-ClientWindowRectangle $sessions[$accountName]
        if (-not $rectangleText) { continue }
        $positions[$accountName] = $rectangleText
        $sessions[$accountName].AppliedRect = $rectangleText                          # so a later drag is measured from here
        $saved++
    }
    if (-not $saved)
    {
        Write-Log "nothing to save: none of the accounts has a window open"
        return 0
    }
    try
    {
        $positions | ConvertTo-Json | Set-Content $positionsPath -Encoding UTF8
        Write-Log "saved where $saved window$(if ($saved -ne 1) { 's' }) and how big they are"
    }
    catch
    {
        Write-Log "WARNING: could not save the window layout: $($_.Exception.Message)"
        return 0
    }
    return $saved
}

function Restore-WindowLayout
{
    # Put them back where they were saved, now, rather than waiting for a relaunch
    $positions = Read-WindowLayoutFile
    if (-not $positions.Count)
    {
        Write-Log "no saved window layout to load yet, press Save layout first"
        return 0
    }
    $moved = 0
    foreach ($accountName in $allAccounts)
    {
        if (-not $positions.ContainsKey($accountName)) { continue }
        if ($sessions[$accountName].ProcessId -eq 0) { continue }
        if (Set-ClientWindow $accountName $sessions[$accountName].ProcessId $positions) { $moved++ }
    }
    Write-Log "loaded the saved layout into $moved window$(if ($moved -ne 1) { 's' })"
    return $moved
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

function Set-ClientWindow($accountName, $processId, $layout)
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

    # Handed in by Load layout, which ignores the setting; otherwise whatever a launch
    # should use, which does not
    $savedPositions = if ($layout) { $layout } else { Get-SavedWindowPositions }
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
        # Where it really ended up, not what was asked for. Roblox settles its window a
        # little after being moved, and storing the request meant the window could sit
        # tens of pixels from what was recorded, which a drag then had to beat before it
        # counted at all.
        $sessions[$accountName].AppliedRect = "$($rect.Left),$($rect.Top)," +
                                              "$($rect.Right - $rect.Left),$($rect.Bottom - $rect.Top)"
        $where = if ($fromMemory) { "where you left it" } else
        {
            "slot $slotIndex" + $(if ($slot.ScreenCount -gt 1) { " on screen $($slot.ScreenNumber)" } else { "" })
        }
        Write-Log "moved $accountName (PID $processId) to $where ($x,$y $($tileWidth)x$($tileHeight))"
        return $true
    }

    # Taking note of where it actually is, even though moving it failed. Without this,
    # AppliedRect stayed empty and the whole "put it back where I dragged it" feature
    # quietly did nothing for anyone whose clients are elevated: the drag check needs
    # something to compare against, and a denied move left it with nothing. That is the
    # likeliest reason it was reported as not working at all.
    if ($readBack)
    {
        $sessions[$accountName].AppliedRect = "$($rect.Left),$($rect.Top)," +
                                              "$($rect.Right - $rect.Left),$($rect.Bottom - $rect.Top)"
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

function Start-StepRun($accountName, $reason)
{
    if ($script:stepRun.Active) { return }
    if (-not $accountName -or -not $sessions.ContainsKey($accountName)) { return }

    $stepText = (Get-SessionServer $sessions[$accountName]).StepList
    if (-not $stepText) { return }

    try
    {
        $steps = Get-StepList $stepText
    }
    catch
    {
        Write-Log "ERROR: the step list has a problem, $($_.Exception.Message)"
        return
    }
    if ($steps.Count -eq 0) { return }

    $session = $sessions[$accountName]
    if ($session.State -ne "Running" -or -not $session.JoinedAt)
    {
        Write-Log "not running the steps: $accountName is not in the game"
        return
    }

    $script:stepRun = @{ Active = $true; Steps = $steps; Index = 0; NextAt = (Get-Date); Reason = $reason
                         HeldKey = $null; Account = $accountName }
    Write-Log "running $($steps.Count) steps on $accountName ($reason)"
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

    $stepAccount = $script:stepRun.Account
    if (-not $stepAccount -or -not $sessions.ContainsKey($stepAccount))
    {
        Stop-StepRun "the account it was running on is gone"
        return
    }
    $session = $sessions[$stepAccount]
    if ($session.State -ne "Running" -or -not $session.JoinedAt)
    {
        Stop-StepRun "$stepAccount left the game"
        return
    }

    if ($script:stepRun.Index -ge $script:stepRun.Steps.Count)
    {
        Write-Log "step run finished on $stepAccount"
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
    if (-not $process) { Stop-StepRun "$stepAccount is gone"; return }
    $process.Refresh()
    $handle = $process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) { Stop-StepRun "$stepAccount has no window"; return }

    if (-not (Set-WindowFocused $handle))
    {
        Stop-StepRun "could not focus $stepAccount"
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

function Get-ServerAntiIdleAction($server)
{
    # Parsed once per server and kept on the server record, because this runs on a timer
    # and reparsing the same string every few minutes is work for nothing. A server
    # whose field cannot be read falls back to Space rather than skipping the poke.
    if (-not $server) { return $antiIdleAction }
    if (-not $server.ContainsKey("ParsedAntiIdle") -or $server["ParsedAntiIdleFrom"] -ne "$($server.AntiIdleKey)")
    {
        $server["ParsedAntiIdleFrom"] = "$($server.AntiIdleKey)"
        $server["ParsedAntiIdle"] = try { Get-AntiIdleAction $server.AntiIdleKey } catch { $null }
    }
    return $server["ParsedAntiIdle"]
}

function Test-ServerAggressive($server)
{
    if (-not $server) { return $aggressiveAntiIdle }
    return ("$($server.AggressiveAntiIdle)" -eq "True")
}

function Get-AntiIdleInterval($server)
{
    # Aggressive mode goes twice as often, with a floor of one minute. Roblox pulls the
    # plug at 20, so the normal setting is already capped at 18 in the settings window.
    $minutes = if ($server) { [int]$server.AntiIdleMinutes } else { $antiIdleMinutes }
    $aggressive = if ($server) { "$($server.AggressiveAntiIdle)" -eq "True" } else { $aggressiveAntiIdle }
    if (-not $aggressive) { return $minutes }
    return [math]::Max(1, [int][math]::Floor($minutes / 2))                             # floor, so 15 becomes 7 rather than 8

}

function Send-AntiIdleKey($code, $modifiers)
{
    # Modifiers go down first and come up last, in reverse, so the game sees one
    # shortcut instead of a handful of unrelated presses
    $held = @($modifiers | Where-Object { $_ })
    foreach ($modifier in $held)
    {
        $modifierScan = [byte]([Win32.Window]::MapVirtualKey($modifier, 0))
        [Win32.Window]::keybd_event($modifier, $modifierScan, 0, [UIntPtr]::Zero)
    }
    if ($held.Count) { Start-Sleep -Milliseconds 30 }

    $scanCode = [byte]([Win32.Window]::MapVirtualKey($code, 0))                       # games want a real scan code
    [Win32.Window]::keybd_event($code, $scanCode, 0, [UIntPtr]::Zero)                 # key down
    Start-Sleep -Milliseconds 80
    [Win32.Window]::keybd_event($code, $scanCode, 2, [UIntPtr]::Zero)                 # KEYEVENTF_KEYUP

    for ($index = $held.Count - 1; $index -ge 0; $index--)
    {
        $modifierScan = [byte]([Win32.Window]::MapVirtualKey($held[$index], 0))
        [Win32.Window]::keybd_event($held[$index], $modifierScan, 2, [UIntPtr]::Zero)
    }
}

function Send-AntiIdleClick($handle, $action)
{
    # Fractions of the window rather than screen pixels, so the same spot works whichever
    # monitor the window is on and whatever size the tile is. Same as a step list click.
    $windowRect = Get-WindowRectangle $handle
    if (-not $windowRect) { return $false }
    $targetX = [int]($windowRect.X + ($windowRect.Width * $action.X))
    $targetY = [int]($windowRect.Y + ($windowRect.Height * $action.Y))
    [Win32.Window]::SetCursorPos($targetX, $targetY) | Out-Null
    Start-Sleep -Milliseconds 40
    [Win32.Window]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)                     # left down
    Start-Sleep -Milliseconds 50
    [Win32.Window]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)                     # left up
    return $true
}

function Send-AntiIdleAction($handle, $action)
{
    # Whatever this account's server asked for. Falls back to Space only if the setting
    # could not be read at all, so a broken field still keeps the clients awake.
    if (-not $action)
    {
        Send-AntiIdleKey ([byte]0x20) @()
        return "pressed Space"
    }
    if ($action.Kind -eq "click")
    {
        if (Send-AntiIdleClick $handle $action) { return "clicked $($action.X),$($action.Y)" }
        return $null
    }
    Send-AntiIdleKey $action.Key $action.Modifiers
    return "pressed $($action.Label)"
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

    # This account's own server decides what to send and how hard to try
    $idleServer = Get-SessionServer $session
    $aggressiveHere = Test-ServerAggressive $idleServer
    $actionHere = Get-ServerAntiIdleAction $idleServer

    # Focus is refused often enough to matter: 1301 of 5867 attempts in one log, 22%,
    # and every refusal used to mean waiting another minute. Windows hands focus over
    # far more readily on the second or third ask, so ask again here instead.
    $attempts = if ($aggressiveHere) { 4 } else { 2 }
    $focused = $false
    for ($attempt = 1; $attempt -le $attempts -and -not $focused; $attempt++)
    {
        $focused = Set-WindowFocused $handle
        if (-not $focused -and $attempt -lt $attempts) { Start-Sleep -Milliseconds 150 }
    }

    if (-not $focused)
    {
        # Retry in a minute rather than fighting for focus on every tick
        $session.LastInputAt = (Get-Date).AddMinutes(1 - (Get-AntiIdleInterval $idleServer))

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

    if ($aggressiveHere)
    {
        # Aggressive ignores whatever the key or spot is set to and walks and jumps
        # instead. One tap of anything is enough for Roblox's own 20 minute timer, but a
        # game can watch for more than that, and a character that moves and jumps is the
        # harder thing to mistake for someone sitting still. W is held rather than tapped
        # because a tap can be swallowed between frames.
        $moveKey = [byte]0x57                                                          # W
        $moveScan = [byte]([Win32.Window]::MapVirtualKey($moveKey, 0))
        [Win32.Window]::keybd_event($moveKey, $moveScan, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 220
        [Win32.Window]::keybd_event($moveKey, $moveScan, 2, [UIntPtr]::Zero)

        $rectangle = Get-WindowRectangle $handle
        if ($rectangle)
        {
            # Inside the window, so the move cannot land on another client.
            #
            # This read .Left and .Right and .Top and .Bottom, which Get-WindowRectangle
            # does not have: it returns X, Y, Width and Height. Every one of them was
            # $null, so the centre worked out as 0,0 and the cursor was being parked in
            # the corner of the screen instead of in the window.
            $centreX = [int]($rectangle.X + ($rectangle.Width / 2))
            $centreY = [int]($rectangle.Y + ($rectangle.Height / 2))
            [Win32.Window]::SetCursorPos($centreX, $centreY) | Out-Null
            Start-Sleep -Milliseconds 40
            [Win32.Window]::SetCursorPos($centreX + 12, $centreY + 8) | Out-Null
        }

        # Space, not the setting. Pressed once: a second jump 60 milliseconds later lands
        # while the character is still in the air and does nothing at all.
        Send-AntiIdleKey ([byte]0x20) @()
        $did = "walked and jumped"
    }
    else
    {
        $did = Send-AntiIdleAction $handle $actionHere
        if (-not $did)
        {
            Write-Log "WARNING: could not read $accountName's window to click in, anti-idle skipped"
            return
        }
    }

    $session.LastInputAt = Get-Date
    $how = $did
    Write-Log ("anti-idle: $how in $accountName" +
               $(if ($attempt -gt 2) { " (focus took $($attempt - 1) tries)" } else { "" }))

    if ($previous -ne [IntPtr]::Zero -and $previous -ne $handle)
    {
        [Win32.Window]::SetForegroundWindow($previous) | Out-Null
    }
}

function Get-LaunchUrl($accountName)
{
    # The place and the link come from this account's own server, which is the whole of
    # what makes one server different from another as far as launching goes
    $server = Get-SessionServer $sessions[$accountName]
    $launchUrl = "http://localhost:$accountManagerPort/LaunchAccount" +
                 "?Account=$([uri]::EscapeDataString($accountName))" +
                 "&PlaceId=$($server.PlaceId)" +
                 "&Password=$([uri]::EscapeDataString($accountManagerPassword))"
    if ($server.PrivateServerLink)
    {
        $launchUrl += "&JobId=$([uri]::EscapeDataString($server.PrivateServerLink))"
    }
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
    Set-RobloxFramerateCap (Get-SessionServer $session).FramerateCap                   # a client that just closed may have reset it

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
        $session.ChallengeSeenAt = $null
        $session.ChallengeAlerted = $false
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
    # A client that was already running: its log is created a couple of seconds after the
    # process. Measured over six live clients the gap was 1.96 to 2.13 seconds and every
    # one matched a different log, so this is a sound way to tell them apart.
    #
    # Logs another session already holds are left out, or adopting several clients at once
    # would hand the same log to more than one of them and have them read each other's
    # disconnects.
    $takenPaths = @($sessions.Values | ForEach-Object { $_.LogPath } | Where-Object { $_ })
    $logFile = Get-PlayerLogFiles |
        Where-Object { $takenPaths -notcontains $_.FullName } |
        Sort-Object { [math]::Abs(($_.CreationTime - $process.StartTime).TotalSeconds) } |
        Select-Object -First 1
    if (-not $logFile -or [math]::Abs(($logFile.CreationTime - $process.StartTime).TotalSeconds) -gt 60)
    {
        throw "No unclaimed *_Player_*.log in $logFolder matches PID $($process.Id) started at $($process.StartTime)"
    }
    return $logFile.FullName
}

function Register-AdoptedClient($accountName, $process, $describedAs)
{
    # Taking over a client that was already playing, rather than closing it and starting
    # again. Used for main on every start, and for every open client when "adopt the
    # Roblox windows already open" is on.
    $session = $sessions[$accountName]
    $session.ProcessId = $process.Id
    $session.ProcessStartTime = $process.StartTime
    $session.StartedAt = $process.StartTime
    $session.LastInputAt = Get-Date                                                   # unknown when it last had input, so start the clock now
    $session.JoinedAt = Get-Date                                                      # it was already playing, so don't hold it to the join timeout
    $session.EverStarted = $true                                                      # it is already up, so a stop is a relaunch
    $session.StepsPending = $false                                                    # already set up by whoever was playing it
    Set-SessionState $session "Running"

    try
    {
        $session.LogPath = Find-StartupLogFile $process
        # Only what happens from now on: the log holds however long it has been running
        $session.LogOffset = (Get-Item $session.LogPath).Length
        Write-Log ("adopted PID $($process.Id) as $describedAs $accountName, " +
                   "log $(Split-Path -Leaf $session.LogPath)")
    }
    catch
    {
        # Without a log we cannot see it disconnect, but it is still tracked and tiled
        $session.LogPath = $null
        Write-Log ("WARNING: adopted PID $($process.Id) as $describedAs $accountName but found no matching log, " +
                   "so disconnects will not be seen for it until it relaunches")
    }
    Set-ClientWindow $accountName $process.Id | Out-Null
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
        if ($session.ChallengeSeenAt)
        {
            $waited = [int]((Get-Date) - $session.ChallengeSeenAt).TotalMinutes
            Write-Log "$($session.Account) passed Roblox's verification after $waited min and is in the game"
            $session.ChallengeSeenAt = $null
            $session.ChallengeAlerted = $false
        }
    }

    # Roblox answers the join with 403 and challengedByGcs when it wants a person to pass
    # its check before letting the account in, and the client then shows the press and
    # hold page. That looks exactly like being stuck on an error screen, so it used to be
    # killed after 150 seconds and launched again, which gave whoever owns the account two
    # and a half minutes to notice and no way to finish in time. On 05-10 one account was
    # cut off three times in seven minutes that way, and every retry is another challenged
    # join, which is what keeps Roblox asking.
    if (-not $session.JoinedAt -and $text -match $challengePattern -and -not $session.ChallengeSeenAt)
    {
        $session.ChallengeSeenAt = Get-Date
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
        if ($script:stepRun.Active -and $accountName -ne $script:stepRun.Account)
        {
            return "waiting for $($script:stepRun.Account)'s setup"
        }

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
        if ($session.ChallengeSeenAt) { return "verify it by hand" }
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

# Every account across every server, each one knowing which server it belongs to and
# whether it is that server's main. Main first within a server, so it is relaunched
# before any of its alts, and the servers in the order they were added.
#
# An account named twice is taken once, by the first server that claims it: the same
# account cannot be in two servers at the same time anyway, and launching it twice
# would have the two sessions fighting over one client.
$accountServer = @{}
$accountIsMain = @{}
$allAccounts = New-Object System.Collections.Generic.List[string]
for ($serverIndex = 0; $serverIndex -lt $servers.Count; $serverIndex++)
{
    $serverMain = "$($servers[$serverIndex].MainAccount)".Trim()
    foreach ($accountName in (Get-ServerAccounts $servers[$serverIndex]))
    {
        if ($accountServer.ContainsKey($accountName))
        {
            Write-Log ("WARNING: $accountName is listed on more than one server, so it stays with " +
                       "$($servers[$accountServer[$accountName]].Name)")
            continue
        }
        $accountServer[$accountName] = $serverIndex
        $accountIsMain[$accountName] = ($accountName -eq $serverMain)
        $allAccounts.Add($accountName)
    }
}
$allAccounts = $allAccounts.ToArray()

$sessions = @{}

function New-SessionRecord($accountName, $serverIndex, $isMain)
{
    return @{ ProcessId = 0; ProcessStartTime = $null; StartedAt = $null
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
                                 FocusRefusedCount = 0; ChallengeSeenAt = $null
              ChallengeAlerted = $false; Account = $accountName
              ServerIndex = $serverIndex; IsMain = $isMain }
}

foreach ($accountName in $allAccounts)
{
    $sessions[$accountName] = New-SessionRecord $accountName $accountServer[$accountName] $accountIsMain[$accountName]
}

function Sync-SessionsWithServers($newServers)
{
    # Takes a new list of servers and makes the running watchdog match it, without a
    # restart. Accounts that are already up keep their session, their window and their
    # history, and only learn which server they now belong to. New ones are added at the
    # end of the list so nobody else's window slot shifts, and queued to launch one at a
    # time like any other. An account that is no longer configured stops being watched
    # but is left running: closing somebody's client because they edited a text box is
    # not a thing to do without being asked.
    $script:servers = @($newServers)

    $wantedServer = @{}
    $wantedMain = @{}
    $wanted = New-Object System.Collections.Generic.List[string]
    for ($serverIndex = 0; $serverIndex -lt $script:servers.Count; $serverIndex++)
    {
        $serverMain = "$($script:servers[$serverIndex].MainAccount)".Trim()
        foreach ($accountName in (Get-ServerAccounts $script:servers[$serverIndex]))
        {
            if ($wantedServer.ContainsKey($accountName)) { continue }
            $wantedServer[$accountName] = $serverIndex
            $wantedMain[$accountName] = ($accountName -eq $serverMain)
            $wanted.Add($accountName)
        }
    }

    $dropped = @($script:allAccounts | Where-Object { -not $wantedServer.ContainsKey($_) })
    foreach ($accountName in $dropped)
    {
        $stillUp = $script:sessions[$accountName].ProcessId -ne 0
        $script:sessions.Remove($accountName)
        Write-Log ("$accountName is no longer on any server, so it is not watched any more" +
                   $(if ($stillUp) { ", and its window was left open" } else { "" }))
    }

    # Existing accounts first, in the order they already had, then anything new
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($accountName in $script:allAccounts)
    {
        if ($wantedServer.ContainsKey($accountName)) { $ordered.Add($accountName) }
    }
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($accountName in $wanted)
    {
        if ($ordered.Contains($accountName)) { continue }
        $ordered.Add($accountName)
        $added.Add($accountName)
    }
    $script:allAccounts = $ordered.ToArray()

    foreach ($accountName in $script:allAccounts)
    {
        if ($script:sessions.ContainsKey($accountName))
        {
            $script:sessions[$accountName].ServerIndex = $wantedServer[$accountName]
            $script:sessions[$accountName].IsMain = $wantedMain[$accountName]
        }
        else
        {
            $script:sessions[$accountName] = New-SessionRecord $accountName $wantedServer[$accountName] $wantedMain[$accountName]
        }
    }

    if ($added.Count)
    {
        # Spread out behind whatever is already waiting, so a new server does not launch
        # five clients at once on top of a farm that is already running
        Update-LaunchQueue $relaunchDelaySeconds
        Write-Log ("added $($added.Count) account$(if ($added.Count -ne 1) { 's' }): $($added -join ', ')")
    }
    return @{ Added = $added.ToArray(); Dropped = $dropped }
}

function Get-SessionServer($session)
{
    # The server a session belongs to. Falls back to the first one rather than returning
    # nothing, so a session created before its server existed still launches somewhere.
    $index = [int]$session.ServerIndex
    if ($index -lt 0 -or $index -ge $servers.Count) { $index = 0 }
    return $servers[$index]
}

function Get-StepReadyAccount
{
    # The first main that could have its setup run right now: in the game, with a step
    # list on its own server. What the Run button acts on, and what decides whether it
    # is clickable at all.
    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        if (-not $session.IsMain) { continue }
        if ($session.State -ne "Running" -or -not $session.JoinedAt) { continue }
        if (-not (Get-SessionServer $session).StepList) { continue }
        return $accountName
    }
    return $null
}

function Get-MainAccounts
{
    # Every server's main, which is who must never be relogged on a timer or closed to
    # free memory. A server is allowed to have none.
    return @($allAccounts | Where-Object { $sessions[$_].IsMain })
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
Set-RobloxFramerateCap $servers[0].FramerateCap
if ($minimumFreeMegabytes -gt 0)
{
    Write-Log "will kill the largest alt below $minimumFreeMegabytes MB available (now $([int](Get-FreeMegabytes)) MB)"
}
else
{
    Write-Log "will not kill alts over memory (now $([int](Get-FreeMegabytes)) MB available)"
}

# The oldest running client is adopted as main. With "adopt the Roblox windows already
# open" the rest are taken as the alts instead of being closed and launched again, in the
# order they started, so a farm that is already up is picked up as it stands.
#
# Which running client belongs to which alt cannot be known: nothing local says so. For
# alts that does not matter, since they are interchangeable, but it does mean the names in
# the window are the account list's order and not necessarily what each window is logged
# into. Main is the exception and is the oldest, which is why it has to be started first.
$runningClients = @(Get-RobloxClients | Sort-Object StartTime)
if ($adoptOpenClients -and $runningClients.Count -gt 1)
{
    $takeUpTo = [math]::Min($runningClients.Count, $allAccounts.Count)
    Write-Log ("adopting the $takeUpTo client$(if ($takeUpTo -ne 1) { 's' }) already open instead of launching; " +
               "the oldest is taken as main and the rest as alts in the order they started")
    for ($adoptIndex = 0; $adoptIndex -lt $takeUpTo; $adoptIndex++)
    {
        $role = if ($adoptIndex -eq 0) { "main" } else { "an already open client for" }
        Register-AdoptedClient $allAccounts[$adoptIndex] $runningClients[$adoptIndex] $role
    }
    if ($runningClients.Count -gt $allAccounts.Count)
    {
        Write-Log ("$($runningClients.Count - $allAccounts.Count) open client$(if ($runningClients.Count - $allAccounts.Count -ne 1) { 's' }) " +
                   "left over with no account to match, so they are not tracked")
    }
}
elseif ($runningClients.Count -and $allAccounts.Count)
{
    # The oldest window goes to the first account in the list, which is the first
    # server's main when it has one. A first server with no main at all means the oldest
    # window is simply its first alt.
    $firstName = $allAccounts[0]
    $role = if ($sessions[$firstName].IsMain) { "main" } else { "the first account" }
    Register-AdoptedClient $firstName $runningClients[0] $role
}
Write-Log "alts: $($altAccounts -join ', ')"
if ($discordWebhookUrl)
{
    Write-Log "Discord alerts are on$(if ($discordSummaryMinutes -gt 0) { ", with a status message every $discordSummaryMinutes min" })"

    # Starting it yourself is not news: you are sitting right there having just pressed
    # Start. Coming back by itself after a crash is news, because the crash message only
    # promised it would try, and this is what says it worked.
    if ($autoStarted)
    {
        Send-DiscordAlert "Watchdog is back up" ("It restarted itself after crashing and is watching " +
            "$($allAccounts.Count) accounts again: " + ($allAccounts -join ", ")) $alertGreen
    }
}

if ($closeOtherClients -and $adoptOpenClients)
{
    # The settings window will not let both be ticked, but this is still reachable: a
    # restart after a crash goes straight in without opening it, so a settings file that
    # already had both, or was edited by hand, arrives here as it is. Adopting wins,
    # because closing the windows would destroy the very thing it was told to adopt.
    Write-Log ("not closing the other Roblox windows: they are being adopted instead. Untick " +
               "'Adopt the windows already open' if you want them closed on start")
}
elseif ($closeOtherClients)
{
    $claimedIds = @($sessions.Values | ForEach-Object { $_.ProcessId } | Where-Object { $_ -ne 0 })
    Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object { $claimedIds -notcontains $_.Id -and $_.MainWindowHandle -ne 0 } |
        ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Log "closed leftover PID $($_.Id)"
        }
}

# ---- Status window ----------------------------------------------------------------

$statusForm = New-Object System.Windows.Forms.Form
$statusForm.Text = "Roblox Watchdog"
$statusForm.Size = New-Object System.Drawing.Size(580, 648)                           # grown for the Add server row
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
    $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(22, 40, 34)           # green tinted, mixed against the new background
    $elevationStrip.ForeColor = $themeGreen
}
else
{
    $elevationStrip.Text = "Not running as administrator. If Account Manager is elevated, tiling, anti-idle and closing strays will be denied."
    $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(48, 36, 18)           # amber tinted
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

$saveLayoutButton = New-Object System.Windows.Forms.Button
$saveLayoutButton.Text = "Save layout"
$saveLayoutButton.Location = New-Object System.Drawing.Point(310, 424)
$saveLayoutButton.Size = New-Object System.Drawing.Size(120, 27)
Set-ThemedButton $saveLayoutButton $false
$statusForm.Controls.Add($saveLayoutButton)

$loadLayoutButton = New-Object System.Windows.Forms.Button
$loadLayoutButton.Text = "Load layout"
$loadLayoutButton.Location = New-Object System.Drawing.Point(436, 424)
$loadLayoutButton.Size = New-Object System.Drawing.Size(120, 27)
Set-ThemedButton $loadLayoutButton $false
$statusForm.Controls.Add($loadLayoutButton)

$saveLayoutButton.Add_Click({
    $saved = Save-WindowLayout
    if ($saved) { $headline.Text = "saved $saved window$(if ($saved -ne 1) { 's' })" }
})

$loadLayoutButton.Add_Click({
    $moved = Restore-WindowLayout
    if ($moved) { $headline.Text = "put $moved window$(if ($moved -ne 1) { 's' }) back" }
})

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
    $ready = Get-StepReadyAccount
    if (-not $ready) { return }
    Start-StepRun $ready "you pressed Run"
})

$addServerButton = New-Object System.Windows.Forms.Button
$addServerButton.Text = "Add server"
$addServerButton.Location = New-Object System.Drawing.Point(14, 505)
$addServerButton.Size = New-Object System.Drawing.Size(120, 27)
Set-ThemedButton $addServerButton $false
$statusForm.Controls.Add($addServerButton)

$addServerButton.Add_Click({
    # A whole farm added while the rest keeps running. The same window the settings use,
    # so there is one place that knows what a server looks like.
    $fresh = Get-DefaultServer
    $fresh.Name = "Server $($servers.Count + 1)"
    foreach ($key in "MaximumSessionMinutes", "AntiIdleMinutes", "AntiIdleKey", "AggressiveAntiIdle", "FramerateCap")
    {
        $fresh[$key] = $servers[0][$key]
    }
    $fresh.PlaceId = $servers[0].PlaceId

    $added = Show-ServerWindow $fresh $servers.Count $false
    if (-not $added) { return }

    # Checked before anything is touched, including against the accounts already running,
    # so a typo cannot leave the watchdog half changed
    $candidate = @($servers) + @($added)
    try
    {
        $trial = @{}
        foreach ($key in $settings.Keys) { $trial[$key] = $settings[$key] }
        $trial["Servers"] = $candidate
        Test-Settings $trial
    }
    catch
    {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Check that server",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:settings["Servers"] = $candidate
    Save-Settings $script:settings
    $changes = Sync-SessionsWithServers $candidate
    Write-Log "added $($added.Name) from the window: $(@(Get-ServerAccounts $added) -join ', ')"
    $headline.Text = "added $($added.Name), starting $($changes.Added.Count) account$(if ($changes.Added.Count -ne 1) { 's' })"
})

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Location = New-Object System.Drawing.Point(450, 468)
$exitButton.Size = New-Object System.Drawing.Size(100, 30)
Set-ThemedButton $exitButton $false
$statusForm.Controls.Add($exitButton)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Location = New-Object System.Drawing.Point(14, 546)                         # below Add server, which sits at 505
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

        # Nothing was read while paused, so the logs have a pause worth of history in
        # them. Skipping to the end means resuming does not act on a disconnect that has
        # already come and gone, or relog an account that came back half an hour ago.
        $skipped = 0
        foreach ($pausedName in $allAccounts)
        {
            $pausedSession = $sessions[$pausedName]
            if (-not $pausedSession.LogPath) { continue }
            try
            {
                $length = (Get-Item $pausedSession.LogPath -ErrorAction Stop).Length
                if ($length -gt $pausedSession.LogOffset)
                {
                    $pausedSession.LogOffset = $length
                    $skipped++
                }
            }
            catch { }
        }
        Write-Log ("resumed from the window" +
                   $(if ($skipped) { ", skipping what $skipped log$(if ($skipped -ne 1) { 's' }) gained while paused" } else { "" }))
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

    # Servers first: that is what decides which accounts exist and what each one does
    $changes = Sync-SessionsWithServers $updated.Servers

    $script:relaunchDelaySeconds = [int]$updated.RelaunchDelaySeconds
    $script:reapStrayMinutes = [int]$updated.ReapStrayMinutes
    $script:closeOtherClients = ($updated.CloseOtherClients -ne "False")
    $script:adoptOpenClients = ($updated.AdoptOpenClients -eq "True")
    $script:useAllMonitors = ($updated.UseAllMonitors -ne "False")
    $script:discordWebhookUrl = $updated.DiscordWebhookUrl
    $script:discordPingId = $updated.DiscordPingId
    $script:discordSummaryMinutes = [int]$updated.DiscordSummaryMinutes
    $script:rememberWindowPositions = ($updated.RememberWindowPositions -ne "False")

    # The first server's, still only used as the answer before a server is known
    $script:minimumFreeMegabytes = [int]$script:servers[0].MinimumFreeMegabytes
    $script:maximumSessionMinutes = [int]$script:servers[0].MaximumSessionMinutes
    $script:framerateCap = [int]$script:servers[0].FramerateCap
    $script:antiIdleMinutes = [int]$script:servers[0].AntiIdleMinutes
    $script:antiIdleKey = $script:servers[0].AntiIdleKey
    $script:aggressiveAntiIdle = ("$($script:servers[0].AggressiveAntiIdle)" -eq "True")
    $script:antiIdleAction = try { Get-AntiIdleAction $script:antiIdleKey } catch { $null }
    $script:stepListText = $script:servers[0].StepList
    $script:runStepsOnRejoin = ("$($script:servers[0].RunStepsOnRejoin)" -eq "True")
    if (-not $script:rememberWindowPositions)
    {
        # The file is kept and simply not used, rather than deleted. It used to be
        # deleted here, which would now throw away a layout saved on purpose with the
        # button. Unticking means back to the grid; Load layout still works, and
        # re-ticking brings the layout back.
        Write-Log "windows go back to the grid on launch; the saved layout is kept and Load layout still uses it"
    }
    Write-Log "settings saved and applied"

    # No restart needed any more: whatever changed is already live
    if ($changes.Added.Count -or $changes.Dropped.Count)
    {
        $parts = @()
        if ($changes.Added.Count) { $parts += "starting $($changes.Added.Count): $($changes.Added -join ', ')" }
        if ($changes.Dropped.Count) { $parts += "no longer watching $($changes.Dropped -join ', ')" }
        $headline.Text = ($parts -join "  and  ")
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
        if ($sessions[$accountName].IsMain) { $label += "   (main)" }
        if ($servers.Count -gt 1)
        {
            # Only worth the room when there is something to tell apart
            $label += "   [$((Get-SessionServer $session).Name)]"
        }
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

    if ($script:stepRun.Active)
    {
        $runStepsButton.Enabled = $true
        $runStepsButton.Text = "Stop $($script:stepRun.Index)/$($script:stepRun.Steps.Count)"
    }
    else
    {
        # Clickable when some server's main is in the game with a setup to run, whichever
        # server that turns out to be
        $runStepsButton.Enabled = ((Get-StepReadyAccount) -and -not $script:globalPaused)
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
        if ($detailSession.ChallengeSeenAt -and -not $detailSession.JoinedAt)
        {
            $waiting = [int]((Get-Date) - $detailSession.ChallengeSeenAt).TotalMinutes
            $parts.Add("Roblox wants its press and hold check passed, waiting $waiting min, nothing will be relaunched until it is")
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
            $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(44, 26, 48)   # accent tinted, for the update notice
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
            # The highest threshold any server asked for: free memory is one number for
            # the whole machine, so that is the point at which somebody wants something
            # closed. Which server's alt gets closed is decided below.
            $thresholds = @($servers | ForEach-Object { [int]$_.MinimumFreeMegabytes } | Where-Object { $_ -gt 0 })
            $minimumFreeMegabytes = if ($thresholds.Count) { ($thresholds | Measure-Object -Maximum).Maximum } else { 0 }
            if ($freeMegabytes -ge $minimumFreeMegabytes) { $script:lowMemoryAlerted = $false }

            # A closing client takes a while to hand its memory back, and the check runs
            # every ten seconds, so without a gap a machine that stays low closes one alt
            # after another until there are none left. One at a time, then wait and look
            # again.
            $killCooldownOver = (-not $script:lastMemoryKillAt) -or
                                (((Get-Date) - $script:lastMemoryKillAt).TotalSeconds -ge $memoryKillCooldownSeconds)

            if ($minimumFreeMegabytes -gt 0 -and $freeMegabytes -lt $minimumFreeMegabytes -and $killCooldownOver)
            {
                # Never a main, on any server, and only an alt whose own server asked to
                # be included: a server left at 0 is protected while another is not, so
                # one farm can be sacrificed to keep another alive.
                $mainProcessIds = @(Get-MainAccounts | ForEach-Object { $sessions[$_].ProcessId } | Where-Object { $_ -ne 0 })
                $closableIds = @($allAccounts |
                    Where-Object { -not $sessions[$_].IsMain -and $sessions[$_].ProcessId -ne 0 -and
                                   [int](Get-SessionServer $sessions[$_]).MinimumFreeMegabytes -gt 0 -and
                                   $freeMegabytes -lt [int](Get-SessionServer $sessions[$_]).MinimumFreeMegabytes } |
                    ForEach-Object { $sessions[$_].ProcessId })

                $largestAlt = Get-RobloxClients |
                    Where-Object { $mainProcessIds -notcontains $_.Id -and $closableIds -contains $_.Id } |
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

        # Paused used to stop the relaunching but not the watching, so it still read the
        # logs, still decided an account had changed server, and still closed a client
        # over a disconnect it could then not relaunch. Pause means leave everything
        # alone, so nothing in here runs at all.
        if ($script:globalPaused) { continue }

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
                        if ($sessions[$accountName].IsMain) { $mainDroppedThisPass = $true }
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
                                if ($sessions[$accountName].IsMain) { $mainReloggedThisPass = $true }
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
                                if ($sessions[$accountName].IsMain) { $mainReloggedThisPass = $true }
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
                            if ($sessions[$accountName].IsMain) { $mainDroppedThisPass = $true }
                            Stop-Session $accountName "disconnected (reason $realDropReason)"
                        }
                    }

                    # Waiting on a person, so the clock below does not apply: the window is
                    # left exactly as it is for as long as it takes, and relaunching it
                    # would only throw the page away and ask Roblox again.
                    if ($session.ChallengeSeenAt -and -not $session.JoinedAt)
                    {
                        if (-not $session.ChallengeAlerted)
                        {
                            $session.ChallengeAlerted = $true
                            Write-Log ("$accountName is being asked to pass Roblox's verification before it can " +
                                       "join, so it is being left alone until someone does. Hold the button in " +
                                       "its window and it will carry on by itself")
                            Send-DiscordAlert "$accountName needs you to verify it" ("Roblox is asking for its " +
                                "press and hold check before letting $accountName into the game.`n`nIts window " +
                                "is being left open and nothing will be relaunched until it is done, because " +
                                "every retry asks Roblox again and makes it more likely to keep asking.") $alertAmber $true
                        }
                    }
                    elseif ($session.State -eq "Running" -and -not $session.JoinedAt -and $session.StartedAt -and
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
                                    "that server.") $alertRed $sessions[$accountName].IsMain
                            }
                        }
                    }

                    # Every server relogs its own alts on its own timer, and no server's
                    # main is ever relogged on one
                    $relogAfter = [int](Get-SessionServer $session).MaximumSessionMinutes
                    if ($session.State -eq "Running" -and -not $session.IsMain -and $relogAfter -gt 0 -and
                        $session.StartedAt -and
                        ((Get-Date) - $session.StartedAt).TotalMinutes -gt $relogAfter)
                    {
                        Stop-Session $accountName "is older than $relogAfter min"
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
                                # Size as well as position: resizing a window without
                                # moving its corner was never noticed, so a window made
                                # bigger went back to its old size on the next launch
                                $applied = $session.AppliedRect -split ','
                                $movedBy = [math]::Max([math]::Abs($current.X - [int]$applied[0]),
                                                       [math]::Abs($current.Y - [int]$applied[1]))
                                if ($applied.Count -eq 4)
                                {
                                    $movedBy = [math]::Max($movedBy,
                                        [math]::Max([math]::Abs($current.Width - [int]$applied[2]),
                                                    [math]::Abs($current.Height - [int]$applied[3])))
                                }
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
                $antiIdleServer = Get-SessionServer $session
                if ([int]$antiIdleServer.AntiIdleMinutes -gt 0 -and -not $script:globalPaused -and
                    -not $antiIdleSentThisPass -and
                    $session.State -eq "Running" -and -not $session.ChallengeSeenAt -and
                    $session.LastInputAt -and
                    ((Get-Date) - $session.LastInputAt).TotalMinutes -ge (Get-AntiIdleInterval $antiIdleServer))
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
            if ($sessions[$accountName].IsMain) { $mainReloggedThisPass = $true }
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
            if ($sessions[$accountName].IsMain) { $mainDroppedThisPass = $true }
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
    # Each server's main, in order. A main whose turn cannot come yet keeps its setup
    # pending rather than losing it, so it is picked up on a later pass.
    $stepsWaiting = $false
    foreach ($mainName in (Get-MainAccounts))
    {
        $mainSession = $sessions[$mainName]
        if (-not $mainSession.StepsPending) { continue }
        if ($mainSession.State -ne "Running" -or -not $mainSession.JoinedAt) { continue }

        $mainServer = Get-SessionServer $mainSession
        if (-not $mainServer.StepList) { continue }

        if ("$($mainServer.RunStepsOnRejoin)" -eq "True")
        {
            if ($script:stepRun.Active) { continue }                                   # its turn comes later
            $mainSession.StepsPending = $false
            Start-StepRun $mainName "$mainName rejoined"
        }
        else
        {
            $mainSession.StepsPending = $false
            $stepsWaiting = $true
            Write-Log "$mainName is back in the game, the steps are waiting for you to press Run"
        }
    }

    # Nothing has gone wrong, so this is not an error, but the account comes back with its
    # character respawned and its inventory in the hotbar. Anything placed by hand has to
    # be placed again, which is worth being told. Main is always worth saying, because it
    # is the one with a setup; a whole group relogging at once is worth saying because it
    # means every one of them needs it. A single alt is logged and left at that.
    if ($mainReloggedThisPass -or $reloggedThisPass.Count -ge $relogWaveSize)
    {
        $mainsRelogged = @($reloggedThisPass | Where-Object { $sessions[$_].IsMain })
        $others = @($reloggedThisPass | Where-Object { -not $sessions[$_].IsMain })
        if ($mainsRelogged.Count)
        {
            # Named rather than called "main", because with more than one server there is
            # more than one main and knowing which one it was is the point of the message
            $who = $mainsRelogged -join ", "
            $hasSteps = @($mainsRelogged | Where-Object { (Get-SessionServer $sessions[$_]).StepList }).Count -gt 0
            $tail = if ($stepsWaiting) { "Press Run in the watchdog window to set it up again." }
                    elseif ($hasSteps) { "The steps are running now." }
                    else { "Its inventory is back in the hotbar, so the rockets need placing again." }
            $withOthers = if ($others.Count) { "`n`nAlso relogged: $($others -join ', ')" } else { "" }
            $title = if ($mainsRelogged.Count -gt 1) { "$($mainsRelogged.Count) mains relogged" } else { "Main relogged" }
            Send-DiscordAlert $title ("$who went back into the game on its own, so it was not " +
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