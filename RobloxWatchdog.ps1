#------------------------------------------------------------------------------------#
# Name script          : RobloxWatchdog.ps1
# Description         : Settings window, then: launches alts through Roblox Account
#                        Manager, relogs them when they die or get old, and kills the
#                        largest alt when RAM is low. The oldest running client at
#                        startup is treated as the main account.
# Name Developer    : SleepyFlo
# Project              : Miniwar AFK
# Date               : 18-09-2026
#------------------------------------------------------------------------------------#

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

$processName = "RobloxPlayerBeta"
$minimumClientBytes = 500MB
$checkIntervalSeconds = 10
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
    $form.Size = New-Object System.Drawing.Size(460, 470)
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

    Add-Row "Alt usernames (one per line)" "AltAccounts" 100 $false
    Add-Row "Place ID" "PlaceId" 20 $false
    Add-Row "Private server link (optional)" "PrivateServerLink" 20 $false
    Add-Row "RAM web server port" "AccountManagerPort" 20 $false
    Add-Row "RAM web server password" "AccountManagerPassword" 20 $true
    Add-Row "Kill an alt below free MB" "MinimumFreeMegabytes" 20 $false
    Add-Row "Seconds between launches" "RelaunchDelaySeconds" 20 $false
    Add-Row "Relog alts after minutes" "MaximumSessionMinutes" 20 $false

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "Start the MAIN account first. The oldest running client is protected."
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
    if (-not $settings.AltAccounts) { throw "At least one alt username is required" }
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

function Set-AltWindow($processId, $slotIndex)
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
        throw "Alt PID $processId never showed a window"
    }

    # Roblox restores its own saved size right after the window appears; move after that
    Start-Sleep -Seconds 5

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $columns = [math]::Ceiling([math]::Sqrt($altAccounts.Count))
    $rows = [math]::Ceiling($altAccounts.Count / $columns)
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
    # is only logged; the new Roblox window in Start-Alt is the real success check
    Write-Log "RAM: $($url -replace 'Password=[^&]+', 'Password=***')"
    $response = $httpClient.GetAsync($url).GetAwaiter().GetResult()                  # HTTP response
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()           # RAM's reply text
    $reply = "$([int]$response.StatusCode) '$($response.ReasonPhrase)' $body"         # status + text for logs
    Write-Log "RAM replied: $reply"
    return $reply
}

function Start-Alt($accountName)
{
    $trackedIds = @($mainProcessId) + @($altSessions.Values | ForEach-Object { $_.ProcessId })

    $launchUrl = Get-LaunchUrl $accountName
    $ramReply = Invoke-AccountManager $launchUrl                                      # last RAM answer
    Write-Log "launched $accountName"

    # Poll every 200 ms so we kill RobloxInstaller before it can close other instances
    $installerKilled = $false
    for ($attempt = 0; $attempt -lt 450; $attempt++)   # 450 × 200 ms = 90 s
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

$mainProcess = Get-RobloxClients | Sort-Object StartTime | Select-Object -First 1
if (-not $mainProcess)
{
    throw "No Roblox client is running. Start the main account first, then run this."
}
$mainProcessId = $mainProcess.Id
Write-Log "protecting PID $mainProcessId as main"
Write-Log "alts: $($altAccounts -join ', ')"


# Alts left over from an earlier run are untracked; start from only the main
Get-Process $processName -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $mainProcessId -and $_.MainWindowHandle -ne 0 } |
    ForEach-Object {
        Stop-Process -Id $_.Id -Force
        Write-Log "closed leftover PID $($_.Id)"
    }

$altSessions = @{}
foreach ($accountName in $altAccounts)
{
    $altSessions[$accountName] = @{ ProcessId = 0; StartedAt = $null; RelaunchAfter = (Get-Date) }
}

while ($true)
{
    if (-not (Get-Process -Id $mainProcessId -ErrorAction SilentlyContinue))
    {
        throw "Main client (PID $mainProcessId) is no longer running"
    }

    $freeMegabytes = Get-FreeMegabytes
    if ($freeMegabytes -lt $minimumFreeMegabytes)
    {
        $largestAlt = Get-RobloxClients |
            Where-Object { $_.Id -ne $mainProcessId } |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 1

        if (-not $largestAlt)
        {
            throw "Free memory is $([int]$freeMegabytes) MB and no alt is left to kill"
        }

        Stop-Process -Id $largestAlt.Id -Force
        Write-Log "killed PID $($largestAlt.Id) ($([int]($largestAlt.WorkingSet64 / 1MB)) MB), free was $([int]$freeMegabytes) MB"
    }

    foreach ($accountName in $altAccounts)
    {
        $session = $altSessions[$accountName]
        $processAlive = $session.ProcessId -ne 0 -and (Get-Process -Id $session.ProcessId -ErrorAction SilentlyContinue)
        $sessionExpired = $processAlive -and ((Get-Date) - $session.StartedAt).TotalMinutes -gt $maximumSessionMinutes

        if ($sessionExpired)
        {
            Stop-Process -Id $session.ProcessId -Force
            Write-Log "$accountName session older than $maximumSessionMinutes min, relogging"
            $processAlive = $false
        }

        if (-not $processAlive -and (Get-Date) -gt $session.RelaunchAfter)
        {
            $session.ProcessId = Start-Alt $accountName
            $session.StartedAt = Get-Date
            Write-Log "$accountName running as PID $($session.ProcessId)"

            # Staggers the next launch so accounts don't join at the same second
            foreach ($otherName in $altAccounts)
            {
                if ($altSessions[$otherName].ProcessId -eq 0)
                {
                    $altSessions[$otherName].RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
                }
            }

            Set-AltWindow $session.ProcessId ([array]::IndexOf($altAccounts, $accountName))
        }
        elseif (-not $processAlive -and $session.ProcessId -ne 0)
        {
            Write-Log "$accountName (PID $($session.ProcessId)) is gone, relaunching in $relaunchDelaySeconds s"
            $session.ProcessId = 0
            $session.RelaunchAfter = (Get-Date).AddSeconds($relaunchDelaySeconds)
        }
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}