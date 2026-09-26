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
# 002          21-09-2026 Miniwar AFK FG  Disconnect-detectie via Roblox logbestanden, main wordt ook herstart en getegeld (slot 0)
# 003          22-09-2026 Miniwar AFK FG  Security: instellingen naar LOCALAPPDATA, wachtwoord versleuteld (DPAPI),
#                                         bestandsrechten dichtgezet, private server link gevalideerd, PID-hergebruik afgevangen.
#                                         Robuustheid: fouten in de lus niet meer fataal, backoff na mislukte launches,
#                                         HTTP-timeout, logbestand, afgeknot logbestand afgevangen.
# 004          23-09-2026 Miniwar AFK FG  Framerate cap tegen CPU-verbruik, anti-idle: venster naar voren en toetsaanslag
#                                         zodat Roblox de client niet na 20 minuten kickt.
# 005          25-09-2026 Miniwar AFK FG  Client die wel start maar nooit in de game komt wordt herstart (geen disconnectcode
#                                         bij "failed to connect"), zwerfprocessen zonder venster worden opgeruimd,
#                                         fatale fouten gaan naar het logbestand in plaats van alleen het console.
# 006          26-09-2026 Miniwar AFK FG  Statusvenster in plaats van een console: de lus is nu een state machine die per
#                                         tick een stap zet, zodat het venster niet vastloopt tijdens een launch. Tray-icoon,
#                                         pauzeknop, per-account herstarten en een zichtbare melding als rechten ontbreken.
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
$maximumLaunchFailures = 5                                                           # log loudly after this many failed launches in a row
$logFolder = Join-Path $env:LOCALAPPDATA "Roblox\logs"                              # Roblox client log files
$disconnectPattern = "Sending disconnect with reason: (\d+)"                         # logged on drop (277) and leave (285)
$ignoredDisconnectReasons = @()                                                      # e.g. @("285") to ignore a normal leave/teleport
$joinMarker = "Connection accepted"                                                  # logged only once the client is really in the game
$joinTimeoutSeconds = 150                                                            # no join by then means it is stuck on an error screen
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

function Write-ElevationHint
{
    # Said once, not on every denial: the old version repeated the same failure every
    # ten seconds and buried everything else in the log
    if ($script:elevationHintShown -or $isElevated) { return }
    $script:elevationHintShown = $true
    Write-Log "HINT: that was denied because the watchdog is not running as administrator while the Roblox clients are."
    Write-Log "HINT: either run the exe as administrator, or stop running Roblox Account Manager as administrator (which also fixes autoclickers)."
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
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host "Closing in 15 seconds, the reason is in $logFilePath" -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    exit 1
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
        Write-Host "WARNING: the saved password could not be decrypted, please type it again" -ForegroundColor Yellow
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
        ReapStrayMinutes       = "3"
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
    $form.Size = New-Object System.Drawing.Size(600, 680)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

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
        $form.Controls.Add($label)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(248, $rowTop)
        $textBox.Size = New-Object System.Drawing.Size(320, $height)
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
    Add-Row "Kill an alt below free MB" "MinimumFreeMegabytes" 20 $false
    Add-Row "Seconds between launches" "RelaunchDelaySeconds" 20 $false
    Add-Row "Relog alts after minutes" "MaximumSessionMinutes" 20 $false
    Add-Row "Frame rate cap (0=off)" "FramerateCap" 20 $false
    Add-Row "Anti-idle every min (0=off)" "AntiIdleMinutes" 20 $false
    Add-Row "Anti-idle key" "AntiIdleKey" 20 $false
    Add-Row "Close strays after min (0=off)" "ReapStrayMinutes" 20 $false

    # Closing other clients is destructive, so it is a deliberate choice
    $closeOthersBox = New-Object System.Windows.Forms.CheckBox
    $closeOthersBox.Text = "Close other Roblox windows on start"
    $closeOthersBox.Location = New-Object System.Drawing.Point(248, $rowTop)
    $closeOthersBox.Size = New-Object System.Drawing.Size(320, 20)
    $closeOthersBox.Checked = ($saved["CloseOtherClients"] -ne "False")
    $form.Controls.Add($closeOthersBox)
    $rowTop += 30

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "A running client is adopted as main; otherwise main is launched."
    $note.Location = New-Object System.Drawing.Point(15, $rowTop)
    $note.Size = New-Object System.Drawing.Size(553, 20)
    $form.Controls.Add($note)

    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "Start"
    $startButton.Location = New-Object System.Drawing.Point(468, ($rowTop + 30))
    $startButton.Size = New-Object System.Drawing.Size(100, 30)
    $startButton.DialogResult = "OK"
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

    # The link is handed straight to RAM, so only accept a real Roblox one
    if ($settings.PrivateServerLink -and $settings.PrivateServerLink -notmatch '^https://(www\.)?roblox\.com/')
    {
        throw "Private server link must start with https://www.roblox.com/ (paste the full share link)"
    }

    foreach ($key in "MinimumFreeMegabytes", "RelaunchDelaySeconds", "MaximumSessionMinutes")
    {
        if ($settings[$key] -notmatch '^\d{1,9}$') { throw "$key must be a number" }
    }
    if ([int]$settings.MinimumFreeMegabytes -lt 100) { throw "Kill an alt below free MB must be at least 100" }
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
}

