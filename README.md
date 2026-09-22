download

[Download RobloxWatchdog.exe](https://github.com/FloSoftwareDev/roblox-watchdog/releases/latest/download/RobloxWatchdog.exe)

what it does

launches your alts into the private server through Roblox Account Manager (RAM)
relaunches any account that crashes or gets kicked, main included
relogs alts every X minutes so they don't go stale (main is never relogged)
if your PC runs low on RAM, it closes the heaviest alt instead of letting everything freeze
tiles all the windows so they don't stack, main always in the top left
keeps retrying with a growing delay when a launch fails, instead of dying

setup

In RAM go to Settings > Developer: turn on Enable Web Server, Allow LaunchAccount Method, and set a Webserver Password (6+ characters)
Don't run RAM as admin, or autoclickers won't work on the Roblox windows
Start your main account first
Run the script and fill in: alt usernames (one per line), place ID, private server link (paste the full share link), RAM port + password, and the limits (free MB, seconds between launches, relog minutes)
Hit start and go touch grass 

heads up: by default it closes any other Roblox windows besides your main when it starts. Untick "Close other Roblox windows on start" if you don't want that.

Settings get saved, so next time it's just start. They live in %LOCALAPPDATA%\RobloxWatchdog\, the RAM password is encrypted for your Windows account only, and the run log is next to it in RobloxWatchdog.log.
