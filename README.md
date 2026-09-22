download

[Download RobloxWatchdog.exe](https://github.com/FloSoftwareDev/roblox-watchdog/releases/latest/download/RobloxWatchdog.exe)

what it does

launches your alts into the private server through Roblox Account Manager (RAM, required, see below)
relaunches any account that crashes or gets kicked, main included
relogs alts every X minutes so they don't go stale (main is never relogged)
if your PC runs low on RAM, it closes the heaviest alt instead of letting everything freeze
tiles all the windows so they don't stack, main always in the top left
keeps retrying with a growing delay when a launch fails, instead of dying
caps Roblox's frame rate so the clients don't eat your CPU rendering frames nobody looks at

you need Roblox Account Manager

[Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager) (RAM) is required. This watchdog does not log into anything by itself and never touches your passwords or cookies. It only tells RAM "launch this account into this place", and RAM does the actual logging in. Without RAM running, nothing will start.

So the order is: install RAM, add your accounts to it, then run this.

RAM was archived in October 2024, so it isn't maintained any more, but 3.7.2 still works. Grab it from the Releases page of that repo.

setup

In RAM go to Settings > Developer: turn on Enable Web Server, Allow LaunchAccount Method, and set a Webserver Password (6+ characters)
Don't run RAM as admin, or autoclickers won't work on the Roblox windows
Start your main account first
Run the script and fill in: alt usernames (one per line), place ID, private server link (paste the full share link), RAM port + password, and the limits (free MB, seconds between launches, relog minutes, frame rate cap)
Hit start and go touch grass 

heads up: by default it closes any other Roblox windows besides your main when it starts. Untick "Close other Roblox windows on start" if you don't want that.

about the frame rate cap

Running a bunch of clients is usually CPU bound, not RAM bound. Uncapped, each client renders as fast as it can and burns a whole lot of cores for an AFK farm that doesn't need it. 6 clients on a 12 core CPU went from 10 cores down to under 7 just by capping to 30.

The cap goes into Roblox's own settings, and Roblox resets it to unlimited whenever a client closes, so the watchdog writes it again at startup and before every launch. Set it to 0 if you'd rather leave Roblox alone.

A client only picks up the cap when it launches, so an already running client (like a main you adopted) keeps whatever it started with until it relaunches.

Settings get saved, so next time it's just start. They live in %LOCALAPPDATA%\RobloxWatchdog\, the RAM password is encrypted for your Windows account only, and the run log is next to it in RobloxWatchdog.log.