# Reopen the window on a bad value instead of throwing away everything that was typed
$settings = Get-SavedSettings
while ($true)
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
# A-Z virtual key codes are the same numbers as their uppercase characters
$antiIdleVirtualKey = if ($antiIdleKey -eq "Space") { [byte]0x20 } else { [byte][char]([string]$antiIdleKey).ToUpper() }
$reapStrayMinutes = [int]$settings.ReapStrayMinutes
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

Add-Type -Namespace Win32 -Name Window -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hWnd, bool altTab);
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
[DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);
"@

# Separate block because it needs a struct, which -MemberDefinition cannot declare.
# Used to read a window back after moving it: MoveWindow can report success while the
# window has not actually budged.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public class WinPos
{
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
}
"@

function Set-ClientWindow($processId, $slotIndex)
{
    # Nothing here waits: the Tiling state does the waiting, one step per tick, so the
    # status window stays responsive instead of freezing for a minute per launch
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    $process.Refresh()
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $columns = [math]::Ceiling([math]::Sqrt($allAccounts.Count))
    $rows = [math]::Ceiling($allAccounts.Count / $columns)
    $tileWidth = [int]($screen.Width / $columns)
    $tileHeight = [int]($screen.Height / $rows)
    $x = $screen.X + ($slotIndex % $columns) * $tileWidth
    $y = $screen.Y + [math]::Floor($slotIndex / $columns) * $tileHeight

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
        Write-Log "moved PID $processId to slot $slotIndex ($x,$y $($tileWidth)x$($tileHeight))"
        return $true
    }

    Write-Log "WARNING: PID $processId did not move to slot $slotIndex (asked for $x,$y, it sits at $($rect.Left),$($rect.Top))"
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

    [Win32.Window]::ShowWindow($handle, 9) | Out-Null                                 # SW_RESTORE, a minimised window cannot take focus
    [Win32.Window]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds 400

    if ([Win32.Window]::GetForegroundWindow() -ne $handle)
    {
        # Windows refuses SetForegroundWindow unless the caller already owns the
        # foreground; SwitchToThisWindow is not bound by that
        [Win32.Window]::SwitchToThisWindow($handle, $true)
        Start-Sleep -Milliseconds 400
    }

    if ([Win32.Window]::GetForegroundWindow() -ne $handle)
    {
        # Retry in a minute rather than fighting for focus on every tick
        $session.LastInputAt = (Get-Date).AddMinutes(1 - $antiIdleMinutes)
        Write-Log "WARNING: could not focus $accountName, anti-idle keystroke not sent, retrying in 1 min"
        Write-ElevationHint
        return
    }

    $scanCode = [byte]([Win32.Window]::MapVirtualKey($antiIdleVirtualKey, 0))          # games want a real scan code
    [Win32.Window]::keybd_event($antiIdleVirtualKey, $scanCode, 0, [UIntPtr]::Zero)    # key down
    Start-Sleep -Milliseconds 80
    [Win32.Window]::keybd_event($antiIdleVirtualKey, $scanCode, 2, [UIntPtr]::Zero)    # KEYEVENTF_KEYUP
    $session.LastInputAt = Get-Date
    Write-Log "anti-idle: pressed $antiIdleKey in $accountName"

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

    $newClient = Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object { $session.LaunchTrackedIds -notcontains $_.Id -and $_.MainWindowHandle -ne 0 } |
        Sort-Object StartTime |
        Select-Object -First 1

    if ($newClient)
    {
        $session.ProcessId = $newClient.Id
        $session.ProcessStartTime = $newClient.StartTime
        Set-SessionState $session "FindingLog"
        return
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
        Where-Object { $_.CreationTime -ge $session.LaunchedAt -and $takenPaths -notcontains $_.FullName } |
        Sort-Object CreationTime |
        Select-Object -First 1

    if ($logFile)
    {
        $session.LogPath = $logFile.FullName
        $session.LogOffset = 0
        $session.StartedAt = Get-Date
        $session.JoinedAt = $null                                                     # not in the game until the log says so
        $session.LastInputAt = Get-Date                                               # joining counts as input
        $session.WindowSeenAt = $null
        Write-Log "$accountName running as PID $($session.ProcessId), log $(Split-Path -Leaf $session.LogPath)"

        # Staggers the next launch so accounts don't join at the same second
        foreach ($otherSession in $sessions.Values)
        {
            if ($otherSession.State -eq "Idle")
            {
                $otherSession.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
            }
        }

        Set-SessionState $session "Tiling"
        return
    }

    if (((Get-Date) - $session.StateSince).TotalSeconds -gt $logTimeoutSeconds)
    {
        # Don't leave a half-started client running untracked
        Stop-Process -Id $session.ProcessId -Force -ErrorAction SilentlyContinue
        $session.ProcessId = 0
        $session.ProcessStartTime = $null
        throw "no new *_Player_*.log appeared within $logTimeoutSeconds s"
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

    Set-ClientWindow $session.ProcessId ([array]::IndexOf($allAccounts, $accountName)) | Out-Null
    Set-SessionState $session "Running"
}

function Get-PlayerLogFiles
{
    Get-ChildItem $logFolder -Filter "*_Player_*.log" -ErrorAction Stop
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
    # One read per tick, because the offset only moves forward and both checks share it.
    # Returns the Roblox disconnect code (e.g. 277, 285), or $null while still connected,
    # and records the moment the client actually got into the game.
    $text = Read-NewLogText $session

    if (-not $session.JoinedAt -and $text.Contains($joinMarker))
    {
        $session.JoinedAt = Get-Date
    }

    $match = [regex]::Match($text, $disconnectPattern)                               # first disconnect line
    if ($match.Success -and $ignoredDisconnectReasons -notcontains $match.Groups[1].Value)
    {
        return $match.Groups[1].Value
    }
    return $null
}

function Set-SessionState($session, $state)
{
    $session.State = $state
    $session.StateSince = Get-Date
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
    $backoffSeconds = [math]::Min($relaunchDelaySeconds * $session.FailureCount, 600)
    $session.RelaunchAfter = (Get-Date).AddSeconds($backoffSeconds)
    Set-SessionState $session "Idle"

    Write-Log "WARNING: launching $accountName failed ($($session.FailureCount)x): $message"
    if ($session.FailureCount -eq $maximumLaunchFailures)
    {
        Write-Log "ERROR: $accountName has failed $maximumLaunchFailures launches in a row, is RAM running with the web server on?"
    }
    Write-Log "retrying $accountName in $backoffSeconds s"
}

function Get-SessionStatusText($accountName)
{
    $session = $sessions[$accountName]
    if ($session.Paused) { return "paused" }

    if ($session.State -eq "Idle")
    {
        $waitSeconds = [int](($session.RelaunchAfter - (Get-Date)).TotalSeconds)
        if ($waitSeconds -gt 0) { return "relaunching in $waitSeconds s" }
        return "waiting"
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
    if ($session.Paused) { return [System.Drawing.Color]::FromArgb(150, 150, 150) }
    if ($session.State -eq "Running" -and $session.JoinedAt) { return [System.Drawing.Color]::FromArgb(30, 150, 60) }
    if ($session.State -eq "Idle") { return [System.Drawing.Color]::FromArgb(150, 150, 150) }
    return [System.Drawing.Color]::FromArgb(220, 140, 0)
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
                                 LaunchUrl = $null; WindowSeenAt = $null; Paused = $false }
}

$globalPaused = $false
$reallyExit = $false
$strayClosedCount = 0
$lastDisconnectAt = $null
$lastFreeMegabytes = 0
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
Write-Log "will kill the largest alt below $minimumFreeMegabytes MB available (now $([int](Get-FreeMegabytes)) MB)"

# A running client is adopted as main; everything else is untracked and closed
$runningMain = Get-RobloxClients | Sort-Object StartTime | Select-Object -First 1
if ($runningMain)
{
    $sessions[$mainAccount].ProcessId = $runningMain.Id
    $sessions[$mainAccount].ProcessStartTime = $runningMain.StartTime
    $sessions[$mainAccount].StartedAt = $runningMain.StartTime
    $sessions[$mainAccount].LastInputAt = Get-Date                                    # unknown when it last had input, so start the clock now
    $sessions[$mainAccount].JoinedAt = Get-Date                                       # it was already playing, so don't hold it to the join timeout
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
    Set-ClientWindow $runningMain.Id 0 | Out-Null                                     # main is always slot 0
}
Write-Log "alts: $($altAccounts -join ', ')"

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

$greyText = [System.Drawing.Color]::FromArgb(110, 110, 110)

$statusForm = New-Object System.Windows.Forms.Form
$statusForm.Text = "Roblox Watchdog"
$statusForm.Size = New-Object System.Drawing.Size(580, 600)
$statusForm.StartPosition = "CenterScreen"
$statusForm.FormBorderStyle = "FixedSingle"
$statusForm.MaximizeBox = $false
$statusForm.BackColor = [System.Drawing.Color]::White
$statusForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Always present rather than shown only on trouble, so the layout never shifts and the
# answer to "is this elevated" is on screen instead of buried in the log
$elevationStrip = New-Object System.Windows.Forms.Label
$elevationStrip.Location = New-Object System.Drawing.Point(0, 0)
$elevationStrip.Size = New-Object System.Drawing.Size(564, 44)
$elevationStrip.TextAlign = "MiddleLeft"
$elevationStrip.Padding = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)
if ($isElevated)
{
    $elevationStrip.Text = "Running as administrator."
    $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 233)
    $elevationStrip.ForeColor = [System.Drawing.Color]::FromArgb(25, 110, 50)
}
else
{
    $elevationStrip.Text = "Not running as administrator. If Account Manager is elevated, tiling, anti-idle and closing strays will be denied."
    $elevationStrip.BackColor = [System.Drawing.Color]::FromArgb(255, 244, 205)
    $elevationStrip.ForeColor = [System.Drawing.Color]::FromArgb(130, 80, 0)
}
$statusForm.Controls.Add($elevationStrip)

