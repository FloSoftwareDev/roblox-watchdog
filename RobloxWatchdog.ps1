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
#
#------------------------------------------------------------------------------------#

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

$processName = "RobloxPlayerBeta"
$minimumClientBytes = 500MB
$checkIntervalSeconds = 10
$maximumLaunchFailures = 5                                                           # log loudly after this many failed launches in a row
$logFolder = Join-Path $env:LOCALAPPDATA "Roblox\logs"                              # Roblox client log files
$disconnectPattern = "Sending disconnect with reason: (\d+)"                         # logged on drop (277) and leave (285)
$ignoredDisconnectReasons = @()                                                      # e.g. @("285") to ignore a normal leave/teleport
$httpClient = New-Object System.Net.Http.HttpClient
$httpClient.Timeout = [TimeSpan]::FromSeconds(15)                                    # never let a hung RAM freeze the watchdog

# Settings live in LOCALAPPDATA, not next to the script: when run as a .ps1 the old
# path resolved to the PowerShell install folder under System32
$scriptFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Environment]::GetCommandLineArgs()[0]) }
$settingsFolder = Join-Path $env:LOCALAPPDATA "RobloxWatchdog"
$settingsPath = Join-Path $settingsFolder "RobloxWatchdog.json"
$legacySettingsPath = Join-Path $scriptFolder "RobloxWatchdog.json"                  # pre-003 location, migrated on first run
$logFilePath = Join-Path $settingsFolder "RobloxWatchdog.log"

