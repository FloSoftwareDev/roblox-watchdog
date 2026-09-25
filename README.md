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
keeps the clients awake so Roblox doesn't kick them for being idle
notices a client that launched but never got into the game and relaunches it
clears out the leftover Roblox processes that pile up in Task Manager

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

about anti-idle

Roblox kicks a client after 20 minutes without input, and it only counts input while the window has focus. So there is no way around it: the window has to come to the front for a moment to get the keystroke. The watchdog puts your previous window back straight after, so it isn't supposed to interrupt what you were doing.

Default is every 15 minutes per account, and each account is on its own timer starting from when it joined, so they don't all do it at once. Max is 18, because 20 is when Roblox pulls the plug. Set it to 0 to turn it off.

Default key is Space, which is the most reliable thing to register as input but does make your character jump. Any single letter works too, so pick something your game ignores if jumping is a problem.

Two things to know. With several accounts you'll see a brief focus flicker every few minutes, and if you happen to be typing at that exact moment the keystroke goes to Roblox instead of to you. And if Windows refuses to hand over focus, the keystroke is skipped and it tries again a minute later rather than fighting for it.

about stuck clients and strays

There are two ways an account can die that a disconnect code never tells you about, and both used to leave you to find it by hand.

The first: the client launches fine, gets a window, and then fails to reach the game server. It sits on an error screen forever. Roblox never writes a disconnect code for this, because it never connected in the first place, so watching for disconnects will never catch it. This actually happened on 25-09: a private server shut down, four accounts relaunched, all four failed to connect with "Failed to connect to server, no response" and sat there for 42 minutes. The watchdog now waits for the client to report that it is really in the game, and relaunches it if that hasn't happened within 150 seconds.

The second: Roblox spawns a helper process when a client shuts down, and those never exit. No window, about 175 MB each, and they build up until you go and force close them in Task Manager. The watchdog now closes any Roblox process it didn't launch that has no window and has been sitting there past the grace period. Default is 3 minutes, 0 turns it off. An untracked client that does have a window is left alone and only mentioned in the log, in case you started it yourself.

Fatal errors are also written to the log file now. They used to only go to the console, so if the watchdog died while you were asleep there was nothing to look at afterwards.

Settings get saved, so next time it's just start. They live in %LOCALAPPDATA%\RobloxWatchdog\, the RAM password is encrypted for your Windows account only, and the run log is next to it in RobloxWatchdog.log.