$headline = New-Object System.Windows.Forms.Label
$headline.Location = New-Object System.Drawing.Point(14, 58)
$headline.Size = New-Object System.Drawing.Size(536, 40)
$headline.Font = New-Object System.Drawing.Font("Segoe UI", 19)
$headline.TextAlign = "MiddleCenter"
$headline.Text = "starting"
$statusForm.Controls.Add($headline)

function New-Tile($caption, $x, $y)
{
    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Location = New-Object System.Drawing.Point($x, $y)
    $captionLabel.Size = New-Object System.Drawing.Size(250, 16)
    $captionLabel.ForeColor = $greyText
    $captionLabel.Text = $caption
    $statusForm.Controls.Add($captionLabel)

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Location = New-Object System.Drawing.Point($x, ($y + 17))
    $valueLabel.Size = New-Object System.Drawing.Size(250, 25)
    $valueLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $valueLabel.Text = "-"
    $statusForm.Controls.Add($valueLabel)
    return $valueLabel
}

$tileFreeRam  = New-Tile "free memory"     28 108
$tileStrays   = New-Tile "strays closed"   300 108
$tileUptime   = New-Tile "watchdog uptime" 28 156
$tileLastDrop = New-Tile "last disconnect" 300 156

$accountList = New-Object System.Windows.Forms.ListView
$accountList.Location = New-Object System.Drawing.Point(14, 208)
$accountList.Size = New-Object System.Drawing.Size(536, 206)
$accountList.View = "Details"
$accountList.FullRowSelect = $true
$accountList.GridLines = $false
$accountList.HeaderStyle = "Nonclickable"
$accountList.MultiSelect = $false
$accountList.Columns.Add("", 28) | Out-Null
$accountList.Columns.Add("Account", 168) | Out-Null
$accountList.Columns.Add("Status", 156) | Out-Null
$accountList.Columns.Add("Memory", 78) | Out-Null
$accountList.Columns.Add("Up", 102) | Out-Null                                        # fills the rest, so no empty sliver column
foreach ($accountName in $allAccounts)
{
    $item = New-Object System.Windows.Forms.ListViewItem("")
    $item.UseItemStyleForSubItems = $false                                            # so only the dot is coloured
    $item.SubItems.Add($accountName) | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.Tag = $accountName
    $accountList.Items.Add($item) | Out-Null
}
$statusForm.Controls.Add($accountList)

