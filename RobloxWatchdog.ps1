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
#
#------------------------------------------------------------------------------------#

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

$processName = "RobloxPlayerBeta"
$minimumClientBytes = 500MB
$checkIntervalSeconds = 10
$logFolder = Join-Path $env:LOCALAPPDATA "Roblox\logs"                              # Roblox client log files
$disconnectPattern = "Sending disconnect with reason: (\d+)"                         # logged on drop (277) and leave (285)
$httpClient = New-Object System.Net.Http.HttpClient
$settingsPath = Join-Path (Split-Path -Parent ([Environment]::GetCommandLineArgs()[0])) "RobloxWatchdog.json"

trap
{
    Write-Host "ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

# ---- Settings window ---------------------------------------------------------------

function Get-SavedSettings
{
    if (-not (Test-Path $settingsPath))
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
        }
    }

    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $settings = @{}
    foreach ($property in $json.PSObject.Properties)
    {
        $settings[$property.Name] = [string]$property.Value
    }
    return $settings
}

function Show-SettingsWindow($saved)
{
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Roblox Watchdog"
    $form.Size = New-Object System.Drawing.Size(460, 500)
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
    if ($settings.PlaceId -notmatch '^\d+$') { throw "Place ID must be a number" }
    if ($settings.AccountManagerPort -notmatch '^\d+$') { throw "Port must be a number" }
    if ($settings.AccountManagerPassword.Length -lt 6) { throw "RAM password must match the Webserver Password in RAM (RAM requires 6+ characters for LaunchAccount)" }
    foreach ($key in "MinimumFreeMegabytes", "RelaunchDelaySeconds", "MaximumSessionMinutes")
    {
        if ($settings[$key] -notmatch '^\d+$') { throw "$key must be a number" }
    }
}

$settings = Show-SettingsWindow (Get-SavedSettings)
Test-Settings $settings
$settings | ConvertTo-Json | Set-Content $settingsPath

$mainAccount = $settings.MainAccount
$altAccounts = $settings.AltAccounts -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$placeId = $settings.PlaceId
$privateServerLink = $settings.PrivateServerLink                                     # full link, RAM resolves it; empty = public
$accountManagerPort = [int]$settings.AccountManagerPort
$accountManagerPassword = $settings.AccountManagerPassword
$minimumFreeMegabytes = [int]$settings.MinimumFreeMegabytes
$relaunchDelaySeconds = [int]$settings.RelaunchDelaySeconds
$maximumSessionMinutes = [int]$settings.MaximumSessionMinutes

# ---- Watchdog ----------------------------------------------------------------------

function Write-Log($message)
{
    Write-Host "$(Get-Date -Format HH:mm:ss) $message"
}

function Get-RobloxClients
{
    Get-Process $processName -ErrorAction SilentlyContinue |
        Where-Object { $_.WorkingSet64 -gt $minimumClientBytes }
}

function Get-FreeMegabytes
{
    (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024
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
        throw "Client PID $processId never showed a window"
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
    $response = $httpClient.GetAsync($url).GetAwaiter().GetResult()                  # HTTP response
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()           # RAM's reply text
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
                Write-Log "killed RobloxInstaller for $accountName, retrying launch"
                Start-Sleep -Milliseconds 500
                $ramReply = Invoke-AccountManager $launchUrl
            }
        }

        $newClient = Get-Process $processName -ErrorAction SilentlyContinue |
            Where-Object { $trackedIds -notcontains $_.Id -and $_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime |
            Select-Object -First 1

        if ($newClient) { return $newClient.Id }
    }

    throw "No new Roblox window appeared after launching $accountName (RAM replied: $ramReply)"
}

function Get-PlayerLogFiles
{
    Get-ChildItem $logFolder -Filter "*_Player_*.log"
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
        $stream.Seek($session.LogOffset, "Begin") | Out-Null
        $text = (New-Object System.IO.StreamReader($stream)).ReadToEnd()              # new log lines
        $session.LogOffset = $stream.Position
        return $text
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
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Start-Session($accountName)
{
    $session = $sessions[$accountName]
    $launchTime = Get-Date                                                            # log files after this are new
    $session.ProcessId = Start-Client $accountName
    $session.LogPath = Find-NewLogFile $launchTime
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
    Stop-Process -Id $session.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Log "$accountName (PID $($session.ProcessId)) $reason, relaunching in $relaunchDelaySeconds s"
    $session.ProcessId = 0
    $session.LogPath = $null
    $session.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
}

# Main first, so it is relaunched before any alt
$allAccounts = @($mainAccount) + $altAccounts
$sessions = @{}
foreach ($accountName in $allAccounts)
{
    $sessions[$accountName] = @{ ProcessId = 0; StartedAt = $null; RelaunchAfter = (Get-Date); LogPath = $null; LogOffset = 0 }
}

# A running client is adopted as main; everything else is untracked and closed
$runningMain = Get-RobloxClients | Sort-Object StartTime | Select-Object -First 1
if ($runningMain)
{
    $sessions[$mainAccount].ProcessId = $runningMain.Id
    $sessions[$mainAccount].StartedAt = $runningMain.StartTime
    $sessions[$mainAccount].LogPath = Find-StartupLogFile $runningMain
    Write-Log "adopted PID $($runningMain.Id) as main $mainAccount, log $(Split-Path -Leaf $sessions[$mainAccount].LogPath)"
    Set-ClientWindow $runningMain.Id 0                                                # main is always slot 0
}
Write-Log "alts: $($altAccounts -join ', ')"

Get-Process $processName -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $sessions[$mainAccount].ProcessId -and $_.MainWindowHandle -ne 0 } |
    ForEach-Object {
        Stop-Process -Id $_.Id -Force
        Write-Log "closed leftover PID $($_.Id)"
    }

while ($true)
{
    $freeMegabytes = Get-FreeMegabytes
    if ($freeMegabytes -lt $minimumFreeMegabytes)
    {
        $largestAlt = Get-RobloxClients |
            Where-Object { $_.Id -ne $sessions[$mainAccount].ProcessId } |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 1

        if (-not $largestAlt)
        {
            throw "Free memory is $([int]$freeMegabytes) MB and no alt is left to kill"
        }

        Stop-Process -Id $largestAlt.Id -Force
        Write-Log "killed PID $($largestAlt.Id) ($([int]($largestAlt.WorkingSet64 / 1MB)) MB), free was $([int]$freeMegabytes) MB"
    }

    foreach ($accountName in $allAccounts)
    {
        $session = $sessions[$accountName]

        if ($session.ProcessId -eq 0)
        {
            if ((Get-Date) -gt $session.RelaunchAfter) { Start-Session $accountName }
            continue
        }

        if (-not (Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue))
        {
            Stop-Session $accountName "is gone"
            continue
        }

        $disconnectReason = Get-DisconnectReason $session                             # $null = still connected
        if ($disconnectReason)
        {
            Stop-Session $accountName "disconnected (reason $disconnectReason)"
        }
        elseif ($accountName -ne $mainAccount -and ((Get-Date) - $session.StartedAt).TotalMinutes -gt $maximumSessionMinutes)
        {
            Stop-Session $accountName "is older than $maximumSessionMinutes min"
        }
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}