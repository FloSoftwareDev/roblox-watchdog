download

[Download RobloxWatchdog.exe](https://github.com/FloSoftwareDev/roblox-watchdog/releases/latest/download/RobloxWatchdog.exe)

what it does

launches your alts into the private server through Roblox Account Manager (RAM, required, see below)
relaunches any account that crashes or gets kicked, main included
notices a client that launched but never got into the game and relaunches it
relogs alts every X minutes so they don't go stale (main is never relogged)
keeps the clients awake so Roblox doesn't kick them for being idle
caps Roblox's frame rate so the clients don't eat your CPU rendering frames nobody looks at
tiles all the windows so they don't stack, spread over all your monitors, and puts them back where you dragged them
if your PC runs low on RAM, it closes the heaviest alt instead of letting everything freeze
clears out the leftover Roblox processes that pile up in Task Manager
tells you on Discord when something actually needs you
starts itself again if it crashes
keeps retrying with a growing delay when a launch fails, instead of dying

you need Roblox Account Manager

[Roblox Account Manager](https://github.com/ic3w0lf22/Roblox-Account-Manager) (RAM) is required. This watchdog does not log into anything by itself and never touches your passwords or cookies. It only tells RAM "launch this account into this place", and RAM does the actual logging in. Without RAM running, nothing will start.

So the order is: install RAM, add your accounts to it, then run this.

RAM was archived in October 2024, so it isn't maintained any more, but 3.7.2 still works. Grab it from the Releases page of that repo.

setup

In RAM go to Settings > Developer: turn on Enable Web Server, Allow LaunchAccount Method, and set a Webserver Password (6+ characters)
Don't run RAM as admin, or autoclickers won't work on the Roblox windows. If you do run it as admin then the clients are admin too, and Windows won't let a normal program touch them: tiling, anti-idle and closing strays all get denied. In that case run the watchdog as admin as well. The window says which it is along the top.
Start your main account first
Fill in: alt usernames (one per line), place ID, private server link (paste the full share link), RAM port + password, and the limits
Hit start and go touch grass

heads up: by default it closes any other Roblox windows besides your main when it starts. Untick "Close other Roblox windows on start" if you don't want that.

also: it works out which client is your main by taking the oldest one that's already running. If you start it with an alt open and your main closed, that alt gets treated as main, which means it never gets relogged and never gets closed to free memory. There is no way to ask a running client which account it is, so if that matters, close everything before starting.

the window

A strip along the top says whether it's running as administrator, because that one thing silently breaks tiling, anti-idle and stray cleanup.

Under that: how many accounts are playing, free memory, strays closed, how long the watchdog has been up, and how long since the last disconnect. Then a row per account with a coloured dot, what it's doing, its memory, how long it's been up, and how many times it has dropped. The drop count goes amber at five, which is how you spot one account that's having a worse time than the others. Select a row and the line underneath shows its total uptime and when it last dropped, and why.

Select one or several accounts and you can relaunch or pause just those. Pause on its own stops relaunching, anti-idle and stray cleanup without closing anything, for when you want to work or record.

Closing the window keeps the watchdog running in the tray. Use Exit, or the tray menu, to actually stop it.

discord alerts

Paste a webhook url into the settings and hit Test, which sends a message straight away so you know it works before you rely on it.

It only sends things worth looking at: it started, it crashed and whether it's coming back, an account has failed five launches in a row, memory ran out with nothing left to close, it's missing permissions, and several accounts dropping at once. Ordinary single disconnects are not sent, because there were 152 of them in four days and that would be noise rather than a notification.

"Discord alerts every min" is a periodic status message and is off by default. The alerts above work whether or not you turn it on.

if it crashes

It starts itself again, and that copy goes straight in without showing the settings window, because nobody is there to press Start. Pressing Exit is not a crash, so a deliberate stop stays stopped. If it crashes three times in ten minutes it gives up and stays down rather than respawning for ever, and it tells you on Discord either way.

This catches the watchdog erroring, which is what happened on 24-09 when it died and the accounts sat dead for 74 minutes. It won't catch the process being killed outright, from Task Manager or by Windows, because nothing gets to run in that case.

about the frame rate cap

Running a bunch of clients is usually CPU bound, not RAM bound. Uncapped, each client renders as fast as it can and burns a whole lot of cores for an AFK farm that doesn't need it. 6 clients on a 12 core CPU went from 10 cores down to under 7 just by capping to 30.

The cap goes into Roblox's own settings, and Roblox resets it to unlimited whenever a client closes, so the watchdog writes it again at startup and before every launch. Set it to 0 if you'd rather leave Roblox alone.

A client only picks up the cap when it launches, so an already running client (like a main you adopted) keeps whatever it started with until it relaunches.

about anti-idle

Roblox kicks a client after 20 minutes without input, and it only counts input while the window has focus. So there is no way around it: the window has to come to the front for a moment to get the keystroke. The watchdog puts your previous window back straight after, so it isn't supposed to interrupt what you were doing.

Default is every 15 minutes per account, and each account is on its own timer starting from when it joined, so they don't all do it at once. Max is 18, because 20 is when Roblox pulls the plug. Set it to 0 to turn it off.

Default key is Space, which is the most reliable thing to register as input but does make your character jump. Any single letter works too, so pick something your game ignores if jumping is a problem.

Two things to know. With several accounts you'll see a brief focus flicker every few minutes, and if you happen to be typing at that exact moment the keystroke goes to Roblox instead of to you. And if Windows refuses to hand over focus, the keystroke is skipped and it tries again a minute later rather than fighting for it.

about the window layout

Accounts are shared out over your monitors in proportion to how much screen area each one has, and then tiled inside each screen. Nothing is tiled across the gap between two monitors, so no window ever ends up half on one screen and half on the other. Main keeps the top left slot on your main screen.

On a 2560x1440 plus a 1920x1080, six accounts go from 853x700 each to four at 1280x720 and two at 960x1080, which is roughly 60% more room per window.

Drag a window somewhere and that's where that account goes from then on, instead of back into the grid. Roblox nudging its own window by a few pixels doesn't count as you moving it. Untick "Put windows back where I dragged them" to go back to the grid and forget the saved spots.

Untick "Spread the windows over all monitors" to keep everything on the main screen, which is handy if you are recording or want the second screen for something else.

about stuck clients and strays

There are two ways an account can die that a disconnect code never tells you about, and both used to leave you to find it by hand.

The first: the client launches fine, gets a window, and then fails to reach the game server. It sits on an error screen forever. Roblox never writes a disconnect code for this, because it never connected in the first place, so watching for disconnects will never catch it. This actually happened on 25-09: a private server shut down, four accounts relaunched, all four failed to connect with "Failed to connect to server, no response" and sat there for 42 minutes. The watchdog now waits for the client to report that it is really in the game, and relaunches it if that hasn't happened within 150 seconds.

The second: Roblox spawns a helper process when a client shuts down, and those never exit. No window, about 175 MB each, and they build up until you go and force close them in Task Manager. The watchdog now closes any Roblox process it didn't launch that has no window and has been sitting there past the grace period. Default is 3 minutes, 0 turns it off. An untracked client that does have a window is left alone and only mentioned in the log, in case you started it yourself.

where things are saved

Everything lives in %LOCALAPPDATA%\RobloxWatchdog\:

RobloxWatchdog.json, your settings. The RAM password in it is encrypted for your Windows account only, so a copy of the file is useless anywhere else
RobloxWatchdog.log, everything the watchdog did, including why it stopped. The Log button in the window shows the same thing
WindowPositions.json, where you dragged each account's window

Settings get saved, so next time it's just start.