$relaunchButton = New-Object System.Windows.Forms.Button
$relaunchButton.Text = "Relaunch selected"
$relaunchButton.Location = New-Object System.Drawing.Point(14, 424)
$relaunchButton.Size = New-Object System.Drawing.Size(140, 27)
$relaunchButton.Enabled = $false
$statusForm.Controls.Add($relaunchButton)

$pauseAccountButton = New-Object System.Windows.Forms.Button
$pauseAccountButton.Text = "Pause selected"
$pauseAccountButton.Location = New-Object System.Drawing.Point(162, 424)
$pauseAccountButton.Size = New-Object System.Drawing.Size(140, 27)
$pauseAccountButton.Enabled = $false
$statusForm.Controls.Add($pauseAccountButton)

$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Text = "Settings"
$settingsButton.Location = New-Object System.Drawing.Point(14, 468)
$settingsButton.Size = New-Object System.Drawing.Size(100, 30)
$statusForm.Controls.Add($settingsButton)

$pauseButton = New-Object System.Windows.Forms.Button
$pauseButton.Text = "Pause"
$pauseButton.Location = New-Object System.Drawing.Point(122, 468)
$pauseButton.Size = New-Object System.Drawing.Size(100, 30)
$statusForm.Controls.Add($pauseButton)

$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "Log"
$logButton.Location = New-Object System.Drawing.Point(230, 468)
$logButton.Size = New-Object System.Drawing.Size(100, 30)
$statusForm.Controls.Add($logButton)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Location = New-Object System.Drawing.Point(450, 468)
$exitButton.Size = New-Object System.Drawing.Size(100, 30)
$statusForm.Controls.Add($exitButton)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Location = New-Object System.Drawing.Point(14, 508)
$hintLabel.Size = New-Object System.Drawing.Size(536, 18)
$hintLabel.ForeColor = $greyText
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
    if ($accountList.SelectedItems.Count -eq 0) { return }
    $accountName = $accountList.SelectedItems[0].Tag
    $session = $sessions[$accountName]
    if ($session.State -ne "Idle")
    {
        Stop-Session $accountName "relaunch asked for from the window"
    }
    $session.FailureCount = 0
    $session.RelaunchAfter = Get-Date
    $session.Paused = $false
})