trap
{
    Write-Host "ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

function Write-Log($message)
{
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
    Write-Host $line
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
    $form.Size = New-Object System.Drawing.Size(460, 560)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    $inputs = @{}
    $rowTop = 15

    function Add-Row($labelText, $key, $height, $isPassword)
    {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labelText
        $label.Location = New-Object System.Drawing.Point(15, $rowTop)
        $label.Size = New-Object System.Drawing.Size(170, 20)
        $form.Controls.Add($label)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(190, $rowTop)
        $textBox.Size = New-Object System.Drawing.Size(240, $height)
        $textBox.Text = $saved[$key]
        if ($height -gt 20)
        {
            $textBox.Multiline = $true
            $textBox.AcceptsReturn = $true
            $textBox.ScrollBars = "Vertical"
        }
        if ($isPassword)
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

    # Closing other clients is destructive, so it is a deliberate choice
    $closeOthersBox = New-Object System.Windows.Forms.CheckBox
    $closeOthersBox.Text = "Close other Roblox windows on start"
    $closeOthersBox.Location = New-Object System.Drawing.Point(190, $rowTop)
    $closeOthersBox.Size = New-Object System.Drawing.Size(240, 20)
    $closeOthersBox.Checked = ($saved["CloseOtherClients"] -ne "False")
    $form.Controls.Add($closeOthersBox)
    $rowTop += 30

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "A running client is adopted as main; otherwise main is launched."
    $note.Location = New-Object System.Drawing.Point(15, $rowTop)
    $note.Size = New-Object System.Drawing.Size(415, 20)
    $form.Controls.Add($note)

    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "Start"
    $startButton.Location = New-Object System.Drawing.Point(330, ($rowTop + 30))
    $startButton.Size = New-Object System.Drawing.Size(100, 30)
    $startButton.DialogResult = "OK"
    $form.Controls.Add($startButton)
    $form.AcceptButton = $startButton

    if ($form.ShowDialog() -ne "OK")
    {
        exit 0
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
}

# Reopen the window on a bad value instead of throwing away everything that was typed
$settings = Get-SavedSettings
while ($true)
{
    $settings = Show-SettingsWindow $settings
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
"@

function Set-ClientWindow($processId, $slotIndex)
{
    # Roblox creates its window a few seconds after the process starts
    $process = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++)
    {
        Start-Sleep -Seconds 2
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process -and $process.MainWindowHandle -ne 0)
        {
            break
        }
    }
    if (-not $process -or $process.MainWindowHandle -eq 0)
    {
        # Tiling is cosmetic: a client without a window keeps running, just untiled
        Write-Log "WARNING: client PID $processId never showed a window, leaving it untiled"
        return
    }

    # Roblox restores its own saved size right after the window appears; move after that
    Start-Sleep -Seconds 5

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $columns = [math]::Ceiling([math]::Sqrt($allAccounts.Count))
    $rows = [math]::Ceiling($allAccounts.Count / $columns)
    $tileWidth = [int]($screen.Width / $columns)
    $tileHeight = [int]($screen.Height / $rows)
    $x = $screen.X + ($slotIndex % $columns) * $tileWidth
    $y = $screen.Y + [math]::Floor($slotIndex / $columns) * $tileHeight

    [Win32.Window]::ShowWindow($process.MainWindowHandle, 9) | Out-Null   # SW_RESTORE, MoveWindow ignores maximized windows
    [Win32.Window]::MoveWindow($process.MainWindowHandle, $x, $y, $tileWidth, $tileHeight, $true) | Out-Null
    Write-Log "moved PID $processId to slot $slotIndex ($x,$y $($tileWidth)x$($tileHeight))"
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
    # is only logged; the new Roblox window in Start-Client is the real success check
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

function Start-Client($accountName)
{
    $trackedIds = @($sessions.Values | ForEach-Object { $_.ProcessId })

    $launchUrl = Get-LaunchUrl $accountName
    $ramReply = Invoke-AccountManager $launchUrl                                      # last RAM answer
    Write-Log "launched $accountName"

    # Poll every 200 ms so we kill RobloxInstaller before it can close other instances
    $installerKilled = $false
    for ($attempt = 0; $attempt -lt 450; $attempt++)   # 450 x 200 ms = 90 s
    {
        Start-Sleep -Milliseconds 200

        $installer = Get-Process "RobloxInstaller" -ErrorAction SilentlyContinue
        if ($installer)
        {
            $installer | Stop-Process -Force -ErrorAction SilentlyContinue
            if (-not $installerKilled)
            {
                $installerKilled = $true
                Write-Log "killed RobloxInstaller for $accountName, retrying launch (a Roblox update in progress may need repairing)"
                Start-Sleep -Milliseconds 500
                $ramReply = Invoke-AccountManager $launchUrl
            }
        }

        $newClient = Get-Process $processName -ErrorAction SilentlyContinue |
            Where-Object { $trackedIds -notcontains $_.Id -and $_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime |
            Select-Object -First 1

        if ($newClient) { return $newClient }
    }

    throw "No new Roblox window appeared after launching $accountName (RAM replied: $ramReply)"
}

function Get-PlayerLogFiles
{
    Get-ChildItem $logFolder -Filter "*_Player_*.log" -ErrorAction Stop
}

function Find-NewLogFile($launchTime)
{
    # Launches run one at a time, so the oldest unclaimed log since launch is this client's
    $takenPaths = @($sessions.Values | ForEach-Object { $_.LogPath })
    for ($attempt = 0; $attempt -lt 30; $attempt++)
    {
        $logFile = Get-PlayerLogFiles |
            Where-Object { $_.CreationTime -ge $launchTime -and $takenPaths -notcontains $_.FullName } |
            Sort-Object CreationTime |
            Select-Object -First 1
        if ($logFile) { return $logFile.FullName }
        Start-Sleep -Seconds 1
    }
    throw "No new *_Player_*.log appeared in $logFolder after launching at $launchTime"
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

function Get-DisconnectReason($session)
{
    # Returns the Roblox disconnect code (e.g. 277, 285), or $null while still connected
    $match = [regex]::Match((Read-NewLogText $session), $disconnectPattern)          # first disconnect line
    if ($match.Success -and $ignoredDisconnectReasons -notcontains $match.Groups[1].Value)
    {
        return $match.Groups[1].Value
    }
    return $null
}

function Start-Session($accountName)
{
    $session = $sessions[$accountName]
    $launchTime = Get-Date                                                            # log files after this are new
    $process = Start-Client $accountName

    # The session is only filled in once the log is found, so a half-started client
    # is never left running untracked
    try
    {
        $logPath = Find-NewLogFile $launchTime
    }
    catch
    {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw
    }

    $session.ProcessId = $process.Id
    $session.ProcessStartTime = $process.StartTime
    $session.LogPath = $logPath
    $session.LogOffset = 0
    $session.StartedAt = Get-Date
    Write-Log "$accountName running as PID $($session.ProcessId), log $(Split-Path -Leaf $session.LogPath)"

    # Staggers the next launch so accounts don't join at the same second
    foreach ($otherSession in $sessions.Values)
    {
        if ($otherSession.ProcessId -eq 0)
        {
            $otherSession.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
        }
    }

    Set-ClientWindow $session.ProcessId ([array]::IndexOf($allAccounts, $accountName))
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
    $session.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
}

# Main first, so it is relaunched before any alt
$allAccounts = @($mainAccount) + $altAccounts
$sessions = @{}
foreach ($accountName in $allAccounts)
{
    $sessions[$accountName] = @{ ProcessId = 0; ProcessStartTime = $null; StartedAt = $null
                                 RelaunchAfter = (Get-Date); LogPath = $null; LogOffset = 0; FailureCount = 0 }
}

Write-Log "watchdog started, settings in $settingsPath, log in $logFilePath"
Write-Log "will kill the largest alt below $minimumFreeMegabytes MB available (now $([int](Get-FreeMegabytes)) MB)"

# A running client is adopted as main; everything else is untracked and closed
$runningMain = Get-RobloxClients | Sort-Object StartTime | Select-Object -First 1
if ($runningMain)
{
    $sessions[$mainAccount].ProcessId = $runningMain.Id
    $sessions[$mainAccount].ProcessStartTime = $runningMain.StartTime
    $sessions[$mainAccount].StartedAt = $runningMain.StartTime
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
    Set-ClientWindow $runningMain.Id 0                                                # main is always slot 0
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

while ($true)
{
    # Nothing in here is fatal: a bad tick is logged and retried on the next one
    try
    {
        $freeMegabytes = Get-FreeMegabytes
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

    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]
        try
        {
            if ($session.ProcessId -eq 0)
            {
                if ((Get-Date) -ge $session.RelaunchAfter)
                {
                    try
                    {
                        Start-Session $accountName
                        $session.FailureCount = 0
                    }
                    catch
                    {
                        # Back off a little further each time instead of hammering RAM, but
                        # never give up: an account that cannot start yet keeps being retried
                        $session.FailureCount++
                        $backoffSeconds = [math]::Min($relaunchDelaySeconds * $session.FailureCount, 600)
                        $session.RelaunchAfter = (Get-Date).AddSeconds($backoffSeconds)
                        Write-Log "WARNING: launching $accountName failed ($($session.FailureCount)x): $($_.Exception.Message)"
                        if ($session.FailureCount -eq $maximumLaunchFailures)
                        {
                            Write-Log "ERROR: $accountName has failed $maximumLaunchFailures launches in a row, is RAM running with the web server on?"
                        }
                        Write-Log "retrying $accountName in $backoffSeconds s"
                    }
                }
            }
            elseif (-not (Get-SessionProcess $session))
            {
                Stop-Session $accountName "is gone"
            }
            elseif ($session.LogPath)
            {
                $disconnectReason = Get-DisconnectReason $session                     # $null = still connected
                if ($disconnectReason)
                {
                    Stop-Session $accountName "disconnected (reason $disconnectReason)"
                }
                elseif ($accountName -ne $mainAccount -and $session.StartedAt -and
                        ((Get-Date) - $session.StartedAt).TotalMinutes -gt $maximumSessionMinutes)
                {
                    Stop-Session $accountName "is older than $maximumSessionMinutes min"
                }
            }
        }
        catch
        {
            Write-Log "WARNING: checking $accountName failed: $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}