$pauseAccountButton.Add_Click({
    if ($accountList.SelectedItems.Count -eq 0) { return }
    $accountName = $accountList.SelectedItems[0].Tag
    $session = $sessions[$accountName]
    $session.Paused = -not $session.Paused
    if ($session.Paused)
    {
        Write-Log "$accountName paused from the window, it will not be relaunched or poked"
    }
    else
    {
        $session.RelaunchAfter = Get-Date
        Write-Log "$accountName resumed from the window"
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
    $form.BackColor = [System.Drawing.Color]::White

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = "Both"
    $box.WordWrap = $false
    $box.Dock = "Fill"
    $box.BackColor = [System.Drawing.Color]::White
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
    $script:antiIdleVirtualKey = if ($updated.AntiIdleKey -eq "Space") { [byte]0x20 } else { [byte][char]([string]$updated.AntiIdleKey).ToUpper() }
    $script:reapStrayMinutes = [int]$updated.ReapStrayMinutes
    $script:closeOtherClients = ($updated.CloseOtherClients -ne "False")
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

        $item.Text = "  " + [char]0x25CF
        $item.ForeColor = Get-SessionColor $accountName

        $label = $accountName
        if ($accountName -eq $mainAccount) { $label += "   (main)" }
        $item.SubItems[1].Text = $label
        $item.SubItems[2].Text = Get-SessionStatusText $accountName

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

    $hasSelection = $accountList.SelectedItems.Count -gt 0
    $relaunchButton.Enabled = $hasSelection
    $pauseAccountButton.Enabled = $hasSelection
    if ($hasSelection)
    {
        if ($sessions[$accountList.SelectedItems[0].Tag].Paused)
        {
            $pauseAccountButton.Text = "Resume selected"
        }
        else
        {
            $pauseAccountButton.Text = "Pause selected"
        }
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
            if ($freeMegabytes -lt $minimumFreeMegabytes)
            {
                $largestAlt = Get-RobloxClients |
                    Where-Object { $_.Id -ne $sessions[$mainAccount].ProcessId } |
                    Sort-Object WorkingSet64 -Descending |
                    Select-Object -First 1

                if ($largestAlt)
                {
                    Stop-Process -Id $largestAlt.Id -Force -ErrorAction SilentlyContinue
                    Write-Log "killed PID $($largestAlt.Id) ($([int]($largestAlt.WorkingSet64 / 1MB)) MB), free was $([int]$freeMegabytes) MB"
                }
                else
                {
                    Write-Log "WARNING: only $([int]$freeMegabytes) MB free and no alt left to kill"
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

    # Focusing a window and holding a key takes most of a second, so only one account
    # gets poked per pass; several at once would visibly freeze the window
    $antiIdleSentThisPass = $false

    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        if ($session.Paused) { continue }
        try
        {
            if ($session.State -eq "Idle")
            {
                if (-not $script:globalPaused -and (Get-Date) -ge $session.RelaunchAfter)
                {
                    try
                    {
                        Request-Launch $accountName
                    }
                    catch
                    {
                        Register-LaunchFailure $accountName $_.Exception.Message
                    }
                }
            }
            elseif ($session.State -eq "Running")
            {
                if (-not (Get-SessionProcess $session))
                {
                    Stop-Session $accountName "is gone"
                }
                elseif ($session.LogPath)
                {
                    $disconnectReason = Update-SessionFromLog $session                # $null = still connected
                    if ($disconnectReason)
                    {
                        $script:lastDisconnectAt = Get-Date
                        Stop-Session $accountName "disconnected (reason $disconnectReason)"
                    }
                    elseif (-not $session.JoinedAt -and $session.StartedAt -and
                            ((Get-Date) - $session.StartedAt).TotalSeconds -gt $joinTimeoutSeconds)
                    {
                        # It launched and has a window, but never got into the game: it is
                        # sitting on a "failed to connect" screen, which no disconnect code
                        # is ever written for, so nothing else would notice it
                        Stop-Session $accountName "never joined the game within $joinTimeoutSeconds s (stuck on an error screen)"
                    }
                    elseif ($accountName -ne $mainAccount -and $session.StartedAt -and
                            ((Get-Date) - $session.StartedAt).TotalMinutes -gt $maximumSessionMinutes)
                    {
                        Stop-Session $accountName "is older than $maximumSessionMinutes min"
                    }
                }

                # Still running after the checks above, so it is due a keystroke if it
                # has gone quiet
                if ($antiIdleMinutes -gt 0 -and -not $script:globalPaused -and -not $antiIdleSentThisPass -and
                    $session.State -eq "Running" -and
                    $session.LastInputAt -and ((Get-Date) - $session.LastInputAt).TotalMinutes -ge $antiIdleMinutes)
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
